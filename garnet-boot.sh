#!/bin/bash
# garnet-boot.sh - GARNET-IOS boot menu around ./xl.
# Run from the repository root: ./garnet-boot.sh
# Needs the garnet loader on the phone (fastboot boot garnet-boot.img);
# it refuses to boot when the phone is not in loader state.
# 1 push ramdisk, 2 release boot, 3 verbose boot + live log,
# 4 custom boot-args + live log, 5 reboot to Android, 0 quit.
# Live logs go to logs/garnet-boot-YYYYMMDD-HHMMSS.txt.
# During a log run, press S to save early, then upload to GoFile or go back.
# Runs stay up 900 s by default (XL_SECS); set XL_SECS before opening
# the menu to change it.

set -u
cd "$(dirname "$(readlink -f "$0")")" || exit 1

MAGENTA=$'\033[1;35m'
CYAN=$'\033[0;36m'
GREEN=$'\033[1;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[1;31m'
RESET=$'\033[0m'
SEP='------------------------------------------------------------'

DEFAULT_ARGS="garnet_touch=1 garnet_buttons=1 garnet_cpufreq=1 bootcpu=7 cpus=8 gpu_recover=1 fb_filter=0"
RAMDISK="userland/system.apfs"

show_menu() {
    command -v clear >/dev/null && [ -n "${TERM:-}" ] && clear
    printf '%b\n' "${MAGENTA}"
    printf '%s\n' '  ____     _     ____   _   _   _____   _____            ___    ___    ____  '
    printf '%s\n' ' / ___|   / \   |  _ \  | \ | | | ____| |_   _|          |_ _|  / _ \  / ___| '
    printf '%s\n' '| |  _   / _ \  | |_) | |  \| | |  _|     | |   ___   | |  | | | | \___ \ '
    printf '%s\n' '| |_| | / ___ \ |  _ <  | |\  | | |___    | |             | |  | |_| |  ___) |'
    printf '%s\n' ' \____| /_/   \_\|_| \_\ |_| \_| |_____|   |_|            |___|  \___/  |____/ '
    printf '%b\n' "${RESET}"
    printf '%b\n' "${YELLOW}Maintained by Jotan${RESET}"
    printf '%b\n' "${CYAN}${SEP}${RESET}"
    printf '%bRunning: %b%s\n' "${CYAN}" "${RESET}" "$PWD"
    local missing=()
    local kernel="${XL_KERNEL:-prebuilt/mach.development.bcm2837}"
    [ -f "$kernel" ] || missing+=("kernel ($kernel)")
    [ -f "$RAMDISK" ] || missing+=("ramdisk ($RAMDISK)")
    [ -f "userland/root.apfs" ] || missing+=("root.apfs")
    if [ "${#missing[@]}" -eq 0 ]; then
        printf '%bStatus: %b✓ Ready to Start - all Files Found%b\n' "${CYAN}" "${GREEN}" "${RESET}"
    else
        printf '%bStatus: %b✗ Missing files: %s%b\n' "${CYAN}" "${RED}" "${missing[*]}" "${RESET}"
    fi
    printf '%b\n' "${CYAN}${SEP}${RESET}"
    printf '  %b1)%b Push Ramdisk (System)\n' "${GREEN}" "${RESET}"
    printf '  %b2)%b Load Hack-iOS (Release)\n' "${GREEN}" "${RESET}"
    printf '  %b3)%b Load Hack-iOS (Log Debug)\n' "${GREEN}" "${RESET}"
    printf '  %b4)%b Load Hack-iOS (Debug + Custom Args)\n' "${GREEN}" "${RESET}"
    printf '  %b5)%b Reboot to Android Mode\n' "${GREEN}" "${RESET}"
    printf '  %b0)%b Quit\n' "${GREEN}" "${RESET}"
    printf '%b\n' "${CYAN}${SEP}${RESET}"
}

need_xl() {
    if [ ! -x ./xl ]; then
        printf '%berror: ./xl not found. Run this script from the repository root.%b\n' "${RED}" "${RESET}"
        return 1
    fi
}

check_loader() {
    local st
    st="$(./xl state 2>/dev/null)"
    if [ "$st" = "loader" ]; then
        return 0
    fi
    if [ "$st" = "absent" ] || [ -z "$st" ]; then
        printf '%berror: no fastboot device found at all. Connect the phone first.%b\n' "${RED}" "${RESET}"
    else
        printf '%berror: phone is not in loader state (state: %s).%b\n' "${RED}" "$st" "${RESET}"
        echo "Boot the garnet loader first: fastboot boot garnet-boot.img"
    fi
    return 1
}

push_ramdisk() {
    need_xl || return 1
    check_loader || return 1
    printf '%bPushing the ramdisk (%s). This takes a few minutes.%b\n' "${CYAN}" "$RAMDISK" "${RESET}"
    ./xl ramdisk "$RAMDISK"
}

upload_log() {
    local logfile="$1"
    local uploader=""
    if command -v gofile >/dev/null 2>&1; then
        uploader="gofile"
    elif [ -x "$HOME/gofile" ]; then
        uploader="$HOME/gofile"
    fi
    if [ -z "$uploader" ]; then
        printf '%bGoFile not found. Preparing the environment...%b\n' "${YELLOW}" "${RESET}"
        if ! command -v wget >/dev/null 2>&1; then
            printf '%bwget is not available, cannot download the uploader.%b\n' "${RED}" "${RESET}"
            return 1
        fi
        if wget -q https://raw.githubusercontent.com/kenway214/GoFile-Upload-Script/master/upload.sh -O "$HOME/gofile" && chmod +x "$HOME/gofile"; then
            uploader="$HOME/gofile"
            printf '%bGoFile ready.%b\n' "${GREEN}" "${RESET}"
        else
            printf '%bFailed to download the GoFile uploader.%b\n' "${RED}" "${RESET}"
            return 1
        fi
    fi
    printf '%bUploading %s to GoFile...%b\n' "${CYAN}" "$logfile" "${RESET}"
    "$uploader" "$logfile"
}

save_and_offer() {
    local logfile="$1"
    local weight
    weight="$(du -h "$logfile" 2>/dev/null | cut -f1)"
    printf '%bLogs saved: %s%b\n' "${GREEN}" "$logfile" "${RESET}"
    printf 'Weight: %s\n' "${weight:-unknown}"
    while true; do
        printf '  %b1)%b Upload to GoFile (Recommended for Debug)\n' "${GREEN}" "${RESET}"
        printf '  %b2)%b Back\n' "${GREEN}" "${RESET}"
        read -r -p "$(printf '%bChoose an option: %b' "${YELLOW}" "${RESET}")" sub || return 0
        case "$sub" in
            1) upload_log "$logfile" ;;
            2) return 0 ;;
            *) printf '%bInvalid option.%b\n' "${RED}" "${RESET}" ;;
        esac
    done
}

VALID_BOOT_ARGS=(
    "-v" "debug" "rd" "garnet_root_end" "loader_return_after" "epoch" "sb_delay"
    "garnet_touch" "garnet_buttons" "garnet_cpufreq" "bootcpu" "cpus" "gpu_recover"
    "fb_filter" "gpu" "metal" "camtl" "adreno_speed" "touch_lat" "cpuload" "ca_vbl"
    "applog" "applog_name" "detlog" "ddr" "quiet" "fb_ca_hz" "fb_hz" "fb_measure"
    "adreno" "adreno_pause" "adreno_return" "adreno_skip" "adreno_watch"
    "wifi_join" "wpss" "var_store" "mediamtl" "ca_metallib" "rwa_packed16"
    "metal_all" "metal-all" "metal_sb" "metal_procs" "metal_watch" "caenv" "fb_queue" "gpu_log" "ui_lite"
)

validate_boot_args() {
    local args="$1"
    local invalid=()
    for token in $args; do
        local key="${token%%=*}"
        local match=0
        for valid in "${VALID_BOOT_ARGS[@]}"; do
            if [ "$key" = "$valid" ]; then
                match=1
                break
            fi
        done
        if [ "$match" -eq 0 ]; then
            invalid+=("$token")
        fi
    done
    if [ "${#invalid[@]}" -gt 0 ]; then
        printf '%bWARNING: Unrecognized boot argument(s): %s%b\n' "${YELLOW}" "${invalid[*]}" "${RESET}"
        read -r -p "$(printf '%bDo you want to proceed with booting? [y/N]: %b' "${YELLOW}" "${RESET}")" confirm
        case "$confirm" in
            [yY]|[yY][eE][sS]) return 0 ;;
            *) return 1 ;;
        esac
    fi
    return 0
}

boot_system() {
    local args="$1"
    local with_log="$2"
    local stamp logfile run_pid saved_early key
    need_xl || return 1
    check_loader || return 1
    validate_boot_args "$args" || return 1
    printf '%bBooting with args: %s%b\n' "${CYAN}" "$args" "${RESET}"
    : "${XL_SECS:=900}"
    export XL_SECS
    printf '%bKernel returns to the loader after %s s.%b\n' "${CYAN}" "$XL_SECS" "${RESET}"
    echo "Note: push the ramdisk first (option 1) unless one is already resident."
    if [ "$with_log" = "1" ]; then
        mkdir -p logs
        local slug=""
        [[ "$args" =~ touch_lat=([0-9]+) ]] && slug="${slug}_tl${BASH_REMATCH[1]}"
        [[ "$args" =~ cpuload=([0-9]+) ]] && slug="${slug}_cpu${BASH_REMATCH[1]}"
        [[ "$args" =~ camtl=([0-9]+) ]] && slug="${slug}_camtl${BASH_REMATCH[1]}"
        [[ "$args" =~ ca_vbl=([0-9]+) ]] && slug="${slug}_vbl${BASH_REMATCH[1]}"
        [[ "$args" =~ metal=([0-9]+) ]] && slug="${slug}_mtl${BASH_REMATCH[1]}"
        [[ "$args" =~ ddr=([0-9]+) ]] && slug="${slug}_ddr${BASH_REMATCH[1]}"
        stamp="$(date +%Y%m%d-%H%M%S)"
        logfile="logs/garnet-boot-${stamp}${slug}.txt"
        printf '%bLive log: %s%b\n' "${GREEN}" "$logfile" "${RESET}"
        printf '%bPress S to save the logs early if needed.%b\n' "${YELLOW}" "${RESET}"
        export XL_FOLLOW=2
        XL_CMDLINE="$args" ./xl run &
        run_pid=$!
        trap 'kill "$run_pid" 2>/dev/null' INT TERM
        saved_early=0
        # Flush any lingering stdin from paste/menu
        while read -t 0.05 -n 1000 _; do :; done 2>/dev/null
        while kill -0 "$run_pid" 2>/dev/null; do
            latest_live=$(ls -t logs/*-run.log.live 2>/dev/null | head -n 1)
            if [ -n "$latest_live" ] && [ -s "$latest_live" ]; then
                cp -f "$latest_live" "$logfile" 2>/dev/null
            fi
            if [ -t 0 ]; then
                key=""
                if read -t 1 -n 1 -s key 2>/dev/null; then
                    if [ "$key" = $'\e' ]; then
                        # Discard terminal escape sequences
                        while read -t 0.05 -n 1000 _; do :; done 2>/dev/null
                    elif [ "$key" = "s" ] || [ "$key" = "S" ]; then
                        saved_early=1
                        break
                    fi
                fi
            else
                sleep 1
            fi
        done
        trap - INT TERM
        if [ "$saved_early" = "1" ]; then
            echo "Stopped early (S pressed), asking loader/kernel to stop..."
            timeout 5 ./xl stop >/dev/null 2>&1 || true
            kill "$run_pid" 2>/dev/null
            wait "$run_pid" 2>/dev/null
        else
            wait "$run_pid" 2>/dev/null
        fi
        # Grab final completed or live log
        latest_full=$(ls -t logs/*-run.log logs/*-run.log.live 2>/dev/null | head -n 1)
        if [ -n "$latest_full" ] && [ -s "$latest_full" ]; then
            cp -f "$latest_full" "$logfile" 2>/dev/null
        fi
        # Only fallback to xl log if logfile is missing or tiny (<500 bytes)
        local cur_sz=0
        [ -f "$logfile" ] && cur_sz=$(stat -c%s "$logfile" 2>/dev/null || echo 0)
        if [ "$cur_sz" -lt 500 ]; then
            tmp_log="${logfile}.tmp"
            if timeout 5 ./xl log > "$tmp_log" 2>/dev/null; then
                local tmp_sz
                tmp_sz=$(stat -c%s "$tmp_log" 2>/dev/null || echo 0)
                if [ "$tmp_sz" -gt "$cur_sz" ] && ! grep -q "waiting for the phone" "$tmp_log"; then
                    mv "$tmp_log" "$logfile"
                else
                    rm -f "$tmp_log"
                fi
            else
                rm -f "$tmp_log"
            fi
        fi
        # Check for duplicate byte-identical log
        local prev_log
        prev_log=$(ls -t logs/garnet-boot-*.txt 2>/dev/null | grep -v "$(basename "$logfile")" | head -n 1)
        if [ -n "$prev_log" ] && [ -f "$prev_log" ] && [ -f "$logfile" ]; then
            local prev_hash cur_hash
            prev_hash=$(sha256sum "$prev_log" 2>/dev/null | cut -d' ' -f1)
            cur_hash=$(sha256sum "$logfile" 2>/dev/null | cut -d' ' -f1)
            if [ -n "$prev_hash" ] && [ "$prev_hash" = "$cur_hash" ]; then
                printf '%bWARNING: Log is byte-identical (SHA256: %s) to previous log %s!%b\n' "${YELLOW}" "$cur_hash" "$prev_log" "${RESET}"
            fi
        fi

        # Also auto-export to Downloads storage if accessible
        if [ -d "/storage/emulated/0/Download" ] && [ -s "$logfile" ]; then
            cp -f "$logfile" "/storage/emulated/0/Download/$(basename "$logfile")" 2>/dev/null
        fi

        # Run frames.py automatically if touch_lat was requested
        if [[ "$args" =~ touch_lat=1 ]] && [ -f "tools/frames.py" ]; then
            printf '%b=== Running frames.py latency analysis ===%b\n' "${CYAN}" "${RESET}"
            python3 tools/frames.py "$logfile" || true
            printf '%b=========================================%b\n' "${CYAN}" "${RESET}"
        fi
        save_and_offer "$logfile"
    else
        XL_CMDLINE="$args" ./xl run
    fi
}

reboot_android() {
    need_xl || return 1
    printf '%bRebooting the phone to Android mode.%b\n' "${CYAN}" "${RESET}"
    ./xl reboot
}

while true; do
    show_menu
    read -r -p "$(printf '%bChoose an option: %b' "${YELLOW}" "${RESET}")" choice || exit 0
    case "$choice" in
        1) push_ramdisk ;;
        2) boot_system "$DEFAULT_ARGS" 0 ;;
        3) boot_system "-v $DEFAULT_ARGS" 1 ;;
        4) while true; do
               read -r -p "Boot args (or 'q' to return): " custom
               if [ "$custom" = "q" ] || [ "$custom" = "quit" ]; then
                   break
               fi
               [ -z "$custom" ] && custom="-v $DEFAULT_ARGS"
               if boot_system "$custom" 1; then
                   break
               fi
               printf '%bBoot cancelled. Enter new args or '\''q'\'' to return to menu.%b\n' "${YELLOW}" "${RESET}"
           done ;;
        5) reboot_android ;;
        0) echo "Bye."; exit 0 ;;
        *) printf '%bInvalid option.%b\n' "${RED}" "${RESET}" ;;
    esac
    read -r -p "$(printf '%bPress Enter to continue...%b' "${CYAN}" "${RESET}")" _ || exit 0
done
