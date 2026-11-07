# garnet-boot.ps1 - Interactive HakiOS boot manager for POCO X6 5G (Windows PowerShell)

Set-Location $PSScriptRoot

$SEP = '============================================================'
$DIV = '------------------------------------------------------------'
$DEFAULT_ARGS = 'garnet_touch=1 garnet_buttons=1 garnet_cpufreq=1 bootcpu=7 cpus=8 gpu=1 gl=1 adreno_speed=8 fb_filter=1 cpuload=500 ddr=2 fb_queue=1 touch_lat=1 ui_lite=1 caenv=CA_DISABLE_DIRTY_REGIONS=1'
$RAMDISK = 'userland/system.apfs'

function Show-Menu {
    try { Clear-Host } catch {}
    Write-Host $SEP -ForegroundColor Cyan
    Write-Host "        HakiOS Boot Manager - POCO X6 5G (garnet)" -ForegroundColor White
    Write-Host $SEP -ForegroundColor Cyan
    Write-Host "Directory : $((Get-Location).Path)" -ForegroundColor Cyan
    
    $kernel = if ($env:XL_KERNEL) { $env:XL_KERNEL } else { 'mach.development.bcm2837' }
    if (-not (Test-Path $kernel) -and (Test-Path 'prebuilt/mach.development.bcm2837')) {
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
    Write-Host "  1) Push System Ramdisk (system.apfs)" -ForegroundColor Green
    Write-Host "  2) Boot HakiOS (Release)" -ForegroundColor Green
    Write-Host "  3) Boot HakiOS (Verbose Log)" -ForegroundColor Green
    Write-Host "  4) Boot HakiOS (Custom Boot Arguments)" -ForegroundColor Green
    Write-Host "  5) Return to XNU Loader (Stop current iOS session)" -ForegroundColor Green
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
    param([string]$Args, [bool]$WithLog)

    if (-not (Check-Loader)) { return }
    Write-Host "Booting HakiOS with args: $Args" -ForegroundColor Cyan
    $env:XL_SECS = 900

    if ($WithLog) {
        New-Item -ItemType Directory -Force -Path 'logs' | Out-Null
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $logfile = "logs/garnet-boot-$stamp.txt"
        Write-Host "Live log active. Press 'S' to save log and detach." -ForegroundColor Yellow
        Write-Host "Note: Detaching log keeps iOS running. Use Option 5 to return to loader." -ForegroundColor Cyan

        $env:XL_CMDLINE = $Args
        & .\xl.ps1 run
    } else {
        $env:XL_CMDLINE = $Args
        & .\xl.ps1 run
    }
}

while ($true) {
    Show-Menu
    $choice = Read-Host "Select option [0-5]"
    switch ($choice) {
        '1' { Push-Ramdisk }
        '2' { Boot-System $DEFAULT_ARGS $false }
        '3' { Boot-System "-v $DEFAULT_ARGS" $true }
        '4' {
            $custom = Read-Host "Edit boot args (default: -v $DEFAULT_ARGS)"
            if ([string]::IsNullOrWhiteSpace($custom)) { $custom = "-v $DEFAULT_ARGS" }
            Boot-System $custom $true
        }
        '5' { Return-ToLoader }
        '0' { Write-Host "Exiting."; exit 0 }
        default { Write-Host "Invalid option." -ForegroundColor Red }
    }
    Start-Sleep -Seconds 1
}
