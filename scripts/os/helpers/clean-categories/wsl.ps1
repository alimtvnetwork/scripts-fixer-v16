<# Bucket F: wsl -- WSL distro temp + cache (NOT distro rootfs/user files) #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "wsl" -Label "WSL temp + package cache (rootfs safe)" -Bucket "F"

# Detect WSL presence: wsl.exe must be on PATH.
$wslExe = Get-Command wsl.exe -ErrorAction SilentlyContinue
if ($null -eq $wslExe) {
    $result.Notes += "WSL not installed (wsl.exe not on PATH)"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

# Enumerate distros (skip header line, skip empty)
$distros = @()
try {
    $raw = & wsl.exe --list --quiet 2>$null
    if ($LASTEXITCODE -eq 0 -and $raw) {
        # wsl.exe outputs UTF-16 with NULs; strip them
        $distros = @($raw | ForEach-Object { ($_ -replace "`0","").Trim() } | Where-Object { $_ -and $_ -notmatch "^Windows Subsystem" })
    }
} catch {
    Write-Log "wsl --list failed: $($_.Exception.Message)" -Level "warn"
    $result.Notes += "wsl --list failed: $($_.Exception.Message)"
}

if ($distros.Count -eq 0) {
    $result.Notes += "No WSL distros registered"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

# Inside each distro: clean common safe locations (NEVER /home, NEVER /etc).
# /tmp/*, /var/tmp/*, /var/cache/apt/archives/*.deb, ~/.cache/* (per default user)
$cleanScript = @'
set -e
B=0
for P in /tmp /var/tmp; do
  if [ -d "$P" ]; then
    SZ=$(du -sb "$P" 2>/dev/null | awk '{print $1}'); B=$((B + ${SZ:-0}))
    find "$P" -mindepth 1 -delete 2>/dev/null || true
  fi
done
if [ -d /var/cache/apt/archives ]; then
  SZ=$(du -sb /var/cache/apt/archives 2>/dev/null | awk '{print $1}'); B=$((B + ${SZ:-0}))
  apt-get clean >/dev/null 2>&1 || rm -f /var/cache/apt/archives/*.deb 2>/dev/null || true
fi
HC="$HOME/.cache"
if [ -d "$HC" ]; then
  SZ=$(du -sb "$HC" 2>/dev/null | awk '{print $1}'); B=$((B + ${SZ:-0}))
  find "$HC" -mindepth 1 -delete 2>/dev/null || true
fi
echo "BYTES=$B"
'@

$dryScript = @'
B=0
for P in /tmp /var/tmp /var/cache/apt/archives "$HOME/.cache"; do
  if [ -d "$P" ]; then
    SZ=$(du -sb "$P" 2>/dev/null | awk '{print $1}'); B=$((B + ${SZ:-0}))
  fi
done
echo "BYTES=$B"
'@

foreach ($d in $distros) {
    if (-not $d) { continue }
    $script = if ($DryRun) { $dryScript } else { $cleanScript }
    try {
        $output = & wsl.exe -d $d -- bash -c $script 2>&1
        $bytesLine = @($output | Where-Object { $_ -match "^BYTES=" }) | Select-Object -Last 1
        $b = 0
        if ($bytesLine -and ($bytesLine -match "^BYTES=(\d+)")) { $b = [long]$Matches[1] }
        if ($DryRun) {
            $result.WouldBytes += $b
            if ($b -gt 0) { $result.WouldCount += 1 }
            $result.Notes += "DRY-RUN ${d}: would free ~$([Math]::Round($b/1MB,2)) MB"
        } else {
            $result.Bytes += $b
            if ($b -gt 0) { $result.Count += 1 }
            $result.Notes += "${d}: freed ~$([Math]::Round($b/1MB,2)) MB"
        }
    } catch {
        Write-Log "wsl distro '${d}' clean failed: $($_.Exception.Message)" -Level "warn"
        $result.Notes += "Distro '${d}' failed: $($_.Exception.Message)"
        $result.Locked++
        $result.LockedDetails += @{ Path = "wsl://${d}"; Reason = $_.Exception.Message }
    }
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
