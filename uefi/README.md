# UEFI for POCO X6 5G (garnet)

Port of Project Mu / Mu-Silicium UEFI for the Qualcomm Snapdragon 7s Gen 2 (SM7435-AB, Xiaomi POCO X6 5G).

- `apply.sh`: Clones Mu-Silicium and applies Garnet platform definitions.
- `export.sh`: Exports `garnetPkg`, `garnet.toml`, and `garnet.dtb` back into this repository.
- `files/Platforms/Xiaomi/garnetPkg`: Device description, memory map, ACPI/SMBIOS, and build rules.
- Prebuilt UEFI binaries live in `prebuilt/`: `SILICIUM_UEFI.fd` and `BootShim.bin`.
