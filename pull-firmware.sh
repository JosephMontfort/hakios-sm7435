#!/bin/bash
# Pull POCO X6 5G (garnet) vendor firmware out of Android into fw-*/ directories.
# The phone must be connected via adb with Android running.
set -e
cd "$(dirname "$0")/../.."
pull() {
	local dir=$1; shift
	mkdir -p "$dir"
	for f in "$@"; do adb pull "$f" "$dir/" >/dev/null 2>&1 || echo "pull-firmware.sh: $f: not on phone"; done
	echo "pull-firmware.sh: $dir: $(ls -1 "$dir" | wc -l | tr -d ' ') files"
}
adb get-state >/dev/null

# GPU: Adreno 710 (SM7435-AB)
pull fw-gpu /vendor/firmware/gen71100_gmu.bin /vendor/firmware/a702_gmu.bin /vendor/firmware/a702_sqe.fw /vendor/firmware/a702_zap.mdt /vendor/firmware/a702_zap.b00 /vendor/firmware/a702_zap.b01 /vendor/firmware/a702_zap.b02

# Audio: ADSP
pull fw-audio /vendor/firmware_mnt/image/adsp.mdt $(for i in $(seq -w 2 36); do echo /vendor/firmware_mnt/image/adsp.b$i; done)

# Haptic: AW8697 / Awinic
pull fw-haptic /vendor/firmware/aw8697_haptic.bin

# Modem
pull fw-modem /vendor/firmware_mnt/image/modem.mdt $(for i in $(seq -w 0 28); do echo /vendor/firmware_mnt/image/modem.b$i; done)
mkdir -p fw-modem/image && adb pull /vendor/firmware_mnt/image fw-modem/ >/dev/null 2>&1 || true

echo "pull-firmware.sh: done"
