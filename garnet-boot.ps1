# garnet-boot.ps1 - Interactive HakiOS boot manager for POCO X6 5G (Windows PowerShell)

Set-Location $PSScriptRoot

$SEP = '============================================================'
$DIV = '------------------------------------------------------------'
$DEFAULT_ARGS = 'garnet_touch=1 garnet_buttons=1 garnet_cpufreq=1 bootcpu=7 cpus=8 gpu=1 gl=1 adreno_speed=6 fb_filter=1 cpuload=500 ddr=2 fb_queue=1 touch_lat=1 ui_lite=1 caenv=CA_DISABLE_DIRTY_REGIONS=1 gpu_recover=1'
$METAL_ARGS = "$DEFAULT_ARGS metal=1 metal_all=1 ca_metallib=/redwood/share/QuartzCore-default.metallib"
# Metal as upstream's tools/metal-run.sh runs it (see garnet-boot.sh): fb_filter=1 out, the proven arguments in.
# metal_defer=1 only in $METAL_DEFER (option d): before the plug-in's fix it showed frames the GPU had not drawn (black strips)
$METAL_PERF = 'garnet_touch=1 garnet_buttons=1 garnet_cpufreq=1 bootcpu=7 cpus=8 gpu=1 gl=1 adreno_speed=6 ddr=2 fb_queue=1 ui_lite=1 caenv=CA_DISABLE_DIRTY_REGIONS=1 gpu_recover=1 metal=1 metal_all=1 ca_metallib=/redwood/share/QuartzCore-default.metallib wallpaper_freeze=1 fb_threads=6 fb_hz=120 anim_max=1'
# verbose: on trial the panel's DSI interface (fb_intf: frames written behind the scan, its rate measured) and the GPU at 940 MHz
# the same logging with or without -v (garnet-boot.sh: METAL_LOG): -v only picks the log or the Apple logo on the panel
$METAL_LOG = 'fb_measure=1 touch_lat=1 cpuload=500 gpu_log=1 metal_fps=1'
$METAL_PERF = "$METAL_PERF $METAL_LOG"
$METAL_VERBOSE = "-v $($METAL_PERF -replace 'adreno_speed=6','adreno_speed=8') fb_intf=0x0ae36000"
$METAL_DEFER = "$METAL_PERF metal_defer=1"
# option b: 7 with the blur back (ui_lite=1 left out, nothing else)
$METAL_BLUR = $METAL_PERF -replace 'ui_lite=1 ',''
$RAMDISK = 'userland/system.apfs'

function Show-Menu {
    try { Clear-Host } catch {}
    Write-Host $SEP -ForegroundColor Cyan
    Write-Host "        HakiOS Boot Manager - POCO X6 5G (garnet)" -ForegroundColor White
    Write-Host $SEP -ForegroundColor Cyan
    Write-Host "Directory : $((Get-Location).Path)" -ForegroundColor Cyan
    
    $candidates = @(
        $env:XL_KERNEL,
        'mach.development.bcm2837',
        'hakios-kernel',
        'prebuilt/mach.development.bcm2837',
        'prebuilt/hakios-kernel'
    )
    $kernel = $null
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) {
            $kernel = $c
            break
        }
    }
    if (-not $kernel) {
        $kernel = 'prebuilt/mach.development.bcm2837'
    }
    if (Test-Path $kernel) {
        Write-Host "Kernel    : $kernel (Found)" -ForegroundColor Green
    } else {
        Write-Host "Kernel    : $kernel (Missing)" -ForegroundColor Red
    }

    if (Test-Path $RAMDISK) {
        Write-Host "System RD : $RAMDISK (Found)" -ForegroundColor Green
    } else {
        Write-Host "System RD : $RAMDISK (Not in userland/ - see put system.apfs here.txt)" -ForegroundColor Yellow
    }

    Write-Host $DIV -ForegroundColor Cyan
    Write-Host "Every boot follows the log: press S to save it and detach." -ForegroundColor Cyan
    Write-Host "  1) Push System Ramdisk (system.apfs)" -ForegroundColor Green
    Write-Host "  2) Boot HakiOS (Release)" -ForegroundColor Green
    Write-Host "  3) Boot HakiOS (Verbose Log)" -ForegroundColor Green
    Write-Host "  4) Boot HakiOS (Custom Boot Arguments)" -ForegroundColor Green
    Write-Host "  5) Return to XNU Loader (Stop current iOS session)" -ForegroundColor Green
    Write-Host "  6) Boot HakiOS with Metal (Verbose Log)" -ForegroundColor Green
    Write-Host "  7) Boot HakiOS with Metal (no verbose, fast)" -ForegroundColor Green
    Write-Host "  8) Boot HakiOS with Metal (no verbose, fast, 750x1624 render: fbscale=2)" -ForegroundColor Green
    Write-Host "  9) Boot HakiOS with Metal (old Metal args, Verbose Log)" -ForegroundColor Green
    Write-Host "  b) Boot HakiOS with Metal (as 7, with blur: no ui_lite)" -ForegroundColor Green
    Write-Host "  d) Boot HakiOS with Metal (fast, metal_defer=1: to compare against 7)" -ForegroundColor Green
    Write-Host "Every argument: bootargs.md" -ForegroundColor Cyan
    Write-Host "  0) Exit" -ForegroundColor Green
    Write-Host $SEP -ForegroundColor Cyan
}

function Check-Loader {
    if (-not (Test-Path 'xl.ps1')) {
        Write-Host "error: xl.ps1 not found in current directory." -ForegroundColor Red
        return $false
    }
    $state = & .\xl.ps1 state 2>$null
    if ($state -eq 'loader') {
        return $true
    }
    Write-Host "Device not in loader state (state: $state)." -ForegroundColor Yellow
    Write-Host "If device is in fastboot mode, boot the loader first:"
    Write-Host "  fastboot boot garnet-boot.img"
    return $false
}

function Push-Ramdisk {
    if (-not (Test-Path $RAMDISK)) {
        Write-Host "error: $RAMDISK not found! Place it in userland/." -ForegroundColor Red
        return
    }
    if (-not (Check-Loader)) { return }
    Write-Host "Pushing system ramdisk ($RAMDISK) to resident RAM..." -ForegroundColor Cyan
    & .\xl.ps1 ramdisk $RAMDISK
}

function Return-ToLoader {
    Write-Host "Requesting XNU kernel to stop and return to loader..." -ForegroundColor Cyan
    & .\xl.ps1 stop
    Write-Host "Kernel returned to resident loader. Resident ramdisk preserved." -ForegroundColor Green
}

function Boot-System {
    param([string]$BootArgs)

    if (-not (Check-Loader)) { return }

    $candidates = @(
        $env:XL_KERNEL,
        'mach.development.bcm2837',
        'hakios-kernel',
        'prebuilt/mach.development.bcm2837',
        'prebuilt/hakios-kernel'
    )
    $kernel = $null
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) {
            $kernel = $c
            break
        }
    }
    if ($kernel) {
        $env:XL_KERNEL = $kernel
    }

    Write-Host "Booting HakiOS with args: $BootArgs" -ForegroundColor Cyan
    $env:XL_SECS = 900

    {
        New-Item -ItemType Directory -Force -Path 'logs' | Out-Null
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $logfile = "logs/garnet-boot-$stamp.txt"
        Write-Host "Live log active. Press 'S' to save log and detach." -ForegroundColor Yellow
        Write-Host "Note: Detaching log keeps iOS running. Use Option 5 to return to loader." -ForegroundColor Cyan

        $env:XL_FOLLOW = 5
        $env:XL_CMDLINE = $BootArgs
        $started = Get-Date
        & .\xl.ps1 run
        # this run's own log (never an older run's logs/last.log): the newest written since it started
        $mine = Get-ChildItem 'logs' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+-run\.log(\.live)?$' -and $_.LastWriteTime -ge $started -and $_.Length -gt 0 } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($mine) {
            Copy-Item $mine.FullName $logfile -Force -ErrorAction SilentlyContinue
            Write-Host "Log saved: $logfile ($([int]($mine.Length / 1KB)) KiB)" -ForegroundColor Green
        } else {
            Write-Host "No log of this run was fetched." -ForegroundColor Yellow
        }
    }
}

while ($true) {
    Show-Menu
    $choice = Read-Host "Select option [0-9, b, d]"
    switch ($choice) {
        '1' { Push-Ramdisk }
        '2' { Boot-System $DEFAULT_ARGS }
        '3' { Boot-System "-v $DEFAULT_ARGS" }
        '4' {
            $custom = Read-Host "Edit boot args (default: -v $DEFAULT_ARGS)"
            if ([string]::IsNullOrWhiteSpace($custom)) { $custom = "-v $DEFAULT_ARGS" }
            Boot-System $custom
        }
        '5' { Return-ToLoader }
        '6' { Boot-System $METAL_VERBOSE }
        '7' { Boot-System $METAL_PERF }
        '8' { Boot-System "$METAL_PERF fbscale=2" }
        '9' { Boot-System "-v $METAL_ARGS" }
        'b' { Boot-System $METAL_BLUR }
        'd' { Boot-System $METAL_DEFER }
        '0' { Write-Host "Exiting."; exit 0 }
        default { Write-Host "Invalid option." -ForegroundColor Red }
    }
    Start-Sleep -Seconds 1
}
