#!/bin/bash
# Save Garnet platform from Mu-Silicium into files/
set -e
cd "$(dirname "$(readlink -f "$0")")"
MU=${MU:-../../../Mu-Silicium}
rm -rf files
mkdir -p files/Resources/Configs files/Resources/DTBs files/Platforms/Xiaomi files/Binaries
cp -r $MU/Platforms/Xiaomi/garnetPkg files/Platforms/Xiaomi/
cp $MU/Resources/Configs/garnet.toml files/Resources/Configs/
cp $MU/Resources/DTBs/garnet.dtb files/Resources/DTBs/
find files -name __pycache__ -prune -exec rm -rf {} +
echo "devices/garnet/uefi/export.sh: $(find files -type f | wc -l) files"
