---
name: Write-Log bulletproof contract
description: scripts/shared/logging.ps1 Write-Log is wrapped in an outer try/catch and can NEVER throw — falls back to plain "[ INFO ] msg" on any internal failure. Eliminates the "Cannot index into a null array" class of crashes that surface at the caller's Write-Log line on Windows PowerShell 5.1.
type: feature
---
CODE RED contract: Write-Log is called from every script. If it throws, the
caller's stack trace points at the Write-Log call site (e.g.
`logging.ps1:697 Write-Log $msgLoading`) which is highly misleading — the real
bug is always inside Write-Log.

To prevent that whole class of errors, Write-Log:

1. Accepts `[AllowNull()][AllowEmptyString()]` on $Message.
2. Wraps the entire body in a defensive try/catch with a guaranteed
   `Write-Host "  [ INFO ] $safeMsg"` last-resort fallback.
3. Sub-wraps every fragile section (badge lookup, version-highlighting
   regex split/match, identity stamping, structured event recording).
4. Pulls $script:_LogIdentity fields by branching on hashtable vs PSCustomObject.
5. Lazily reinitializes $script:_LogEvents/_LogErrors/_LogWarnings if any
   were nulled out (re-sourcing logging.ps1 in the same session can do that
   on Windows PowerShell 5.1).
6. Color lookup falls back to "Gray" when $colors[$Status] returns null.
7. Version-highlighting [regex]::Split / IsMatch is in its own try/catch with
   a "print verbatim" safe fallback.

Companion fix in Import-JsonConfig: $script:SharedLogMessages is resolved via
Get-Variable + try/catch instead of bare $script:SharedLogMessages access,
which throws under StrictMode Latest when the variable was never set.

Verified against 16 hostile shapes (null LogMessages, null status, missing
levels, hashtable vs pscustom, null/empty/regex-laden messages, missing files).
