<# Bucket A: chkdsk -- C:\found.*\*.chk fragments #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "chkdsk" -Label "Chkdsk file fragments (C:\found.*)" -Bucket "A"

$found = @(Get-ChildItem -Path "C:\" -Directory -Force -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -match '^found\.\d+$' })

if ($found.Count -eq 0) {
    $result.Notes += "No found.* directories present (no chkdsk fragments)"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

foreach ($f in $found) {
    Invoke-PathSweep -Path $f.FullName -Result $result -DryRun:$DryRun -Filter "*.chk" -LogPrefix "chkdsk"
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
