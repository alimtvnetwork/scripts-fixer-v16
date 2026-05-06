<#
.SYNOPSIS
    os browser <name> -- request that <name> become the default web browser.

.DESCRIPTION
    Modern Windows (10 1803+ / 11) protects the http/https UserChoice
    registry keys with a per-user signed hash; programmatic registry writes
    are silently rejected. This helper does the next-best thing:

      1. Validate the requested name against the shared catalog.
      2. Detect whether the browser is actually installed (file probes +
         PATH lookup). CODE RED: every miss is logged with the exact path.
      3. Open the modern "Default apps" Settings deeplink scoped to that
         app (ms-settings:defaultapps?registeredAppUser=<AppName>) so the
         user only has to click "Set default" once.
      4. After a short wait, verify by reading the current http UserChoice
         ProgId and report whether it matches.

    `--list` prints the catalog and exits. `--dry-run` does steps 1-2 and
    prints what would happen without launching Settings.

.NOTES
    Cross-OS behavior: this script is the Windows arm. Linux uses
    scripts-linux/_shared/default-apps.sh + run.sh routes; macOS uses
    helpers/mac/set-default-browser.sh.
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

Initialize-Logging -ScriptName "OS Default Browser"

$script:DefaultAppProbeMisses = @()

if ($List) {
    Get-DefaultAppCatalogList -Catalog "browser"
    Save-LogFile -Status "ok"
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Name)) {
    Write-Log "Missing browser name. Run '.\run.ps1 os browser --list' to see available options." -Level "fail"
    Save-LogFile -Status "fail"
    exit 2
}

$entry = Resolve-DefaultAppEntry -Name $Name -Catalog "browser"
if ($null -eq $entry) {
    Write-Log "Unknown browser name: '$Name'. Run '.\run.ps1 os browser --list' for the catalog." -Level "fail"
    Save-LogFile -Status "fail"
    exit 2
}

Write-Log "Target browser: $($entry.DisplayName) (key='$($entry.Key)', ProgId='$($entry.ProgId)')" -Level "info"

# 1. Detection
$exePath = Find-InstalledExecutable -Entry $entry
if (-not $exePath) {
    Write-Log "Browser '$($entry.DisplayName)' is NOT installed. Probed paths:" -Level "fail"
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
    Write-Log "DRY-RUN: would then verify HKCU\...\http\UserChoice\ProgId equals '$($entry.ProgId)'." -Level "info"
    Save-LogFile -Status "ok"
    exit 0
}

# 2. Read current default for http (cosmetic -- show the user the before)
$userChoiceKey = "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice"
$currentProgId = $null
try {
    $currentProgId = (Get-ItemProperty -Path $userChoiceKey -Name "ProgId" -ErrorAction SilentlyContinue).ProgId
} catch {
    Write-Log "Could not read current default at ${userChoiceKey}: $($_.Exception.Message)" -Level "warn"
}
if ($currentProgId) {
    Write-Log "Current default for http:// = $currentProgId" -Level "info"
    if ($currentProgId -eq $entry.ProgId) {
        Write-Log "$($entry.DisplayName) is ALREADY the default browser. Nothing to do." -Level "success"
        Save-LogFile -Status "ok"
        exit 0
    }
}

# 3. Launch the modern Settings deeplink scoped to the app
$deeplink = "ms-settings:defaultapps?registeredAppUser=" + [uri]::EscapeDataString($entry.AppName)
Write-Log "Opening Settings deeplink: $deeplink" -Level "info"
Write-Log "Click 'Set default' in the dialog that appears, then return here." -Level "info"
try {
    Start-Process $deeplink | Out-Null
} catch {
    Write-Log "Failed to open Settings deeplink: $($_.Exception.Message)" -Level "fail"
    Write-Log "Fallback: open Settings -> Apps -> Default apps -> '$($entry.DisplayName)' -> Set default." -Level "info"
    Save-LogFile -Status "fail"
    exit 4
}

# 4. Wait + verify (skip the wait when --yes implies non-interactive CI)
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
    Write-Log "Verified: default http handler is now '$($entry.ProgId)' ($($entry.DisplayName))." -Level "success"
    Save-LogFile -Status "ok"
    exit 0
} else {
    Write-Log "Default browser was NOT changed (still '$finalProgId', wanted '$($entry.ProgId)')." -Level "warn"
    Write-Log "Windows 10/11 requires the user to click 'Set default' in the Settings dialog." -Level "info"
    Write-Log "Re-run '.\run.ps1 os browser $($entry.Key)' and complete the dialog within 60s." -Level "info"
    Save-LogFile -Status "partial"
    exit 5
}
