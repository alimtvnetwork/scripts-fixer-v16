<#
.SYNOPSIS
    Read-only validator for the VS Code right-click context-menu registry
    keys (folder + empty-folder/background) for both Stable and Insiders.

.DESCRIPTION
    Probes the well-known HKCR keys script 52 manages and reports each
    target as one of:
        OK        key + \command default present, exe path looks valid
        MISSING   key (or its \command subkey) does not exist
        BROKEN    key exists but \command default is empty / points to a
                  non-existent exe / wrong shape
    Emits a colored table and returns the structured result so callers
    can decide exit code / further action.

    CODE RED: every probe failure logs the EXACT registry path + reason.
#>

function Get-VsCodeMenuTargets {
    <#
    .SYNOPSIS
        Static catalog of the registry targets script 52 owns. One row per
        (edition, scope) pair. exeHint is a substring expected in the
        \command default value when the entry is healthy.
    #>
    return @(
        @{ edition='Stable';   scope='folder';     verb='VSCode';         key='HKCR\Directory\shell\VSCode';                       exeHint='Code.exe' }
        @{ edition='Stable';   scope='background'; verb='VSCode';         key='HKCR\Directory\Background\shell\VSCode';            exeHint='Code.exe' }
        @{ edition='Insiders'; scope='folder';     verb='VSCodeInsiders'; key='HKCR\Directory\shell\VSCodeInsiders';               exeHint='Code - Insiders.exe' }
        @{ edition='Insiders'; scope='background'; verb='VSCodeInsiders'; key='HKCR\Directory\Background\shell\VSCodeInsiders';    exeHint='Code - Insiders.exe' }
    )
}

function _Get-RegDefaultValue {
    <#
    .SYNOPSIS  Returns the (Default) string value of $RegPath, or $null.
    #>
    param([string]$RegPath)
    $out = & reg.exe query $RegPath /ve 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    foreach ($line in $out) {
        if ($line -match '\(Default\)\s+REG_(SZ|EXPAND_SZ)\s+(.*)$') {
            return $matches[2].Trim()
        }
    }
    return $null
}

function _Test-RegKeyExists {
    param([string]$RegPath)
    $null = & reg.exe query $RegPath 2>$null
    return ($LASTEXITCODE -eq 0)
}

function _Resolve-CommandExePath {
    <#
    .SYNOPSIS  Pulls the .exe path out of a registry command line, expands
               %SystemRoot% / %ProgramFiles% / %LOCALAPPDATA% etc.
    #>
    param([string]$CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }
    # Match the first quoted token (typical: "C:\...\Code.exe" "%V")
    if ($CommandLine -match '^"([^"]+\.exe)"') {
        $raw = $matches[1]
    } elseif ($CommandLine -match '^(\S+\.exe)') {
        $raw = $matches[1]
    } else {
        return $null
    }
    return [Environment]::ExpandEnvironmentVariables($raw)
}

function Test-VsCodeContextMenu {
    <#
    .SYNOPSIS
        Validates every (edition, scope) target. Returns a hashtable:
            @{
                Targets = @( @{ edition; scope; key; status; reason; commandLine; exePath } ... )
                IsAllOk = <bool>
                Summary = @{ Ok=<int>; Missing=<int>; Broken=<int>; Total=<int> }
            }

    .PARAMETER PrintTable
        When $true (default), prints a colored PASS/FAIL table to the host.
    #>
    param([bool]$PrintTable = $true)

    $targets = Get-VsCodeMenuTargets
    $rows    = New-Object System.Collections.Generic.List[hashtable]

    foreach ($t in $targets) {
        $key     = $t.key
        $cmdKey  = "$key\command"

        $row = @{
            edition     = $t.edition
            scope       = $t.scope
            key         = $key
            status      = 'MISSING'
            reason      = ''
            commandLine = $null
            exePath     = $null
        }

        if (-not (_Test-RegKeyExists -RegPath $key)) {
            $row.reason = "registry key absent: $key"
            $rows.Add($row); continue
        }
        if (-not (_Test-RegKeyExists -RegPath $cmdKey)) {
            $row.status = 'BROKEN'
            $row.reason = "missing \\command subkey at: $cmdKey"
            $rows.Add($row); continue
        }

        $cmdLine = _Get-RegDefaultValue -RegPath $cmdKey
        $row.commandLine = $cmdLine
        if ([string]::IsNullOrWhiteSpace($cmdLine)) {
            $row.status = 'BROKEN'
            $row.reason = "\\command (Default) value is empty at: $cmdKey"
            $rows.Add($row); continue
        }

        $exe = _Resolve-CommandExePath -CommandLine $cmdLine
        $row.exePath = $exe
        if ([string]::IsNullOrWhiteSpace($exe)) {
            $row.status = 'BROKEN'
            $row.reason = "could not extract .exe from command line: $cmdLine"
            $rows.Add($row); continue
        }
        if (-not (Test-Path -LiteralPath $exe)) {
            $row.status = 'BROKEN'
            $row.reason = "exe referenced by \\command does not exist on disk: $exe"
            $rows.Add($row); continue
        }
        if ($t.exeHint -and ($exe -notlike "*$($t.exeHint)*")) {
            $row.status = 'BROKEN'
            $row.reason = "exe '$exe' does not match expected hint '$($t.exeHint)' for $($t.edition)"
            $rows.Add($row); continue
        }

        $row.status = 'OK'
        $rows.Add($row)
    }

    $okCount      = ($rows | Where-Object { $_.status -eq 'OK' }).Count
    $missingCount = ($rows | Where-Object { $_.status -eq 'MISSING' }).Count
    $brokenCount  = ($rows | Where-Object { $_.status -eq 'BROKEN' }).Count

    $result = @{
        Targets = @($rows)
        IsAllOk = ($missingCount -eq 0 -and $brokenCount -eq 0)
        Summary = @{ Ok = $okCount; Missing = $missingCount; Broken = $brokenCount; Total = $rows.Count }
    }

    if ($PrintTable) {
        Write-Host ""
        Write-Host "  VS Code context-menu registry check" -ForegroundColor Cyan
        Write-Host "  -----------------------------------" -ForegroundColor DarkGray
        $fmt = "  {0,-8} {1,-9} {2,-12} {3,-50}"
        Write-Host ($fmt -f "EDITION", "SCOPE", "STATUS", "KEY") -ForegroundColor Yellow
        Write-Host ($fmt -f "--------", "---------", "------------", "--------------------------------------------------") -ForegroundColor DarkGray

        foreach ($r in $rows) {
            $tag = switch ($r.status) {
                'OK'      { '[  OK  ]' }
                'MISSING' { '[ MISS ]' }
                'BROKEN'  { '[ FAIL ]' }
            }
            $colour = switch ($r.status) {
                'OK'      { 'Green' }
                'MISSING' { 'Yellow' }
                'BROKEN'  { 'Red' }
            }
            Write-Host ($fmt -f $r.edition, $r.scope, $tag, $r.key) -ForegroundColor $colour
            if ($r.status -ne 'OK' -and $r.reason) {
                Write-Host ("           reason : " + $r.reason) -ForegroundColor DarkGray
            }
            if ($r.status -ne 'OK' -and $r.commandLine) {
                Write-Host ("           command: " + $r.commandLine) -ForegroundColor DarkGray
            }
        }

        Write-Host ""
        $sumColour = if ($result.IsAllOk) { 'Green' } else { 'Red' }
        Write-Host ("  Summary: OK={0}  MISSING={1}  BROKEN={2}  TOTAL={3}" -f $okCount, $missingCount, $brokenCount, $rows.Count) -ForegroundColor $sumColour
        if (-not $result.IsAllOk) {
            Write-Host "  Fix:     .\run.ps1 os context-menu install   (runs script 52 repair + script 53 install)" -ForegroundColor DarkGray
            Write-Host "           .\run.ps1 -I 52 repair               (VS Code keys only)" -ForegroundColor DarkGray
        }
        Write-Host ""
    }

    return $result
}
