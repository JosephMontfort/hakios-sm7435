# HakiOS on garnet: boot arguments

Every argument the boot menu (`garnet-boot.sh` / `garnet-boot.ps1`) passes, what it does, and what each value means.
`K` = read by the kernel, `U` = read by userland (SpringBoard / backboardd injections, the Metal plug-in), `L` = the loader.
"Default" is what happens when the argument is absent. The whole boot line holds 607 characters, and the loader uses
about 145 of them, so the sets below replace arguments rather than add to them.

## Options at a glance

| Option | Arguments | Purpose |
|---|---|---|
| 1 | (none: pushes `userland/system.apfs`) | Load the iOS system ramdisk into the loader |
| 2 | `DEFAULT_ARGS` | OpenGL ES (Mesa) window server, Apple logo on the panel |
| 3 | `-v DEFAULT_ARGS` | As 2, with the log on the panel |
| 4 | Your own (prefilled `-v DEFAULT_ARGS`) | Custom |
| 5 | (none) | Stop the running iOS session and return to the loader |
| 6 | `METAL_VERBOSE` = `-v` + 7's set with `adreno_speed=8 fb_intf=0x0ae36000` | Metal, log on the panel, GPU at 940 MHz, scan-synced frames |
| 7 | `METAL_PERF` (+ `METAL_LOG`) | Metal, fast set, Apple logo on the panel (the daily one) |
| 8 | 7 + `fbscale=2` | Metal, rendered at 750x1624 and scaled up |
| 9 | `-v METAL_ARGS` = `-v DEFAULT_ARGS metal=1 metal_all=1 ca_metallib=...` | Old Metal set, verbose |
| b | 7 without `ui_lite=1` | Metal like 7, but with blur (Reduce Transparency off) |
| d | 7 + `metal_defer=1` | Metal like 7, with deferred command recording (to compare) |
| 0 | (none) | Exit the script |

Every option that boots follows the log; press S to save it and detach. Without `-v` the log is still recorded,
just not shown on the panel.

## Kernel and hardware

- `-v`: verbose boot. The panel shows the kernel and system log instead of the Apple logo. Logging is the same either way. Options 3, 6, 9.
- `garnet_touch=1` (K): start garnet's touch-screen driver (FocalTech) and say "this is garnet" to the button, speaker and cpufreq drivers. `0` or absent: no touch. All options.
- `garnet_buttons=1` (K): power and volume buttons driver. `0` or absent: buttons are not read. All options.
- `garnet_cpufreq=1` (K): CPU frequency scaling through garnet's EPSS (4 silver A55 + 4 gold A78 cores). `0` or absent: cores stay at the clocks the loader left. All options.
- `bootcpu=N` (KL): the core the kernel starts on (0–7). `7` = a gold core, about 2.5 times faster than a silver one, while the loader keeps watching from another core. All options.
- `cpus=N` (L): how many cores the kernel brings up (1–8). `8` = all of them. All options.

## Memory bus

- `ddr=N` (K): the DDR bandwidth vote.
  - `2` (default): raise memory bandwidth while cpufreq runs.
  - `1`: only probe and print the DDR tables (a diagnostic).
  - `0`: leave it as the loader left it.

  All options set `ddr=2`.

## GPU (Adreno 710)

- `gpu=1` (K): start the GPU while the system boots and keep it for the window server (the HakiosGPU service). `0` or absent: everything is drawn in software. All options.
- `adreno_speed=N` (K): the GPU clock level asked of the GMU.
  - `1` = 345 MHz (default), `2` = 500, `3` = 600, `4` = 650, `5` = 734
  - `6` = 816 MHz, Turbo: options 2–5, 7–9, b, d
  - `7` = 875 MHz
  - `8` = 940 MHz, SuperTurbo, the maximum: option 6
- `gpu_recover=1` (K): a GPU submission that never finishes gets the core reset and given work again, instead of the window server hanging. `0` or absent: no recovery. All options.
- `gpu_log=N` (K): GPU logging.
  - `1`: one `tl: Q`/`q` line for each submission and its GPU time, plus clock and bandwidth lines. Used by tools/frames.py.
  - `2`: also every register access (very noisy).
  - `0` (default): quiet.

  Options 6, 7, 8, b, d.

## Display / framebuffer (the kernel scales the 1125x2436 iPhone frame onto the 1220x2712 panel)

- `fb_queue=N` (K): how many finished frames may wait for the panel, `1` or `2` (default 2). `1` = lowest latency. All options.
- `fb_threads=N` (K): how many cores scale each frame onto the panel together, `1`–`8` (default 3). `6` in the Metal fast sets.
- `fb_hz=N` (K): how many times a second frames are put on the panel (default 60). `120` = the panel's rate. Options 6–8, b, d.
- `fb_filter=N` (K): how a frame is scaled.
  - `0`: nearest neighbour.
  - `1`: always bilinear (sharper, about 2x the cost).
  - `2` (default): nearest neighbour while frames are moving, then bilinear once the screen settles.

  `fb_filter=1` is in options 2–4 and 9 only; the Metal fast sets leave it out (no measured benefit).
- `fbscale=N` (K): the scale iOS renders at.
  - `0`/`3` (default): 1125x2436, three pixels a point.
  - `2`: 750x1624, 2.25 times fewer pixels to draw and scale, softer picture.

  Option 8.
- `fb_intf=0xADDR` (K): physical address of the panel's DSI interface. `0x0ae36000` = garnet's INTF_1. With it, frames are written behind the panel's scan line (`fb_beam`, which is on whenever this is known), so there is no tearing, and `fb_measure` can read the real refresh rate. Absent: frames are written on a timer. Option 6.
- `fb_measure=1` (K): about a minute after boot, log how often the panel really refreshes (needs `fb_intf`). `0`/absent: off. Options 6–8, b, d.

## Userland / CoreAnimation

- `gl=N` (U): the OpenGL ES (Mesa) renderer for the window server.
  - `1`: load it (on the phone, only if `gpu=1` started the GPU).
  - `0`: never load it; software rendering.

  All options set `gl=1`; Metal options draw through Metal on top of it.
- `ui_lite=1` (U): turn on Reduce Transparency (`EnhancedBackgroundContrastEnabled`). The dock, folders, Control Centre and widget platters use plain colours instead of blurring what is behind them every frame, which saves a lot of GPU time.
  - Absent or `0`: blur stays on. `/var` is fresh every boot, so an earlier `ui_lite=1` boot does not carry over.
  - The vibrancy tint (`BSUIVibrancyEffectViewDisabled`) is set by the SpringBoard injection regardless of this argument.

  Every option except b.
- `caenv=NAME=VALUE` (U): put an environment variable into the window server's (CoreAnimation's) environment. It can be repeated.
  - `CA_DISABLE_DIRTY_REGIONS=1`: CoreAnimation redraws the whole screen every frame instead of only what changed. It is kept because, without it, icons disappeared after idling. It costs GPU time.

  All options.
- `wallpaper_freeze=N` (U): the wallpaper drawn once and kept as a still picture.
  - `1`: still picture. The wallpaper won't change until the next boot.
  - `2`: wallpaper hidden (to measure what it costs).
  - Absent: the live poster is composed every frame.

  Metal fast sets (6–8, b, d).
- `anim_max=1` (U): every SpringBoard animation asks for 80–120 fps. Without it, animations that ask for nothing ran at 24 fps through Metal. Metal fast sets.
- `touch_lat=1` (KU): latency lines for each touch sample, injected touch, swap and frame shown (`tl: p/i/s/v ...`). Read by tools/latency.py and tools/frames.py. `0`/absent: off. All options.
- `cpuload=MS` (K): every MS milliseconds, log each core's busy percentage (`tl: u ...`). `500` = twice a second; `0`/absent: off. All options.

## Metal plug-in (hakios-metal)

- `metal=1` (KU): the window server draws through hakios-metal's Metal plug-in (`/redwood/lib/RedwoodMetal.bundle`) instead of OpenGL ES. Absent: OpenGL ES. Options 6–9, b, d.
- `metal_all=1` (U): every process that asks gets the Metal device. Without it, only the window server (backboardd) does, and others such as SpringBoard's Siri orb fall back to their non-Metal path. Options 6–9, b, d.
- `ca_metallib=PATH` (U): the CoreAnimation shader library handed to the window server when it asks for `default.metallib`. `/redwood/share/QuartzCore-default.metallib` is the one in root.apfs. Options 6–9, b, d.
- `metal_fps=N` (U): plug-in counters every 5 s (frames, passes, GPU busy, GMEM or sysmem per pass, slowest passes).
  - `1`: the counters.
  - `draws`: also time every draw of a sysmem pass by shader (heavy).
  - Absent: off.

  Options 6–8, b, d.
- `metal_defer=1` (U): the window server's command buffers are recorded on a hakios-metal thread, so CoreAnimation's render thread does not wait about 40 µs for each draw to be encoded. Absent: recorded inline. Option d.
- `metal_gmem=1` (U): tiled rendering in the GPU's on-chip GMEM. Not used on garnet: the plug-in draws every pass in
  sysmem on the A7xx whatever this says. Lifting that (14 November build) hung the GPU 14–17 times a boot.

## Added by the loader (not in the menu's sets)

- `debug=0x8`: XNU debug flags (serial/kprintf logging).
- `rd=md0`: root on the ramdisk (`system.apfs`).
- `garnet_12gb=0|1`, `garnet_ram=8|12`: the phone's RAM size, detected by the loader.
- `garnet_root_end=0x...`: where the root image ends in memory.
- `loader_return_after=S`: hand control back to the loader after S seconds (900 = 15 min), so the log can be collected.
- `epoch=SECONDS`: the host's time, used to set the clock.
- `sb_delay=S`: seconds SpringBoard waits before it starts.
