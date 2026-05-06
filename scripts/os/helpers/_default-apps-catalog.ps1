<#
.SYNOPSIS
    Shared catalog for browser + email default-app helpers (Windows side).

.DESCRIPTION
    A single source of truth for:
      - Aliases each name accepts (chrome, firefox, msedge, brave, ...).
      - The detection probes (executable basename + common install paths +
        chocolatey package names) used to decide if the app is installed.
      - The ProgId / ApplicationName the app registers in
        HKLM\SOFTWARE\Clients\* and HKLM\SOFTWARE\RegisteredApplications,
        used to pre-select it in the modern Settings deeplink.
      - The mailto / http(s) URL test we open after the user finishes
        the Settings dialog so they can confirm the change end-to-end.

    Intentionally read-only data -- both helpers (browser.ps1, email.ps1)
    dot-source this file. CODE RED: every probe path is real, surfaced in
    logs verbatim when missing.
#>

$script:BrowserCatalog = @(
    @{
        Key            = "chrome"
        Aliases        = @("chrome", "google-chrome", "googlechrome")
        DisplayName    = "Google Chrome"
        Exe            = "chrome.exe"
        InstallPaths   = @(
            "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
            "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
            "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
        )
        ChocoPackage   = "googlechrome"
        ProgId         = "ChromeHTML"
        AppName        = "Google Chrome"
    },
    @{
        Key            = "firefox"
        Aliases        = @("firefox", "ff", "mozilla-firefox", "mozilla")
        DisplayName    = "Mozilla Firefox"
        Exe            = "firefox.exe"
        InstallPaths   = @(
            "$env:ProgramFiles\Mozilla Firefox\firefox.exe",
            "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe"
        )
        ChocoPackage   = "firefox"
        ProgId         = "FirefoxURL"
        AppName        = "Firefox"
    },
    @{
        Key            = "edge"
        Aliases        = @("edge", "msedge", "microsoft-edge", "microsoftedge")
        DisplayName    = "Microsoft Edge"
        Exe            = "msedge.exe"
        InstallPaths   = @(
            "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
            "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
        )
        ChocoPackage   = "microsoft-edge"
        ProgId         = "MSEdgeHTM"
        AppName        = "Microsoft Edge"
    },
    @{
        Key            = "brave"
        Aliases        = @("brave", "brave-browser")
        DisplayName    = "Brave"
        Exe            = "brave.exe"
        InstallPaths   = @(
            "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe",
            "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe",
            "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe"
        )
        ChocoPackage   = "brave"
        ProgId         = "BraveHTML"
        AppName        = "Brave"
    },
    @{
        Key            = "opera"
        Aliases        = @("opera")
        DisplayName    = "Opera"
        Exe            = "opera.exe"
        InstallPaths   = @(
            "$env:LOCALAPPDATA\Programs\Opera\opera.exe",
            "$env:ProgramFiles\Opera\opera.exe"
        )
        ChocoPackage   = "opera"
        ProgId         = "OperaStable"
        AppName        = "Opera Stable"
    },
    @{
        Key            = "vivaldi"
        Aliases        = @("vivaldi")
        DisplayName    = "Vivaldi"
        Exe            = "vivaldi.exe"
        InstallPaths   = @(
            "$env:LOCALAPPDATA\Vivaldi\Application\vivaldi.exe",
            "$env:ProgramFiles\Vivaldi\Application\vivaldi.exe"
        )
        ChocoPackage   = "vivaldi"
        ProgId         = "VivaldiHTM"
        AppName        = "Vivaldi"
    },
    @{
        Key            = "librewolf"
        Aliases        = @("librewolf", "libre-wolf")
        DisplayName    = "LibreWolf"
        Exe            = "librewolf.exe"
        InstallPaths   = @(
            "$env:ProgramFiles\LibreWolf\librewolf.exe"
        )
        ChocoPackage   = "librewolf"
        ProgId         = "LibreWolfURL"
        AppName        = "LibreWolf"
    }
)

$script:EmailCatalog = @(
    @{
        Key            = "outlook"
        Aliases        = @("outlook", "outlook-classic", "outlook-desktop", "ms-outlook")
        DisplayName    = "Microsoft Outlook (desktop)"
        Exe            = "OUTLOOK.EXE"
        InstallPaths   = @(
            "$env:ProgramFiles\Microsoft Office\root\Office16\OUTLOOK.EXE",
            "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16\OUTLOOK.EXE",
            "$env:ProgramFiles\Microsoft Office\Office16\OUTLOOK.EXE",
            "${env:ProgramFiles(x86)}\Microsoft Office\Office16\OUTLOOK.EXE"
        )
        ChocoPackage   = "office365business"
        ProgId         = "Outlook.URL.mailto.15"
        AppName        = "Microsoft Outlook"
    },
    @{
        Key            = "outlook-new"
        Aliases        = @("outlook-new", "new-outlook", "outlook-store")
        DisplayName    = "Outlook for Windows (new, MSIX)"
        Exe            = "olk.exe"
        InstallPaths   = @(
            "$env:LOCALAPPDATA\Microsoft\WindowsApps\olk.exe"
        )
        ChocoPackage   = $null
        ProgId         = "Microsoft.OutlookForWindows_8wekyb3d8bbwe"
        AppName        = "Outlook"
    },
    @{
        Key            = "thunderbird"
        Aliases        = @("thunderbird", "tb", "mozilla-thunderbird")
        DisplayName    = "Mozilla Thunderbird"
        Exe            = "thunderbird.exe"
        InstallPaths   = @(
            "$env:ProgramFiles\Mozilla Thunderbird\thunderbird.exe",
            "${env:ProgramFiles(x86)}\Mozilla Thunderbird\thunderbird.exe"
        )
        ChocoPackage   = "thunderbird"
        ProgId         = "Thunderbird.Url.mailto"
        AppName        = "Mozilla Thunderbird"
    },
    @{
        Key            = "mailbird"
        Aliases        = @("mailbird")
        DisplayName    = "Mailbird"
        Exe            = "Mailbird.exe"
        InstallPaths   = @(
            "$env:LOCALAPPDATA\Mailbird\Mailbird.exe",
            "$env:ProgramFiles\Mailbird\Mailbird.exe"
        )
        ChocoPackage   = "mailbird"
        ProgId         = "Mailbird"
        AppName        = "Mailbird"
    },
    @{
        Key            = "em-client"
        Aliases        = @("em-client", "emclient", "em")
        DisplayName    = "eM Client"
        Exe            = "MailClient.exe"
        InstallPaths   = @(
            "$env:ProgramFiles\eM Client\MailClient.exe",
            "${env:ProgramFiles(x86)}\eM Client\MailClient.exe"
        )
        ChocoPackage   = "emclient"
        ProgId         = "eMClient.Url.mailto"
        AppName        = "eM Client"
    },
    @{
        Key            = "windows-mail"
        Aliases        = @("windows-mail", "mail", "win-mail")
        DisplayName    = "Windows Mail (legacy UWP)"
        Exe            = "HxOutlook.exe"
        InstallPaths   = @(
            "$env:LOCALAPPDATA\Packages\microsoft.windowscommunicationsapps_8wekyb3d8bbwe"
        )
        ChocoPackage   = $null
        ProgId         = "Microsoft.windowscommunicationsapps_8wekyb3d8bbwe"
        AppName        = "Mail"
    }
)

function Resolve-DefaultAppEntry {
    <#
    .SYNOPSIS
        Look up a catalog entry by user-supplied alias (case-insensitive).
        Returns $null on miss; caller is responsible for the error message.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet("browser", "email")][string]$Catalog
    )
    $needle = $Name.Trim().ToLower()
    if ([string]::IsNullOrWhiteSpace($needle)) { return $null }
    $list = if ($Catalog -eq "browser") { $script:BrowserCatalog } else { $script:EmailCatalog }
    foreach ($entry in $list) {
        if ($entry.Aliases -contains $needle) { return $entry }
    }
    return $null
}

function Find-InstalledExecutable {
    <#
    .SYNOPSIS
        Walk an entry's known install paths + PATH lookup. Returns the
        first existing file, or $null. CODE RED: every probed path that
        misses is recorded in $script:DefaultAppProbeMisses so the caller
        can dump them on failure with exact paths + reasons.
    #>
    param([Parameter(Mandatory)][hashtable]$Entry)

    if (-not (Get-Variable -Name DefaultAppProbeMisses -Scope Script -ErrorAction SilentlyContinue)) {
        $script:DefaultAppProbeMisses = @()
    }

    foreach ($p in $Entry.InstallPaths) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if (Test-Path -LiteralPath $p) { return $p }
        $script:DefaultAppProbeMisses += [pscustomobject]@{
            Path   = $p
            Reason = "file not present at expected install path"
        }
    }

    $cmd = Get-Command $Entry.Exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $script:DefaultAppProbeMisses += [pscustomobject]@{
        Path   = $Entry.Exe
        Reason = "not found on PATH (Get-Command returned nothing)"
    }
    return $null
}

function Get-DefaultAppCatalogList {
    <#
    .SYNOPSIS
        Render a colored two-column catalog used by both --list flags
        and the help block. Caller decides which catalog to render.
    #>
    param([Parameter(Mandatory)][ValidateSet("browser", "email")][string]$Catalog)
    $list = if ($Catalog -eq "browser") { $script:BrowserCatalog } else { $script:EmailCatalog }
    Write-Host ""
    Write-Host "  Available $Catalog names" -ForegroundColor Cyan
    Write-Host "  ===========================" -ForegroundColor DarkGray
    foreach ($entry in $list) {
        $aliasStr = ($entry.Aliases | Where-Object { $_ -ne $entry.Key }) -join ", "
        if ([string]::IsNullOrWhiteSpace($aliasStr)) { $aliasStr = "(no aliases)" }
        Write-Host ("    {0,-14} -> {1}" -f $entry.Key, $entry.DisplayName) -ForegroundColor Green
        Write-Host ("                   aliases: {0}" -f $aliasStr) -ForegroundColor DarkGray
    }
    Write-Host ""
}
