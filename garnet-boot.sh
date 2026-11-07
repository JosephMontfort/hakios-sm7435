#!/bin/bash
# garnet-boot.sh - Interactive HakiOS boot manager for POCO X6 5G (garnet / SM7435-AB)
#
# Automatically handles fastboot staging, resident ramdisk uploads, live logging,
# and kernel returns without cold reboots.

set -u
cd "$(dirname "$(readlink -f "$0")")" || exit 1

# Automatically configure temporary directory for Termux and standard Linux environments
if [ -d "/data/data/com.termux/files/usr/tmp" ]; then
    export TMPDIR="/data/data/com.termux/files/usr/tmp"
elif [ -z "${TMPDIR:-}" ] || [ ! -d "${TMPDIR:-}" ]; then
    export TMPDIR="/tmp"
fi
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$TMPDIR}"

# Ensure helper scripts have execution permissions
chmod +x ./xl 2>/dev/null || true
[ -f "xnuloader/mkpayload.py" ] && chmod +x xnuloader/mkpayload.py 2>/dev/null || true
[ -d "tools" ] && chmod +x tools/*.py 2>/dev/null || true

CYAN=$'\033[0;36m'
GREEN=$'\033[1;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[1;31m'
BOLD=$'\033[1m'
RESET=$'\033[0m'
SEP='============================================================'
DIV='------------------------------------------------------------'

DEFAULT_ARGS="garnet_touch=1 garnet_buttons=1 garnet_cpufreq=1 bootcpu=7 cpus=8 gpu=1 gl=1 adreno_speed=8 fb_filter=1 cpuload=500 ddr=2 fb_queue=1 touch_lat=1 ui_lite=1 caenv=CA_DISABLE_DIRTY_REGIONS=1"
RAMDISK="userland/system.apfs"

show_menu() {
    command -v clear >/dev/null && [ -n "${TERM:-}" ] && clear
    printf '%b\n' "${CYAN}${SEP}${RESET}"
    printf '%b        HakiOS Boot Manager - POCO X6 5G (garnet)%b\n' "${BOLD}" "${RESET}"
    printf '%b\n' "${CYAN}${SEP}${RESET}"
    printf '%bDirectory : %b%s\n' "${CYAN}" "${RESET}" "$PWD"

    local kernel="${XL_KERNEL:-mach.development.bcm2837}"
    [ ! -f "$kernel" ] && [ -f "prebuilt/mach.development.bcm2837" ] && kernel="prebuilt/mach.development.bcm2837"
    if [ -f "$kernel" ]; then
        printf '%bKernel    : %b%s (%b✓ Found%b)\n' "${CYAN}" "${RESET}" "$kernel" "${GREEN}" "${RESET}"
    else
        printf '%bKernel    : %b%s (%b✗ Missing%b)\n' "${CYAN}" "${RESET}" "$kernel" "${RED}" "${RESET}"
    fi

    if [ -f "$RAMDISK" ]; then
        local rsize
        rsize="$(du -h "$RAMDISK" 2>/dev/null | cut -f1)"
        printf '%bSystem RD : %b%s (%s, %b✓ Found%b)\n' "${CYAN}" "${RESET}" "$RAMDISK" "$rsize" "${GREEN}" "${RESET}"
    else
        printf '%bSystem RD : %b%s (%b✗ Not in userland/ - see put system.apfs here.txt%b)\n' "${CYAN}" "${RESET}" "$RAMDISK" "${YELLOW}" "${RESET}"
    fi

    printf '%b\n' "${CYAN}${DIV}${RESET}"
    printf '  %b1)%b Push System Ramdisk (system.apfs)\n' "${GREEN}" "${RESET}"
    printf '  %b2)%b Boot HakiOS (Release)\n' "${GREEN}" "${RESET}"
    printf '  %b3)%b Boot HakiOS (Verbose Log)\n' "${GREEN}" "${RESET}"
    printf '  %b4)%b Boot HakiOS (Custom Boot Arguments)\n' "${GREEN}" "${RESET}"
    printf '  %b5)%b Return to XNU Loader (Stop current iOS session)\n' "${GREEN}" "${RESET}"
    printf '  %b0)%b Exit\n' "${GREEN}" "${RESET}"
    printf '%b\n' "${CYAN}${SEP}${RESET}"
}

need_xl() {
    if [ ! -x ./xl ]; then
        printf '%berror: ./xl not found or not executable. Run from release root.%b\n' "${RED}" "${RESET}"
        return 1
    fi
}

check_loader() {
    local st
    st="$(./xl state 2>/dev/null || echo "absent")"
    if [ "$st" = "loader" ]; then
        return 0
    fi
    if [ "$st" = "absent" ] || [ -z "$st" ]; then
        printf '%berror: no fastboot device detected. Connect device in fastboot mode.%b\n' "${RED}" "${RESET}"
    else
        printf '%bDevice is not in loader state (current state: %s).%b\n' "${YELLOW}" "$st" "${RESET}"
        echo "If device is in stock fastboot mode, boot the loader first:"
        echo "  fastboot boot garnet-boot.img"
    fi
    return 1
}

push_ramdisk() {
    need_xl || return 1
    if [ ! -f "$RAMDISK" ]; then
        printf '%berror: %s not found!%b\n' "${RED}" "$RAMDISK" "${RESET}"
        echo "Please download system.apfs and place it in the userland/ directory."
        echo "Refer to userland/put system.apfs here.txt for details."
        return 1
    fi
    check_loader || return 1
    printf '%bPushing system ramdisk (%s) to resident memory...%b\n' "${CYAN}" "$RAMDISK" "${RESET}"
    echo "This takes approximately 1-2 minutes depending on USB transfer speed."
    ./xl ramdisk "$RAMDISK"
}

return_to_loader() {
    need_xl || return 1
    printf '%bRequesting XNU kernel to stop and return to loader...%b\n' "${CYAN}" "${RESET}"
    if ./xl stop; then
        printf '%bKernel returned to resident loader. Resident ramdisk is preserved in RAM.%b\n' "${GREEN}" "${RESET}"
    else
        printf '%bNotice: Phone may already be in loader mode or disconnected.%b\n' "${YELLOW}" "${RESET}"
    fi
}

boot_system() {
    local args="$1"
    local with_log="$2"
    local stamp logfile run_pid key

    need_xl || return 1
    check_loader || return 1

    printf '%bBooting HakiOS with args: %s%b\n' "${CYAN}" "$args" "${RESET}"
    : "${XL_SECS:=900}"
    export XL_SECS

    if [ "$with_log" = "1" ]; then
        mkdir -p logs
        stamp="$(date +%Y%m%d-%H%M%S)"
        logfile="logs/garnet-boot-$stamp.txt"

        printf '%bLive log active. Press %bS%b to save log and detach.%b\n' "${YELLOW}" "${BOLD}" "${YELLOW}" "${RESET}"
        printf '%bNote: Detaching log keeps iOS running. Use Option 5 to return to loader.%b\n' "${CYAN}" "${RESET}"

        local latest_full="logs/$stamp-run.log"
        XL_FOLLOW=1 XL_CMDLINE="$args" ./xl run > "$latest_full" 2>&1 &
        run_pid=$!

        trap 'kill "$run_pid" 2>/dev/null' INT TERM
        # Flush lingering input
        while read -t 0.05 -n 1000 _; do :; done 2>/dev/null

        while kill -0 "$run_pid" 2>/dev/null; do
            local latest_live
            latest_live=$(ls -t logs/*-run.log.live 2>/dev/null | head -n 1)
            if [ -n "$latest_live" ] && [ -s "$latest_live" ]; then
                cp -f "$latest_live" "$logfile" 2>/dev/null
            fi
            if [ -t 0 ]; then
                key=""
                if read -t 1 -n 1 -s key 2>/dev/null; then
                    if [ "$key" = "s" ] || [ "$key" = "S" ]; then
                        printf '\n%bDetaching from log stream... iOS continues running on device.%b\n' "${GREEN}" "${RESET}"
                        kill "$run_pid" 2>/dev/null
                        wait "$run_pid" 2>/dev/null || true
                        break
                    fi
                fi
            else
                sleep 1
            fi
        done
        trap - INT TERM
        wait "$run_pid" 2>/dev/null || true

        # Finalize log file
        local final_cand
        final_cand=$(ls -t logs/*-run.log logs/*-run.log.live 2>/dev/null | head -n 1)
        if [ -n "$final_cand" ] && [ -s "$final_cand" ]; then
            cp -f "$final_cand" "$logfile" 2>/dev/null
        fi

        if [ -f "$logfile" ] && [ -s "$logfile" ]; then
            printf '%bLog saved: %s (%s)%b\n' "${GREEN}" "$logfile" "$(du -h "$logfile" 2>/dev/null | cut -f1)" "${RESET}"
            # Auto-export to Android Downloads storage if in Termux
            if [ -d "/storage/emulated/0/Download" ]; then
                cp -f "$logfile" "/storage/emulated/0/Download/$(basename "$logfile")" 2>/dev/null || true
                printf '%bExported to: /storage/emulated/0/Download/%s%b\n' "${CYAN}" "$(basename "$logfile")" "${RESET}"
            fi
        fi
    else
        XL_CMDLINE="$args" ./xl run
    fi
}

while true; do
    show_menu
    read -r -p "$(printf '%bSelect option [0-5]: %b' "${YELLOW}" "${RESET}")" choice || exit 0
    case "$choice" in
        1) push_ramdisk ;;
        2) boot_system "$DEFAULT_ARGS" 0 ;;
        3) boot_system "-v $DEFAULT_ARGS" 1 ;;
        4)
            read -r -e -i "-v $DEFAULT_ARGS " -p "Edit boot args: " custom
            [ -z "$custom" ] && custom="-v $DEFAULT_ARGS"
            boot_system "$custom" 1
            ;;
        5) return_to_loader ;;
        0) echo "Exiting."; exit 0 ;;
        *) printf '%bInvalid selection.%b\n' "${RED}" "${RESET}" ;;
    esac
    sleep 1
done
