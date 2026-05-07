<# Bucket F: android-studio-cache -- IDE caches + AVD snapshots/cache + Gradle daemon.
   Cleans:
     %LOCALAPPDATA%\Google\AndroidStudio*\caches \ log \ tmp
     %LOCALAPPDATA%\JetBrains\AndroidStudio*\caches \ log \ tmp
     %USERPROFILE%\.android\cache, %USERPROFILE%\.android\avd\*\snapshots\
   SAFE: SDK packages under %LOCALAPPDATA%\Android\Sdk, project files,
         AVD config.ini / userdata-qemu.img (only snapshots get nuked).
#>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "android-studio-cache" -Label "Android Studio caches + AVD snapshots (SDK + projects SAFE)" -Bucket "F"

$candidates = @(
    @{ Path = (Join-Path (Get-LocalAppDataPath) "Google");     Filter = "AndroidStudio*" },
    @{ Path = (Join-Path (Get-LocalAppDataPath) "JetBrains");  Filter = "AndroidStudio*" }
)

$cacheSubs = @("caches", "log", "tmp")
$foundAny = $false

foreach ($c in $candidates) {
    $isPresent = Test-Path -LiteralPath $c.Path
    if (-not $isPresent) { continue }
    try {
        $studios = @(Get-ChildItem -LiteralPath $c.Path -Directory -Filter $c.Filter -Force -ErrorAction SilentlyContinue)
    } catch {
        Write-Log "android-studio enumerate failed at $($c.Path): $($_.Exception.Message)" -Level "warn"
        continue
    }
    foreach ($s in $studios) {
        $foundAny = $true
        foreach ($sub in $cacheSubs) {
            $target = Join-Path $s.FullName $sub
            if (-not (Test-Path -LiteralPath $target)) { continue }
            Invoke-PathSweep -Path $target -Result $result -DryRun:$DryRun -LogPrefix "android-studio/$($s.Name)/$sub"
        }
    }
}

# AVD snapshots + ~/.android/cache
$dotAndroid = Join-Path (Get-UserProfilePath) ".android"
if (Test-Path -LiteralPath $dotAndroid) {
    $foundAny = $true
    $cacheDir = Join-Path $dotAndroid "cache"
    if (Test-Path -LiteralPath $cacheDir) {
        Invoke-PathSweep -Path $cacheDir -Result $result -DryRun:$DryRun -LogPrefix "android/cache"
    }
    $avdRoot = Join-Path $dotAndroid "avd"
    if (Test-Path -LiteralPath $avdRoot) {
        try {
            $avds = @(Get-ChildItem -LiteralPath $avdRoot -Directory -Filter "*.avd" -Force -ErrorAction SilentlyContinue)
        } catch {
            Write-Log "android-studio AVD enumerate failed at ${avdRoot}: $($_.Exception.Message)" -Level "warn"
            $avds = @()
        }
        foreach ($a in $avds) {
            $snap = Join-Path $a.FullName "snapshots"
            if (Test-Path -LiteralPath $snap) {
                Invoke-PathSweep -Path $snap -Result $result -DryRun:$DryRun -LogPrefix "android/avd/$($a.Name)/snapshots"
            }
        }
    }
}

if (-not $foundAny) {
    $result.Notes += "Android Studio not installed (no AndroidStudio* under Google/JetBrains, no ~/.android)"
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
