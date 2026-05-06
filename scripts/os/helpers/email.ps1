<#
.SYNOPSIS
    os email <name> -- request that <name> become the default mail client
                       (handler for mailto: links).

.DESCRIPTION
    Same constraint as the browser helper: the mailto UserChoice key is
    hash-protected on Windows 10/11. We:

      1. Validate the requested name against the shared catalog.
      2. Detect whether the mail client is installed (CODE RED: every
         missing probe path is logged verbatim).
      3. Open the modern Settings deeplink scoped to the app so the user
         can click "Set default" once.
      4. Verify by reading HKCU\...\mailto\UserChoice\ProgId.

    Also writes a best-effort legacy hint to HKCU\Software\Clients\Mail
    for older apps that still honour it (Outlook 2016, Office tooling).
    The modern UserChoice still wins; the legacy write is logged as a
    "best-effort" line.

    `--list` and `--dry-run` mirror the browser helper.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Name,

    [switch]$List,
    [switch]$DryRun,
    [switch]$Yes
)

$ErrorActionPreference = "Continue"
Set-StrictMode -Version Latest

$helpersDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptDir  = Split-Path -Parent $helpersDir
$sharedDir  = Join-Path (Split-Path -Parent $scriptDir) "shared"

. (Join-Path $sharedDir "logging.ps1")
. (Join-Path $sharedDir "json-utils.ps1")
. (Join-Path $helpersDir "_common.ps1")
. (Join-Path $helpersDir "_default-apps-catalog.ps1")

Initialize-Logging -ScriptName "OS Default Email"

$script:DefaultAppProbeMisses = @()

if ($List) {
    Get-DefaultAppCatalogList -Catalog "email"
    Save-LogFile -Status "ok"
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Name)) {
    Write-Log "Missing mail-client name. Run '.\run.ps1 os email --list' to see available options." -Level "fail"
    Save-LogFile -Status "fail"
    exit 2
}

$entry = Resolve-DefaultAppEntry -Name $Name -Catalog "email"
if ($null -eq $entry) {
    Write-Log "Unknown mail-client name: '$Name'. Run '.\run.ps1 os email --list' for the catalog." -Level "fail"
    Save-LogFile -Status "fail"
    exit 2
}

Write-Log "Target mail client: $($entry.DisplayName) (key='$($entry.Key)', ProgId='$($entry.ProgId)')" -Level "info"

# 1. Detection
$exePath = Find-InstalledExecutable -Entry $entry
if (-not $exePath) {
    Write-Log "Mail client '$($entry.DisplayName)' is NOT installed. Probed paths:" -Level "fail"
    foreach ($miss in $script:DefaultAppProbeMisses) {
        Write-Log ("  - {0}  ({1})" -f $miss.Path, $miss.Reason) -Level "fail"
    }
    if ($entry.ChocoPackage) {
        Write-Log "Hint: choco install $($entry.ChocoPackage) -y" -Level "info"
    }
    Save-LogFile -Status "fail"
    exit 3
}
Write-Log "Detected installed at: $exePath" -Level "success"

if ($DryRun) {
    Write-Log "DRY-RUN: would open ms-settings:defaultapps scoped to '$($entry.AppName)'." -Level "info"
    Write-Log "DRY-RUN: would then verify HKCU\...\mailto\UserChoice\ProgId equals '$($entry.ProgId)'." -Level "info"
    Save-LogFile -Status "ok"
    exit 0
}

# 2. Read current default for mailto
$userChoiceKey = "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\mailto\UserChoice"
$currentProgId = $null
try {
    $currentProgId = (Get-ItemProperty -Path $userChoiceKey -Name "ProgId" -ErrorAction SilentlyContinue).ProgId
} catch {
    Write-Log "Could not read current default at ${userChoiceKey}: $($_.Exception.Message)" -Level "warn"
}
if ($currentProgId) {
    Write-Log "Current default for mailto: = $currentProgId" -Level "info"
    if ($currentProgId -eq $entry.ProgId) {
        Write-Log "$($entry.DisplayName) is ALREADY the default mail client. Nothing to do." -Level "success"
        Save-LogFile -Status "ok"
        exit 0
    }
}

# 3. Best-effort legacy HKCU\Software\Clients\Mail hint (Outlook honours this)
$legacyKey = "HKCU:\Software\Clients\Mail"
try {
    if (-not (Test-Path $legacyKey)) { New-Item -Path $legacyKey -Force | Out-Null }
    Set-ItemProperty -Path $legacyKey -Name "(default)" -Value $entry.AppName -ErrorAction Stop
    Write-Log "Legacy HKCU\Software\Clients\Mail set to '$($entry.AppName)' (best-effort -- modern UserChoice still wins)." -Level "info"
} catch {
    Write-Log "Could not write legacy mail hint at ${legacyKey}: $($_.Exception.Message)" -Level "warn"
}

# 4. Launch Settings deeplink scoped to the app
$deeplink = "ms-settings:defaultapps?registeredAppUser=" + [uri]::EscapeDataString($entry.AppName)
Write-Log "Opening Settings deeplink: $deeplink" -Level "info"
Write-Log "Click 'Set default for mailto' in the dialog, then return here." -Level "info"
try {
    Start-Process $deeplink | Out-Null
} catch {
    Write-Log "Failed to open Settings deeplink: $($_.Exception.Message)" -Level "fail"
    Write-Log "Fallback: open Settings -> Apps -> Default apps -> '$($entry.DisplayName)' -> mailto -> Set default." -Level "info"
    Save-LogFile -Status "fail"
    exit 4
}

# 5. Wait + verify
if (-not $Yes) {
    Write-Host ""
    Write-Host "  Waiting up to 60s for you to click 'Set default'..." -ForegroundColor Yellow
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        $now = $null
        try { $now = (Get-ItemProperty -Path $userChoiceKey -Name "ProgId" -ErrorAction SilentlyContinue).ProgId } catch {}
        if ($now -eq $entry.ProgId) { break }
    }
}

$finalProgId = $null
try { $finalProgId = (Get-ItemProperty -Path $userChoiceKey -Name "ProgId" -ErrorAction SilentlyContinue).ProgId } catch {}

if ($finalProgId -eq $entry.ProgId) {
    Write-Log "Verified: default mailto handler is now '$($entry.ProgId)' ($($entry.DisplayName))." -Level "success"
    Save-LogFile -Status "ok"
    exit 0
} else {
    Write-Log "Default mail client was NOT changed (still '$finalProgId', wanted '$($entry.ProgId)')." -Level "warn"
    Write-Log "Windows 10/11 requires the user to click 'Set default' in the Settings dialog." -Level "info"
    Write-Log "Re-run '.\run.ps1 os email $($entry.Key)' and complete the dialog within 60s." -Level "info"
    Save-LogFile -Status "partial"
    exit 5
}
