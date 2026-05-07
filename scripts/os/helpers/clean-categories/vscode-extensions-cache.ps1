<# Bucket F: vscode-extensions-cache -- per-extension cache/log directories
   inside %USERPROFILE%\.vscode\extensions\<publisher>.<name>-<ver>\.
   Sweeps subdirs named "cache", ".cache", "logs", ".logs", "tmp" and the
   shared CachedExtensions / CachedExtensionVSIXs folders under %APPDATA%\Code.
   The extension code itself, settings.json, keybindings, snippets are SAFE.
#>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "vscode-extensions-cache" -Label "VS Code per-extension cache + logs (extensions SAFE)" -Bucket "F"

$extDir = Join-Path (Get-UserProfilePath) ".vscode\extensions"
$codeAppData = Join-Path (Get-AppDataPath) "Code"

$hasExt = Test-Path -LiteralPath $extDir
$hasCode = Test-Path -LiteralPath $codeAppData
if (-not $hasExt -and -not $hasCode) {
    $result.Notes += "VS Code not installed (no $extDir, no $codeAppData)"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

# Per-extension cache/log subfolders (depth 1 only)
if ($hasExt) {
    try {
        $extFolders = @(Get-ChildItem -LiteralPath $extDir -Directory -Force -ErrorAction SilentlyContinue)
    } catch {
        Write-Log "vscode-extensions-cache enumerate failed at ${extDir}: $($_.Exception.Message)" -Level "warn"
        $extFolders = @()
    }
    $cacheNames = @("cache", ".cache", "logs", ".logs", "tmp", ".tmp")
    foreach ($ext in $extFolders) {
        foreach ($n in $cacheNames) {
            $sub = Join-Path $ext.FullName $n
            $isPresent = Test-Path -LiteralPath $sub
            if (-not $isPresent) { continue }
            Invoke-PathSweep -Path $sub -Result $result -DryRun:$DryRun -LogPrefix "vscode-ext/$($ext.Name)/$n"
        }
    }
} else {
    $result.Notes += "Per-extension scan skipped: $extDir missing"
}

# Shared extension caches under %APPDATA%\Code (workspace state NOT touched)
if ($hasCode) {
    foreach ($sub in @("CachedExtensions", "CachedExtensionVSIXs", "logs\exthost*")) {
        $isGlob = $sub.Contains('*')
        if ($isGlob) {
            try {
                $matches = Get-ChildItem -Path (Join-Path $codeAppData $sub) -Directory -Force -ErrorAction SilentlyContinue
                foreach ($m in $matches) {
                    Invoke-PathSweep -Path $m.FullName -Result $result -DryRun:$DryRun -LogPrefix "vscode/$($m.Name)"
                }
            } catch {
                Write-Log "vscode-extensions-cache glob failed at ${sub}: $($_.Exception.Message)" -Level "warn"
            }
        } else {
            Invoke-PathSweep -Path (Join-Path $codeAppData $sub) -Result $result -DryRun:$DryRun -LogPrefix "vscode/$sub"
        }
    }
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
