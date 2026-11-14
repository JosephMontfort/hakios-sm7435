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

DEFAULT_ARGS="garnet_touch=1 garnet_buttons=1 garnet_cpufreq=1 bootcpu=7 cpus=8 gpu=1 gl=1 adreno_speed=6 fb_filter=1 cpuload=500 ddr=2 fb_queue=1 touch_lat=1 ui_lite=1 caenv=CA_DISABLE_DIRTY_REGIONS=1 gpu_recover=1"
# Metal: the window server on hakios-metal's plug-in (/redwood/lib/RedwoodMetal.bundle, built by CI into root.apfs)
# with CoreAnimation's merged shader library. FD_FBFETCH_FLUSH=1 (in caenv) brings back the GL path's old per-draw
# flush if the GMEM window ever shows tile garbage again.
METAL_ARGS="$DEFAULT_ARGS metal=1 metal_all=1 ca_metallib=/redwood/share/QuartzCore-default.metallib"
# Metal as upstream's tools/metal-run.sh runs it (docs/reference/metal-measurements.md): the wallpaper one still picture,
# six cores scaling a frame onto the panel at its 120 Hz (the driver's default is 60), SpringBoard's animations asking
# for 80..120. fb_filter=1 left out: measured upstream as no help. metal_defer=1 left out of the default sets: before the
# plug-in's fix it let the panel show frames the GPU had not drawn yet (black strips, a missing first Apple logo); it
# is only in METAL_DEFER, to compare. The boot line holds 607 characters: these replace, they are not added to.
METAL_PERF="garnet_touch=1 garnet_buttons=1 garnet_cpufreq=1 bootcpu=7 cpus=8 gpu=1 gl=1 adreno_speed=6 ddr=2 fb_queue=1 ui_lite=1 caenv=CA_DISABLE_DIRTY_REGIONS=1 gpu_recover=1 metal=1 metal_all=1 ca_metallib=/redwood/share/QuartzCore-default.metallib wallpaper_freeze=1 fb_threads=6 fb_hz=120 anim_max=1"
# what gets logged is the same with or without -v: -v only decides whether the panel shows the log or the Apple logo.
# Every Metal option takes these: frame lines, CPU load, each GPU submission's time, touch latency, the plug-in's
# counters every 5 s (cpuload=500 and touch_lat=1 were in DEFAULT_ARGS already, so options 2 and 3 log alike too).
METAL_LOG="fb_measure=1 touch_lat=1 cpuload=500 gpu_log=1 metal_fps=1"
METAL_PERF="$METAL_PERF $METAL_LOG"
# on trial in the verbose one only: the panel's DSI interface (INTF_1 = MDSS 0xae00000 + 0x36000, read from garnet's
# device tree) so frames are written behind the panel's scan (fb_beam, on by default once fb_intf is known) and its real
# rate is measured once (fb_measure, a minute in); and the GPU at 940 MHz (adreno_speed=8) instead of 816.
METAL_VERBOSE="-v ${METAL_PERF/adreno_speed=6/adreno_speed=8} fb_intf=0x0ae36000"
# the fast set with the window server's command buffers recorded on hakios-metal's own thread (needs the fixed plug-in)
METAL_DEFER="$METAL_PERF metal_defer=1"
# option 7 with the blur back: ui_lite=1 (Reduce Transparency) left out, nothing else changed. /var is fresh every
# boot (var_store is off), so nothing from an earlier ui_lite=1 boot keeps it on.
METAL_BLUR="${METAL_PERF/ui_lite=1 /}"
# option 7 with GMEM tiles (metal_gmem=1): passes of many draws drawn in the GPU's 512 KB on-chip memory, written out
# once, instead of every draw blending straight in DDR. Back on trial now that the kernel leaves GMEM's texture window
# at address 0 as the phone's own KGSL does (it was at 16 MB: every tile's framebuffer fetch faulted, the 14 Nov hangs).
METAL_GMEM="$METAL_PERF metal_gmem=1"
# the same at the GPU's top clock, 940 MHz (adreno_speed=8, which this phone's speed bin allows) instead of 816
METAL_GMEM_FAST="${METAL_GMEM/adreno_speed=6/adreno_speed=8}"
RAMDISK="userland/system.apfs"

check_prerequisites() {
    if ! command -v python3 >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1; then
        printf '%berror: Python 3 is required by xl and image tools but is not installed.%b\n' "${RED}" "${RESET}"
        printf 'Please install Python 3 and rerun this script:\n'
        if [ -d "/data/data/com.termux" ]; then
            printf '  pkg install python\n'
        else
            printf '  sudo apt install python3  (or your distribution package manager)\n'
        fi
        exit 1
    fi
}

show_menu() {
    command -v clear >/dev/null && [ -n "${TERM:-}" ] && clear
    printf '%b\n' "${CYAN}${SEP}${RESET}"
    printf '%b        HakiOS Boot Manager - POCO X6 5G (garnet)%b\n' "${BOLD}" "${RESET}"
    printf '%b\n' "${CYAN}${SEP}${RESET}"
    printf '%bDirectory : %b%s\n' "${CYAN}" "${RESET}" "$PWD"

    local kernel=""
    for k in "${XL_KERNEL:-}" "mach.development.bcm2837" "hakios-kernel" "prebuilt/mach.development.bcm2837" "prebuilt/hakios-kernel"; do
        if [ -n "$k" ] && [ -f "$k" ]; then
            kernel="$k"
            break
        fi
    done
    [ -z "$kernel" ] && kernel="${XL_KERNEL:-prebuilt/mach.development.bcm2837}"
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
    printf '%bEvery boot follows the log: press S to save it and detach.%b\n' "${CYAN}" "${RESET}"
    printf '  %b1)%b Push System Ramdisk (system.apfs)\n' "${GREEN}" "${RESET}"
    printf '  %b2)%b Boot HakiOS (Release)\n' "${GREEN}" "${RESET}"
    printf '  %b3)%b Boot HakiOS (Verbose Log)\n' "${GREEN}" "${RESET}"
    printf '  %b4)%b Boot HakiOS (Custom Boot Arguments)\n' "${GREEN}" "${RESET}"
    printf '  %b5)%b Return to XNU Loader (Stop current iOS session)\n' "${GREEN}" "${RESET}"
    printf '  %b6)%b Boot HakiOS with Metal (Verbose Log)\n' "${GREEN}" "${RESET}"
    printf '  %b7)%b Boot HakiOS with Metal (no verbose, fast)\n' "${GREEN}" "${RESET}"
    printf '  %b8)%b Boot HakiOS with Metal (no verbose, fast, 750x1624 render: fbscale=2)\n' "${GREEN}" "${RESET}"
    printf '  %b9)%b Boot HakiOS with Metal (old Metal args, Verbose Log)\n' "${GREEN}" "${RESET}"
    printf '  %bb)%b Boot HakiOS with Metal (as 7, with blur: no ui_lite)\n' "${GREEN}" "${RESET}"
    printf '  %bd)%b Boot HakiOS with Metal (fast, metal_defer=1: to compare against 7)\n' "${GREEN}" "${RESET}"
    printf '  %bg)%b Boot HakiOS with Metal (as 7, GMEM tiles: metal_gmem=1)\n' "${GREEN}" "${RESET}"
    printf '  %bh)%b Boot HakiOS with Metal (as g, GPU at 940 MHz: adreno_speed=8)\n' "${GREEN}" "${RESET}"
    printf '%bEvery argument: bootargs.md%b\n' "${CYAN}" "${RESET}"
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
    local stamp logfile run_pid key

    need_xl || return 1
    check_loader || return 1

    local kernel=""
    for k in "${XL_KERNEL:-}" "mach.development.bcm2837" "hakios-kernel" "prebuilt/mach.development.bcm2837" "prebuilt/hakios-kernel"; do
        if [ -n "$k" ] && [ -f "$k" ]; then
            kernel="$k"
            break
        fi
    done
    if [ -n "$kernel" ]; then
        export XL_KERNEL="$kernel"
    fi

    local phone_rec="${XDG_RUNTIME_DIR:-/tmp}/darwin-hakios-phone.ramdisk"
    if [ ! -f "$phone_rec" ] || [ ! -s "$phone_rec" ]; then
        if [ ! -f "$RAMDISK" ]; then
            printf '%b[WARN] No resident system ramdisk uploaded and userland/system.apfs not found!%b\n' "${YELLOW}" "${RESET}"
            printf '%b       Kernel may panic (launchd failed, errno 2) if root filesystem is missing.%b\n' "${YELLOW}" "${RESET}"
        fi
    fi

    printf '%bBooting HakiOS with args: %s%b\n' "${CYAN}" "$args" "${RESET}"
    : "${XL_SECS:=900}"
    export XL_SECS

    {
        mkdir -p logs
        stamp="$(date +%Y%m%d-%H%M%S)"
        logfile="logs/garnet-boot-$stamp.txt"

        printf '%bLive log active. Press %bS%b to save log and detach.%b\n' "${YELLOW}" "${BOLD}" "${YELLOW}" "${RESET}"
        printf '%bNote: Detaching log keeps iOS running. Use Option 5 to return to loader.%b\n' "${CYAN}" "${RESET}"

        # xl's own log of this run is logs/HHMMSS-run.log(.live); this marker tells it from older runs'
        local marker="logs/.boot-$stamp" latest_full="logs/xl-$stamp.out"
        : > "$marker"
        command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock 2>/dev/null && local woke=1
        XL_FOLLOW=${XL_FOLLOW:-5} XL_CMDLINE="$args" ./xl run > "$latest_full" 2>&1 &
        run_pid=$!

        this_run_log() { # the newest log of this run: the final one if xl wrote it, else the newest live snapshot
            find logs -maxdepth 1 \( -name '[0-9]*-run.log' -o -name '[0-9]*-run.log.live' \) -newer "$marker" -size +0 \
                -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n 1 | cut -d' ' -f2-
        }

        trap 'kill "$run_pid" 2>/dev/null' INT TERM
        # Flush lingering input
        while read -t 0.05 -n 1000 _; do :; done 2>/dev/null

        local shown=0 n
        while kill -0 "$run_pid" 2>/dev/null; do
            local latest_live
            latest_live=$(this_run_log)
            [ -n "$latest_live" ] && cp -f "$latest_live" "$logfile" 2>/dev/null
            # xl's fetch lines (sizes, failures) as they come
            n=$(wc -l < "$latest_full" 2>/dev/null || echo 0)
            if [ "$n" -gt "$shown" ]; then
                sed -n "$((shown + 1)),${n}p" "$latest_full" | grep -E 'FAILED|xl:' | sed 's/^/  /'
                shown=$n
            fi
            if [ -t 0 ]; then
                key=""
                if read -t 1 -n 1 -s key 2>/dev/null; then
                    if [ "$key" = "s" ] || [ "$key" = "S" ]; then
                        printf '\n%bFetching the whole log once more, then detaching (iOS keeps running)...%b\n' "${GREEN}" "${RESET}"
                        kill -USR1 "$run_pid" 2>/dev/null
                        # xl finishes its fetch and leaves; at most 3 minutes, then it is killed
                        local w=0
                        while kill -0 "$run_pid" 2>/dev/null && [ $w -lt 180 ]; do sleep 1; w=$((w + 1)); done
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
        [ -n "${woke:-}" ] && termux-wake-unlock 2>/dev/null

        # Finalize: this run's own log, never logs/last.log (that can be an older run's)
        local final_cand
        final_cand=$(this_run_log)
        [ -n "$final_cand" ] && cp -f "$final_cand" "$logfile" 2>/dev/null
        grep -E 'FAILED|stopped by|\[logs/' "$latest_full" 2>/dev/null | tail -n 3
        rm -f "$marker"

        if [ -f "$logfile" ] && [ -s "$logfile" ]; then
            printf '%bLog saved: %s (%s)%b\n' "${GREEN}" "$logfile" "$(du -h "$logfile" 2>/dev/null | cut -f1)" "${RESET}"
            if [ -d "/storage/emulated/0/Download" ]; then
                cp -f "$logfile" "/storage/emulated/0/Download/$(basename "$logfile")" 2>/dev/null || true
                printf '%bExported copy: %s%b\n' "${CYAN}" "/storage/emulated/0/Download/$(basename "$logfile")" "${RESET}"
            fi
        fi
    }
}

check_prerequisites

while true; do
    show_menu
    read -r -p "$(printf '%bSelect option [0-9, b, d]: %b' "${YELLOW}" "${RESET}")" choice || exit 0
    case "$choice" in
        1) push_ramdisk ;;
        2) boot_system "$DEFAULT_ARGS" ;;
        3) boot_system "-v $DEFAULT_ARGS" ;;
        4)
            read -r -e -i "-v $DEFAULT_ARGS " -p "Edit boot args: " custom
            [ -z "$custom" ] && custom="-v $DEFAULT_ARGS"
            boot_system "$custom"
            ;;
        5) return_to_loader ;;
        6) boot_system "$METAL_VERBOSE" ;;
        7) boot_system "$METAL_PERF" ;;
        8) boot_system "$METAL_PERF fbscale=2" ;;
        9) boot_system "-v $METAL_ARGS" ;;
        b|B) boot_system "$METAL_BLUR" ;;
        d|D) boot_system "$METAL_DEFER" ;;
        g|G) boot_system "$METAL_GMEM" ;;
        h|H) boot_system "$METAL_GMEM_FAST" ;;
        0) echo "Exiting."; exit 0 ;;
        *) printf '%bInvalid selection.%b\n' "${RED}" "${RESET}" ;;
    esac
    sleep 1
done
