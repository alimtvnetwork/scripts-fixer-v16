<# Bucket B: recent-docs -- %APPDATA%\Microsoft\Windows\Recent\* (top files) #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "recent-docs" -Label "Quick Access recent files" -Bucket "B"
$recent = Join-Path (Get-AppDataPath) "Microsoft\Windows\Recent"

if (-not (Test-Path -LiteralPath $recent)) {
    $result.Notes += "Path not present: $recent"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

# Only top-level *.lnk files -- subfolders (AutomaticDestinations, CustomDestinations) are jumplist's domain
$files = @(Get-ChildItem -LiteralPath $recent -Force -File -ErrorAction SilentlyContinue)
foreach ($f in $files) {
    $sz = $f.Length
    if ($DryRun) { $result.WouldCount++; $result.WouldBytes += $sz; continue }
    try {
        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
        $result.Count++; $result.Bytes += $sz
    } catch {
        $result.Locked++
        $result.LockedDetails += @{ Path = $f.FullName; Reason = (Get-LockReason -Ex $_.Exception) }
        Write-Log "recent-docs locked at $($f.FullName): $($_.Exception.Message)" -Level "warn"
    }
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
