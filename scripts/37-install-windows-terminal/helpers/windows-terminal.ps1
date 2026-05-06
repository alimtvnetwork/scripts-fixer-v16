# --------------------------------------------------------------------------
#  Helper: Install Windows Terminal via Chocolatey and sync settings
#  Supports 3 modes: install+settings (default), settings-only, install-only
# --------------------------------------------------------------------------

function Install-WindowsTerminal {
    param(
        [Parameter(Mandatory)] $WtConfig,
        [Parameter(Mandatory)] $LogMessages,
        [ValidateSet("install+settings", "settings-only", "install-only")]
        [string]$Mode = "install+settings"
    )

    $msgs = $LogMessages.messages

    # -- Mode announcement ---------------------------------------------
    $modeLabel = switch ($Mode) {
        "install+settings" { "WT + Settings (install Windows Terminal and sync settings)" }
        "settings-only"    { "WT Settings (sync settings only)" }
        "install-only"     { "Install WT (install Windows Terminal only)" }
    }
    Write-Log "Mode: $modeLabel" -Level "info"
    Write-Host ""

    # -- Settings-only mode: skip install, go straight to sync ---------
    if ($Mode -eq "settings-only") {
        Write-Log "Skipping Windows Terminal installation (settings-only mode)" -Level "info"
        $syncResult = Sync-WindowsTerminalSettings -LogMessages $LogMessages
        return $syncResult
    }

    # -- Check if already installed ------------------------------------
    $wtPath = $null

    # Windows Terminal (Store/MSIX) stores wt.exe in WindowsApps
    $wtCmd = Get-Command "wt" -ErrorAction SilentlyContinue
    if ($wtCmd) {
        $wtPath = Get-Item $wtCmd.Source
    }

    # Fallback: check common Chocolatey install paths
    if (-not $wtPath) {
        $commonPaths = @(
            "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe"
        )
        foreach ($p in $commonPaths) {
            if (Test-Path $p) {
                $wtPath = Get-Item $p
                break
            }
        }
    }

    if ($wtPath) {
        $version = "unknown"
        try {
            $versionOutput = & wt --version 2>&1 | Select-Object -First 1
            $hasVersion = $versionOutput -match '[\d]+\.[\d]+\.[\d]+'
            if ($hasVersion) {
                $version = $Matches[0]
            }
        } catch { }

        $isAlreadyInstalled = Test-AlreadyInstalled -Name "windows-terminal" -CurrentVersion $version
        if ($isAlreadyInstalled) {
            Write-Log ($msgs.alreadyInstalled -replace '\{version\}', $version) -Level "success"
            # Settings always sync (user may want to restore/fix)
            if ($Mode -eq "install+settings") {
                Sync-WindowsTerminalSettings -LogMessages $LogMessages
            }
            return $true
        }
    }

    # -- Install via Chocolatey ----------------------------------------
    Write-Log $msgs.notFound -Level "info"
    Write-Host ""
    Write-Log $msgs.installing -Level "info"

    try {
        choco install $WtConfig.chocoPackage -y --no-progress | Out-Null
    } catch {
        Write-FileError -FilePath "wt.exe" -Operation "install" -Reason "$_" -Module "Install-WindowsTerminal"
        Write-Log ($msgs.installFailed -replace '\{error\}', $_) -Level "error"
        Save-InstalledError -Name "windows-terminal" -ErrorMessage "$_"
        return $false
    }

    # -- Verify installation -------------------------------------------
    # Refresh PATH so newly-installed wt.exe (Chocolatey shim or WindowsApps alias) is discoverable
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    $verifyCmd = Get-Command "wt" -ErrorAction SilentlyContinue
    $verifiedPath = $null
    if ($verifyCmd) {
        $verifiedPath = $verifyCmd.Source
    } else {
        # Probe known install locations: Chocolatey shim, WindowsApps alias, MSIX package dir
        $candidatePaths = @(
            "$env:ChocolateyInstall\bin\wt.exe",
            "$env:ProgramData\chocolatey\bin\wt.exe",
            "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe"
        )
        $msixMatches = Get-ChildItem -Path "$env:ProgramFiles\WindowsApps" -Filter "wt.exe" -Recurse -ErrorAction SilentlyContinue |
                       Where-Object { $_.FullName -match 'Microsoft\.WindowsTerminal_' } |
                       Select-Object -First 1
        if ($msixMatches) { $candidatePaths += $msixMatches.FullName }

        foreach ($cp in $candidatePaths) {
            if ($cp -and (Test-Path $cp)) { $verifiedPath = $cp; break }
        }
    }

    if (-not $verifiedPath) {
        $checkedPath = "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe"
        Write-FileError -FilePath $checkedPath -Operation "resolve" -Reason "wt.exe not found after Chocolatey install (checked PATH, Chocolatey bin, WindowsApps alias, and Program Files\WindowsApps\Microsoft.WindowsTerminal_*)" -Module "Install-WindowsTerminal"
        Write-Log ($msgs.installFailed -replace '\{error\}', "wt.exe not found after install") -Level "error"
        return $false
    }

    Write-Log "Windows Terminal verified at: $verifiedPath" -Level "info"

    $version = "unknown"
    try {
        $versionOutput = & wt --version 2>&1 | Select-Object -First 1
        $hasVersion = $versionOutput -match '[\d]+\.[\d]+\.[\d]+'
        if ($hasVersion) { $version = $Matches[0] }
    } catch { }

    Write-Log ($msgs.installSuccess) -Level "success"
    Write-Log ("Install target: $($verifyCmd.Source)") -Level "success"
    Write-Host ""
    Save-InstalledRecord -Name "windows-terminal" -Version $version -Method "chocolatey"

    # -- Sync settings (only in install+settings mode) -----------------
    if ($Mode -eq "install+settings") {
        Sync-WindowsTerminalSettings -LogMessages $LogMessages
    } else {
        Write-Log "Settings sync skipped (install-only mode)" -Level "info"
    }

    return $true
}

function Sync-WindowsTerminalSettings {
    param(
        [Parameter(Mandatory)] $LogMessages
    )

    $msgs = $LogMessages.messages
    # $PSScriptRoot = helpers/ -> parent = 37-install-windows-terminal/ -> parent = scripts/ -> parent = repo root
    $repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $settingsSource = Join-Path $repoRoot "settings\03 - windows-terminal"

    # -- Target: %LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_*\LocalState\settings.json
    $wtPackageDir = Get-ChildItem -Path "$env:LOCALAPPDATA\Packages" -Filter "Microsoft.WindowsTerminal_*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1

    if (-not $wtPackageDir) {
        # Fallback for Windows Terminal Preview or non-Store installs
        $wtPackageDir = Get-ChildItem -Path "$env:LOCALAPPDATA\Packages" -Filter "Microsoft.WindowsTerminalPreview_*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    }

    if (-not $wtPackageDir) {
        Write-FileError -FilePath "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_*" -Operation "resolve" -Reason "Windows Terminal package directory not found" -Module "Sync-WindowsTerminalSettings"
        Write-Log $msgs.settingsSkipped -Level "info"
        return $false
    }

    $targetDir = Join-Path $wtPackageDir.FullName "LocalState"
    Write-Log "Settings target: $targetDir" -Level "info"

    # -- Check settings source exists -----------------------------------
    if (-not (Test-Path $settingsSource)) {
        Write-FileError -FilePath $settingsSource -Operation "read" -Reason "Windows Terminal settings source directory does not exist" -Module "Sync-WindowsTerminalSettings"
        Write-Log $msgs.settingsSkipped -Level "info"
        return $false
    }

    # -- Find settings.json in source ----------------------------------
    $sourceSettings = Join-Path $settingsSource "settings.json"
    $hasSettingsFile = Test-Path $sourceSettings
    if (-not $hasSettingsFile) {
        Write-FileError -FilePath $sourceSettings -Operation "read" -Reason "No settings.json found in Windows Terminal settings source" -Module "Sync-WindowsTerminalSettings"
        Write-Log $msgs.settingsSkipped -Level "info"
        return $false
    }

    Write-Log ($msgs.syncingSettings -replace '\{source\}', $settingsSource) -Level "info"

    # -- Ensure target directory exists --------------------------------
    if (-not (Test-Path $targetDir)) {
        New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
    }

    # -- Copy settings.json to target ----------------------------------
    try {
        $dest = Join-Path $targetDir "settings.json"
        Copy-Item -Path $sourceSettings -Destination $dest -Force
        Write-Log ($msgs.settingsSynced -replace '\{path\}', $dest) -Level "success"
    } catch {
        Write-FileError -FilePath $sourceSettings -Operation "copy" -Reason "Failed to copy settings.json: $_" -Module "Sync-WindowsTerminalSettings"
        Write-Log "Failed to copy settings: $_" -Level "error"
        return $false
    }

    # -- Copy any additional files (themes, fragments, etc.) -----------
    $extraFiles = Get-ChildItem -Path $settingsSource -File -Exclude "settings.json", "readme.txt" -ErrorAction SilentlyContinue
    $extraCount = 0
    foreach ($file in $extraFiles) {
        $dest = Join-Path $targetDir $file.Name
        Copy-Item -Path $file.FullName -Destination $dest -Force
        $extraCount++
    }
    if ($extraCount -gt 0) {
        Write-Log "Copied $extraCount additional file(s) to $targetDir" -Level "success"
    }

    return $true
}

function Export-WindowsTerminalSettings {
    <#
    .SYNOPSIS
        Exports Windows Terminal settings FROM the machine back INTO the repo's
        settings/03 - windows-terminal/ folder for backup/version control.
    #>
    param(
        [Parameter(Mandatory)] $LogMessages
    )

    $msgs = $LogMessages.messages

    # -- Find WT package directory -------------------------------------
    $wtPackageDir = Get-ChildItem -Path "$env:LOCALAPPDATA\Packages" -Filter "Microsoft.WindowsTerminal_*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $wtPackageDir) {
        $wtPackageDir = Get-ChildItem -Path "$env:LOCALAPPDATA\Packages" -Filter "Microsoft.WindowsTerminalPreview_*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    }

    $sourceDir = if ($wtPackageDir) { Join-Path $wtPackageDir.FullName "LocalState" } else { $null }

    # Target: repo/settings/03 - windows-terminal/
    $repoRoot  = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $targetDir = Join-Path $repoRoot "settings\03 - windows-terminal"

    Write-Log ($msgs.exportStarting -replace '\{source\}', $(if ($sourceDir) { $sourceDir } else { "LocalState" })) -Level "info"

    # -- Validate source exists ----------------------------------------
    $isSourceMissing = (-not $sourceDir) -or (-not (Test-Path $sourceDir))
    if ($isSourceMissing) {
        Write-FileError -FilePath "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_*\LocalState" -Operation "read" -Reason "Windows Terminal LocalState directory not found. Is Windows Terminal installed?" -Module "Export-WindowsTerminalSettings"
        Write-Log $msgs.exportNoSource -Level "error"
        return $false
    }

    # -- Check for settings.json ---------------------------------------
    $sourceSettings = Join-Path $sourceDir "settings.json"
    $hasSettingsFile = Test-Path $sourceSettings
    if (-not $hasSettingsFile) {
        Write-Log $msgs.exportNoFiles -Level "warn"
        return $false
    }

    # -- Ensure target directory exists --------------------------------
    $isTargetMissing = -not (Test-Path $targetDir)
    if ($isTargetMissing) {
        New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
        Write-Log "Created settings directory: $targetDir" -Level "info"
    }

    $copiedCount = 0

    # -- Copy settings.json --------------------------------------------
    try {
        $dest = Join-Path $targetDir "settings.json"
        Copy-Item -Path $sourceSettings -Destination $dest -Force
        $fileSizeKB = [math]::Round((Get-Item $sourceSettings).Length / 1024, 1)
        Write-Log "Exported: settings.json ($fileSizeKB KB)" -Level "success"
        $copiedCount++
    } catch {
        Write-FileError -FilePath $sourceSettings -Operation "copy" -Reason "Failed to export settings.json: $_" -Module "Export-WindowsTerminalSettings"
        Write-Log "Failed to export settings.json: $_" -Level "error"
    }

    # -- Copy any additional config files (fragments, themes) ----------
    $extraFiles = Get-ChildItem -Path $sourceDir -File -Exclude "state.json" -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "settings.json" }
    foreach ($file in $extraFiles) {
        $isReadme = $file.Name -eq "readme.txt"
        if ($isReadme) { continue }

        $fileSizeKB = [math]::Round($file.Length / 1024, 1)
        $isTooBig = $fileSizeKB -gt 512
        if ($isTooBig) {
            Write-Log "Skipped: $($file.Name) ($fileSizeKB KB -- too large)" -Level "info"
            continue
        }
        try {
            $dest = Join-Path $targetDir $file.Name
            Copy-Item -Path $file.FullName -Destination $dest -Force
            Write-Log "Exported: $($file.Name) ($fileSizeKB KB)" -Level "success"
            $copiedCount++
        } catch {
            Write-FileError -FilePath $file.FullName -Operation "copy" -Reason "Failed to export $($file.Name): $_" -Module "Export-WindowsTerminalSettings"
        }
    }

    $summary = $msgs.exportComplete -replace '\{count\}', $copiedCount -replace '\{path\}', $targetDir
    Write-Log $summary -Level "success"
    return $true
}

function Uninstall-WindowsTerminal {
    <#
    .SYNOPSIS
        Full Windows Terminal uninstall: choco uninstall, purge tracking.
    #>
    param(
        $WtConfig,
        $LogMessages
    )

    $packageName = $WtConfig.chocoPackage

    # 1. Uninstall via Chocolatey
    Write-Log ($LogMessages.messages.uninstalling -replace '\{name\}', "Windows Terminal") -Level "info"
    $isUninstalled = Uninstall-ChocoPackage -PackageName $packageName
    if ($isUninstalled) {
        Write-Log ($LogMessages.messages.uninstallSuccess -replace '\{name\}', "Windows Terminal") -Level "success"
    } else {
        Write-Log ($LogMessages.messages.uninstallFailed -replace '\{name\}', "Windows Terminal") -Level "error"
    }

    # 2. Remove tracking records
    Remove-InstalledRecord -Name "windows-terminal"
    Remove-ResolvedData -ScriptFolder "37-install-windows-terminal"

    Write-Log $LogMessages.messages.uninstallComplete -Level "success"
}
