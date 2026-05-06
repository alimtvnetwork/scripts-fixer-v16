<#
.SYNOPSIS
    os fix-vscode-context-menu -- One-shot repair of the Windows folder
    right-click "Open with VS Code" entries.

.DESCRIPTION
    Thin convenience wrapper that delegates to script
    `scripts/52-vscode-folder-repair/run.ps1`, the canonical implementation
    of the registry repair (HKCR\Directory\shell\VSCode +
    HKCR\Directory\Background\shell\VSCode + Drive variants), backup +
    change ledger, post-repair PASS/FAIL verification, and Explorer
    refresh.

    Subcommand aliases exposed via flags so users don't need to know
    script 52 exists:

        --dry-run / --whatif    Preview without registry writes
        --verify                WhatIf + verbose registry trace (read-only)
        --verify-handlers       Standalone PASS/FAIL handler check (read-only)
        --no-restart            Repair but skip explorer.exe restart
        --trace                 Repair with VerboseRegistry trace
        --restore               Restore newest BEFORE snapshot (.reg import)
        --rollback              Restore default installer entries
        --refresh               Lightweight Explorer/shell refresh only

    Common options:
        --edition stable|insiders   Target edition (auto-detected when omitted)
        --snapshot-dir <path>       Override snapshot folder
        --restore-from <path>       Explicit .reg snapshot for --restore
        --require-signature         Enforce Authenticode signer check
        --non-interactive           Suppress prompts (CI mode)
        --help                      Show script-52 help

    Refuses cleanly on non-Windows so cross-OS callers see actionable text
    instead of a cryptic registry error.

.NOTES
    Per project rule: every file/path error must include exact path and
    failure reason (uses Write-FileError when available).
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$helpersDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$osDir      = Split-Path -Parent $helpersDir
$scriptsDir = Split-Path -Parent $osDir
$sharedDir  = Join-Path $scriptsDir "shared"

. (Join-Path $sharedDir "logging.ps1")

# -- OS gate ----------------------------------------------------------------
$isWindows7Plus = $true
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $isWindows7Plus = $IsWindows
}
if (-not $isWindows7Plus) {
    Write-Host ""
    Write-Host "  [ FAIL ] " -ForegroundColor Red -NoNewline
    Write-Host "'os fix-vscode-context-menu' is Windows-only (failure: current OS is not Windows)."
    Write-Host "          Reason: it writes to HKEY_CLASSES_ROOT registry keys that exist only on Windows." -ForegroundColor Gray
    exit 2
}

# -- Locate script 52 -------------------------------------------------------
$script52Dir = Join-Path $scriptsDir "52-vscode-folder-repair"
$script52Run = Join-Path $script52Dir "run.ps1"
if (-not (Test-Path -LiteralPath $script52Run)) {
    if (Get-Command Write-FileError -ErrorAction SilentlyContinue) {
        Write-FileError `
            -FilePath  $script52Run `
            -Operation "load" `
            -Reason    "script 52 entry script is missing from the repository" `
            -Module    "os fix-vscode-context-menu"
    } else {
        Write-Host ""
        Write-Host "  [ FAIL ] " -ForegroundColor Red -NoNewline
        Write-Host "Cannot find script 52 entry: $script52Run"
        Write-Host "          Reason: file does not exist (failure: missing repo asset)." -ForegroundColor Gray
    }
    exit 2
}

# -- Argument parser --------------------------------------------------------
# Translate the friendly --flags accepted here into the (Command, named-param)
# shape that scripts/52-vscode-folder-repair/run.ps1 expects.
$subCommand   = $null
$forwardArgs  = @{}
$passthrough  = @()

if ($null -ne $Rest -and $Rest.Count -gt 0) {
    for ($i = 0; $i -lt $Rest.Count; $i++) {
        $raw = $Rest[$i]
        if ($null -eq $raw) { continue }
        $tok = "$raw".Trim()
        $low = $tok.ToLower()
        switch -Regex ($low) {
            '^(--?help|/\?|-h|help|\?)$'                      { $forwardArgs['Help'] = $true; break }
            '^(--?dry-run|--?whatif|dry-run|whatif)$'         { if ($null -eq $subCommand) { $subCommand = 'dry-run' } ; break }
            '^(--?verify|verify)$'                            { if ($null -eq $subCommand) { $subCommand = 'verify' } ; break }
            '^(--?verify-handlers|verify-handlers)$'          { if ($null -eq $subCommand) { $subCommand = 'verify-handlers' } ; break }
            '^(--?trace|trace)$'                              { if ($null -eq $subCommand) { $subCommand = 'trace' } ; break }
            '^(--?restore|restore)$'                          { if ($null -eq $subCommand) { $subCommand = 'restore' } ; break }
            '^(--?rollback|rollback)$'                        { if ($null -eq $subCommand) { $subCommand = 'rollback' } ; break }
            '^(--?refresh|refresh)$'                          { if ($null -eq $subCommand) { $subCommand = 'refresh' } ; break }
            '^(--?no-restart|no-restart)$'                    { if ($null -eq $subCommand) { $subCommand = 'no-restart' } ; break }
            '^(--?repair|repair)$'                            { if ($null -eq $subCommand) { $subCommand = 'repair' } ; break }
            '^(--?require-signature|require-signature)$'      { $forwardArgs['RequireSignature'] = $true; break }
            '^(--?non-interactive|non-interactive)$'          { $forwardArgs['NonInteractive']   = $true; break }
            '^(--?edition|edition)$' {
                $i++
                if ($i -lt $Rest.Count) { $forwardArgs['Edition'] = "$($Rest[$i])" }
                break
            }
            '^(--?snapshot-dir|snapshot-dir)$' {
                $i++
                if ($i -lt $Rest.Count) { $forwardArgs['SnapshotDir'] = "$($Rest[$i])" }
                break
            }
            '^(--?restore-from|--?restore-from-file|restore-from|restore-from-file)$' {
                $i++
                if ($i -lt $Rest.Count) { $forwardArgs['RestoreFromFile'] = "$($Rest[$i])" }
                break
            }
            default {
                # Unknown -> forward as-is so callers can use any future
                # script 52 flag (e.g. refresh's --both / --restart) without
                # this wrapper needing an update.
                $passthrough += $tok
            }
        }
    }
}

# Default subcommand: full repair
if ($null -eq $subCommand) { $subCommand = 'repair' }

# -- Friendly banner --------------------------------------------------------
Write-Host ""
Write-Host "  os fix-vscode-context-menu" -ForegroundColor Cyan
Write-Host "  ==========================" -ForegroundColor DarkGray
Write-Host ("  Mode      : " + $subCommand) -ForegroundColor Yellow
Write-Host ("  Delegates : " + $script52Run) -ForegroundColor DarkGray
if ($forwardArgs.Count -gt 0) {
    $kv = ($forwardArgs.GetEnumerator() | ForEach-Object {
        $vv = if ($_.Value -is [switch] -or $_.Value -is [bool]) { '[switch]' } else { "$($_.Value)" }
        "$($_.Key)=$vv"
    }) -join ", "
    Write-Host ("  Options   : " + $kv) -ForegroundColor DarkGray
}
if ($passthrough.Count -gt 0) {
    Write-Host ("  Forward   : " + ($passthrough -join ' ')) -ForegroundColor DarkGray
}
Write-Host ""

# -- Invoke script 52 -------------------------------------------------------
try {
    if ($passthrough.Count -gt 0) {
        & $script52Run $subCommand @forwardArgs @passthrough
    } else {
        & $script52Run $subCommand @forwardArgs
    }
    exit $LASTEXITCODE
} catch {
    Write-Host ""
    Write-Host "  [ FAIL ] " -ForegroundColor Red -NoNewline
    Write-Host "os fix-vscode-context-menu failed while invoking script 52."
    Write-Host ("          Script : " + $script52Run) -ForegroundColor Gray
    Write-Host ("          Reason : " + $_.Exception.Message) -ForegroundColor Gray
    exit 1
}
