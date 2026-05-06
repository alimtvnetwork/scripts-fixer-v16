---
name: Subdispatcher help flags
description: All bare-subcommand dispatchers (os, profile, models, vscode-folder, git-tools, gsa) accept help, --help, -help, -h, /?, ? as aliases. Root forwards -h/-Help when no subaction is given.
type: preference
---
Every bare subcommand dispatcher (`os`, `profile`, `models`, `vscode-folder`,
`git-tools`, `gsa`) MUST accept all of these as the help action:

```
help   --help   -help   -h   /?   ?   <empty>
```

**Root-level forwarding**: PowerShell's parameter binder on root `run.ps1`
swallows `-h` and `-Help` (partial match) before they reach `$Install`. The
root dispatcher therefore detects `($h -or $Help)` and forwards `--help` to
the subdispatcher when no other action was supplied.

**Pattern in subdispatcher run.ps1**:
```powershell
{ $_ -in @("help", "--help", "-help", "-h", "/?", "?", "") } {
    Show-XHelp
    exit 0
}
```

**Pattern in root run.ps1** (per subcommand branch):
```powershell
$hasOsAction = ($osArgs.Count -gt 0) -and -not ("$($osArgs[0])".StartsWith("-"))
if (($h -or $Help) -and -not $hasOsAction) {
    & $osScript "--help"
    exit $LASTEXITCODE
}
```

User commands that MUST work identically:
- `.\run.ps1 os -h`
- `.\run.ps1 os -help`
- `.\run.ps1 os --help`
- `.\run.ps1 os help`
