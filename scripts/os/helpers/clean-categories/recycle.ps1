<# Bucket A: recycle -- empty Recycle Bin on every drive (DESTRUCTIVE, consent-gated) #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "recycle" -Label "Recycle Bin (all drives)" -Bucket "A" -Destructive

$consented = Confirm-DestructiveCategory -Category "recycle" `
    -Warning "UNRECOVERABLE deletion of every Recycle Bin on every drive." `
    -AutoYes:$Yes -DryRun:$DryRun
if (-not $consented) {
    $result.Status = "skip"
    $result.Notes += "Consent declined"
    return $result
}

# Pre-count via $Recycle.Bin enumeration so dry-run reports something useful.
$drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue
foreach ($d in $drives) {
    $rb = Join-Path $d.Root '$Recycle.Bin'
    if (-not (Test-Path -LiteralPath $rb)) { continue }
    try {
        $items = @(Get-ChildItem -LiteralPath $rb -Recurse -Force -ErrorAction SilentlyContinue |
                   Where-Object { -not $_.PSIsContainer })
        $bytes = ($items | Measure-Object -Property Length -Sum).Sum
        if ($null -eq $bytes) { $bytes = 0 }
        if ($DryRun) {
            $result.WouldCount += $items.Count
            $result.WouldBytes += [long]$bytes
            $result.Notes += "DRY-RUN: would empty $rb ($($items.Count) files)"
        }
    } catch {
        Write-Log "Recycle bin enumerate failed at ${rb}: $($_.Exception.Message)" -Level "warn"
    }
}

if (-not $DryRun) {
    foreach ($d in $drives) {
        try {
            Clear-RecycleBin -DriveLetter $d.Name -Force -ErrorAction Stop
            $result.Count++
            $result.Notes += "Emptied $($d.Name): recycle bin"
        } catch {
            if ($_.Exception.Message -match "empty|not contain") {
                $result.Notes += "$($d.Name): already empty"
            } else {
                $result.Locked++
                $result.LockedDetails += @{ Path = "$($d.Name):\`$Recycle.Bin"; Reason = (Get-LockReason -Ex $_.Exception) }
                Write-Log "Recycle bin failed for $($d.Name): $($_.Exception.Message)" -Level "warn"
            }
        }
    }
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
