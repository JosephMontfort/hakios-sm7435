# hakios-sm7435: POCO X6 5G (garnet) and Snapdragon 7s Gen 2 (SM7435-AB)

HakiOS device repository for the **Xiaomi POCO X6 5G** (codename: `garnet`), powered by the Qualcomm Snapdragon 7s Gen 2 (`SM7435-AB`, "parrot" family) and Adreno 710 GPU.

`tools/hakios-device.py sync garnet` in the common HakiOS repository clones this into `devices/garnet/`.

---

## 1. Hardware Architecture

| Subsystem | Specification on POCO X6 5G (Garnet) |
|---|---|
| **SoC** | Qualcomm Snapdragon 7s Gen 2 (`SM7435-AB`, 4x Kryo Gold Cortex-A78 @ 2.40 GHz + 4x Kryo Silver Cortex-A55 @ 1.95 GHz) |
| **GPU** | Qualcomm Adreno 710 (Gen 7_3_0, chip ID `0x07010000`, 8 DCVS clock levels from 345 MHz to 940 MHz) |
| **Touchscreen** | FocalTech FT3683G on QUP1 SE3 SPI (`0x00a8c000`), Protocol Version 2 (PV2), TianMa PRAM firmware |
| **Display Panel** | 1.5K Flow AMOLED (1220 x 2712 @ 120 Hz, 68B colors, Dolby Vision) |
| **PMIC & Rails** | PM6450 / PM7250B (SPMI Arbiter v7 `0x0c400000`, `touch_vddio` 1.8V on GPIO3, RPMh RSC DRV2 `ldoe9` 3.224V) |
| **UEFI Platform** | Project Mu / Mu-Silicium (`garnetPkg`, `SILICIUM_UEFI.fd`) |
| **Memory Window** | K60 notch 5 GB usable RAM window (`0xA1000000` image base, `0xF4000000` payload base) |

---

## 2. Hardware Implementation Status

| Subsystem | Status | Technical Details |
|---|---|---|
| **Display** | **Works** | UEFI GOP framebuffer passed to `MiniIOMobileFramebuffer`. Mesa GPU rendering active. |
| **Touchscreen** | **Works** | FocalTech FT3683G SPI controller on SE3 (`0x00a8c000`), PV2 packet parsing, PRAM firmware upload, SPMI power rails. Multi-touch and system gestures functional. |
| **Buttons** | **Works** | Hardware Volume Up/Down and Power keys through PM6450 SPMI Arbiter v7 (`0x0c400000`). |
| **CPU / SMP** | **Works** | Full 8-core multicore bringup (`cpus=8`, `bootcpu=7`, `cpufreq=1`). CPACR_EL1 FP/SIMD active on secondary cores. |
| **GPU (OpenGL ES)** | **Works** | Adreno 710 brought up step-by-step; GMU uncollapse loop patched at VA `0x115f8`; Freedreno Mesa 25.0.7 OpenGL ES renders SpringBoard and apps. Occasional UI lags/jitters under profiling. |
| **Metal Engine** | **In Development** | Gen 7 command stream and PM4 parity defined in `a7xx.hpp`. Experimental / unstable. |
| **Storage (UFS)** | **Works** | UFS reading through UEFI loader; mutable `/private/var` storage with `var_store=1 ufs_write=1`. |
| **Audio** | **Partial** | Dual AW88261 speaker amplifiers initialized; full audio DSP in progress. |
| **Battery** | **Partial** | Battery level read through PMIC; in-kernel charging not implemented (phone discharges during session). |
| **Wi-Fi & Cellular** | **Missing** | WCN6750 Wi-Fi and MPSS/IPA modem currently in progress for Garnet. |

---

## 3. SoC Address Arguments (`soc.args`)

The kernel reads non-default SoC addresses from `soc.args`:

| Argument | Device-Tree Source | Garnet Value |
|---|---|---|
| `soc_rsc` | `qcom,rpmh-rsc` reg drv-2 | `0x17a20000` |
| `soc_tlmm` | `tlmm` physical GPIO base | `0x0f100000` |
| `soc_spmi` | SPMI PMIC Arbiter v7 core base | `0x0c400000` |
| `soc_cmd_db` | `reserved-memory` `cmd_db` | `0x80860000` |
| `soc_smem` | `reserved-memory` `qcom,smem` | `0x80900000` |
| `soc_imem` | `qcom,msm-imem` | `0x14600000` |

---

## 4. Booting the Device

Run the interactive boot manager from the root of the repository:
```bash
./garnet-boot.sh
```

**Workflow:**
1. Put the POCO X6 5G in fastboot mode (`adb reboot bootloader` or Hold Power + Volume Down).
2. Boot the UEFI image:
   ```bash
   fastboot boot prebuilt/garnet-boot.img
   ```
3. Once the HakiOS boot screen appears, select:
   - **Option 1:** Push Ramdisk (`userland/system.apfs`).
   - **Option 2:** Load HakiOS (Release mode).
   - **Option 3:** Load HakiOS with live debug logging.

---

## 5. Firmware Extraction

To extract vendor firmware binaries from your phone running Android:
```bash
./pull-firmware.sh
```
Pulls the Adreno 710 GMU/SQE/ZAP firmware (`fw-gpu/`), audio DSP firmware (`fw-audio/`), and haptics firmware (`fw-haptic/`). All vendor binaries remain out of Git.

---

## Community & Support

- **Updates Channel:** [t.me/garnetglobal](https://t.me/garnetglobal)
- **Support Group:** [t.me/Garnet_Axion_Support](https://t.me/Garnet_Axion_Support)

---

## Maintainer & Attribution

Maintained by **Montfort** as part of the HakiOS project.
Built upon Apple's open-source XNU kernel (`xnu-8796.121.2`), Project Mu UEFI, and Mesa Gallium Freedreno.
