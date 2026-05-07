# Spec: Error Management for PowerShell Scripts

> **Audience.** Anyone (human or AI) writing or reviewing a PowerShell script
> in this repo. Read this **before** you write a single `Write-Host`. The
> rules below are non-negotiable. The structured logger we ship
> (`scripts/shared/logging.ps1`) is the only sanctioned way to surface
> success, warnings, errors, and file-path failures.
>
> **CODE RED.** Every file/path failure **MUST** log the exact path that was
> attempted **and** the exact reason it failed. This is the single rule that
> trumps every stylistic preference in this document.

---

## 1. Folder structure for a new script

Every script lives under `scripts/<NN>-<kebab-name>/` and follows this shape:

```
scripts/
  NN-my-script/
    run.ps1                  # entry point. param([string[]]$Argv = @())
    config.json              # static config (paths, version pins, flags)
    log-messages.json        # all human-facing strings, keyed by message id
    readme.md                # what the script does, flags, examples
  shared/                    # reusable helpers (DO NOT duplicate)
    logging.ps1              # Initialize-Logging, Write-Log, Write-FileError, Save-LogFile
    confirm-prompt.ps1       # Confirm-DestructiveAction (--yes / --non-interactive)
    admin-check.ps1          # Test-IsElevated / Assert-Elevated
    install-paths.ps1        # Write-InstallPaths (triple-path stamp)
    json-utils.ps1           # Import-JsonConfig (validates + reports trimmed FilePath)
.logs/                       # output directory for JSON logs (auto-created)
  NN/<scriptname>.json
  NN/<scriptname>-error.json # only present when overallStatus != "ok"
spec/
  NN-my-script/readme.md     # design spec (this folder is the contract)
```

**Rules:**

1. **No string literals in `run.ps1` for human output.** Every user-visible
   message lives in `log-messages.json` and is loaded via `Import-JsonConfig`.
   That gives translators, summary writers, and CI parsers one place to look.
2. **No business logic in `log-messages.json`.** It is a flat string table.
3. **Always dot-source `scripts/shared/logging.ps1` first**, then call
   `Initialize-Logging -ScriptName "<name>"` exactly once near the top.
4. **Always end with `Save-LogFile -Status <ok|warn|fail|partial|skip>`**
   even on the failure path. Without it the JSON log is never written.

---

## 2. The two required calls

Every script must contain these two calls, in this order:

```powershell
$ErrorActionPreference = "Continue"
Set-StrictMode -Version Latest

$here   = Split-Path -Parent $MyInvocation.MyCommand.Definition
$shared = Join-Path (Split-Path -Parent $here) "shared"
. (Join-Path $shared "logging.ps1")
. (Join-Path $shared "json-utils.ps1")

$msgs = Import-JsonConfig (Join-Path $here "log-messages.json")
Initialize-Logging -ScriptName "my-script"

try {
    # ... work ...
    Save-LogFile -Status "ok"
    exit 0
} catch {
    Write-Log "Top-level failure: $($_.Exception.Message)" -Level "fail"
    Save-LogFile -Status "fail"
    exit 1
}
```

If you forget the `try/Save-LogFile/exit` envelope the run will look
"successful" to the orchestrator even on a crash.

---

## 3. Levels and what they mean

| Level    | When to use                                                    |
|----------|----------------------------------------------------------------|
| `info`   | Normal progress narration. The default.                        |
| `ok`     | A discrete unit of work succeeded (`Installed git 2.45.1`).    |
| `warn`   | Recoverable problem; the script continued.                     |
| `fail`   | Unrecoverable problem in this category/step. Caller continues. |
| `error`  | Synonym for `fail`. Prefer `fail` for new code.                |

Pick exactly one. A failure logged at `warn` will NOT be promoted into the
`-error.json` sidecar and CI will miss it.

---

## 4. CODE RED -- every file/path error MUST use `Write-FileError`

If your script touches a file, opens a stream, copies, moves, deletes,
extracts, parses JSON, or resolves a path -- and that operation can fail --
you MUST report the failure through `Write-FileError`. Plain `Write-Log`
loses the structured fields that the JSON parser, CI dashboards, and the
orchestrator's grand-summary table depend on.

### Signature

```powershell
Write-FileError `
    -FilePath  <string> `   # exact resolved path that was attempted
    -Operation <string> `   # read|write|copy|move|inject|load|extract|resolve|...
    -Reason    <string> `   # human-readable explanation
   [-Module    <string>] `  # auto-detected from call stack if omitted
   [-Fallback  <string>]    # what we did to recover (if anything)
```

### Mandatory fields in the resulting JSON event

Every file-error event written to `.logs/<NN>/<script>-error.json` carries:

```json
{
  "timestamp":      "2026-05-07T11:50:01.5508095+08:00",
  "level":          "fail",
  "type":           "file-error",
  "filePath":       "C:\\Windows\\SoftwareDistribution\\Download",
  "operation":      "delete",
  "reason":         "Access denied (locked or protected)",
  "module":         "wu-download.ps1",
  "fallback":       "wuauserv stopped, retried -- see warn line above",
  "message":        "[CODE RED] File error during delete: ...",
  "projectVersion": "1.1.1",
  "invokedFrom":    "run.ps1",
  "gitSha":         "d9d3ee90c118",
  "gitBranch":      "main",
  "scriptName":     "os-clean"
}
```

If any of `filePath`, `operation`, `reason`, or `module` is missing, the
log is **non-conformant** and will fail spec review.

### Forbidden patterns

```powershell
# ❌  Loses the path. The error contains a generic message and the user
#     cannot tell which file failed.
Write-Log "Could not read config" -Level "fail"

# ❌  Loses the reason. "$($_.Exception.Message)" alone is not a reason --
#     it is the reason. Pass it explicitly into Write-FileError.
Write-Log "Failed: $($_.Exception.Message)" -Level "fail"

# ❌  Mixes Write-Host (no JSON) with file-related work.
Write-Host "Could not write $path" -ForegroundColor Red
```

### Required pattern

```powershell
try {
    Copy-Item -LiteralPath $src -Destination $dst -Force -ErrorAction Stop
} catch {
    Write-FileError `
        -FilePath  $dst `
        -Operation "copy" `
        -Reason    $_.Exception.Message `
        -Fallback  "left $src in place; user can re-run with --force"
    Save-LogFile -Status "fail"
    exit 1
}
```

---

## 5. Per-step failure ledgers (multi-step scripts)

When a script runs many sub-steps in a loop (e.g. `os clean` walks 60 clean
categories) **collect per-step failures into a ledger** so the final summary
shows which step failed, on which path, with which reason. Pattern:

```powershell
$stepFailures = New-Object System.Collections.Generic.List[hashtable]

function Add-StepFailure {
    param([string]$Step, [string]$Path, [string]$Reason)
    $stepFailures.Add(@{ Step = $Step; Path = $Path; Reason = $Reason }) | Out-Null
    Write-Log "$ScriptName [$Step] FAIL path=$Path reason=$Reason" -Level "fail"
}

# ... at end of run ...
if ($stepFailures.Count -gt 0) {
    $result.Notes += "----- failure summary ($($stepFailures.Count) item(s)) -----"
    foreach ($f in $stepFailures) {
        $result.Notes += ("  [{0}] path={1}" -f $f.Step, $f.Path)
        $result.Notes += ("        reason: {0}" -f $f.Reason)
    }
}
```

The orchestrator already prints `$result.Notes` under each row. This is how
the user tells "vdf parse failed on G:" apart from "shadercache vanished".

---

## 6. StrictMode survival kit (the gotchas that bite every new author)

We always run with `Set-StrictMode -Version Latest`. The five rules below
prevent ~90 % of the "property 'Count' cannot be found" /
"variable cannot be retrieved" runtime crashes we have hit historically.

1. **Always wrap pipeline assignments in `@(...)`.** Otherwise `$x.Count`
   throws when the pipeline returns `$null` or a single scalar.
   ```powershell
   $files = @(Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue)
   if ($files.Count -eq 0) { return }
   ```
2. **Never read `$env:VAR` for a variable that may be unset.** Use
   `[Environment]::GetEnvironmentVariable("VAR")` instead -- `$env:` throws
   under StrictMode when the env var doesn't exist.
3. **Never put `\$VAR` inside a double-quoted string.** PowerShell's escape
   character is `` ` ``, not `\`. `"..(\$WINDIR\..)"` actually expands
   `$WINDIR` and crashes if it is unset. Use single quotes (`'...'`) or
   backtick (`` "..(`$WINDIR\..)" ``).
4. **Test for hashtable keys before reading them.**
   ```powershell
   if ($hash.ContainsKey('foo')) { $x = $hash['foo'] }
   ```
5. **Wrap risky external work in `try/catch` that calls `Write-FileError`,
   then continues** -- never let a single bad path abort the whole run.

---

## 7. `log-messages.json` schema

```jsonc
{
  "scriptName": "OS Clean",                    // appears in console banner + JSON
  "scriptId":   "65",                          // matches scripts/65-os-clean
  "synopsis":   "One-line summary",            // shown in --help
  "usage": [                                   // shown in --help
    ".\\run.ps1 -I 65",
    ".\\run.ps1 -I 65 -- --dry-run"
  ],
  "messages": {
    "PlanStart":  "Building plan...",          // referenced as $msgs.messages.PlanStart
    "PlanEmpty":  "Plan is empty.",
    "FileError":  "[FILE-ERROR] path={0} reason={1}"   // {0}, {1} are -f placeholders
  }
}
```

**Rules:**

- Keys are PascalCase, stable, never reordered (the orchestrator references
  them by name).
- Use `{0}`, `{1}` placeholders, never inline interpolation.
- Never put a real path or version number in here -- those come from
  `config.json` or runtime.

---

## 8. Writing portable Linux/macOS equivalents

When the same script needs a Bash sibling (we keep them under
`scripts-linux/<NN>-<name>/run.sh`), mirror the same contract:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
shared="$(cd "$here/../_shared" && pwd)"
. "$shared/logging.sh"           # log_info / log_warn / log_fail / file_error
. "$shared/json-utils.sh"        # import_json_config
. "$shared/install-paths.sh"     # write_install_paths

init_logging "my-script"

trap 'file_error "$LAST_PATH" "$LAST_OP" "$?" "$BASH_COMMAND"; save_log_file fail; exit 1' ERR

LAST_PATH="/etc/foo.conf"; LAST_OP="read"
content="$(cat "$LAST_PATH")"

save_log_file ok
```

The Bash `file_error` helper writes the **same JSON shape** as
`Write-FileError` -- `filePath`, `operation`, `reason`, `module`,
`scriptName`, etc. -- so a single dashboard can ingest both.

For a portable settings file (e.g. `tools/check-required-packages.config.json`)
keep the same JSON schema between Windows and Linux runs and let each
platform script load it through its own `Import-JsonConfig` /
`import_json_config` helper.

---

## 9. Console output rules

- **Use bracketed ASCII status glyphs**, never wide Unicode emoji:
  `[ OK ]`, `[FAIL]`, `[WARN]`, `[INFO]`, `[ == ]`.
- **No em-dashes** (`—`), no curly quotes, no box-drawing in banners --
  these break Windows ConHost in legacy code pages.
- Color via `Write-Host -ForegroundColor`, never raw ANSI escapes.
- The logger already prints colored prefixes; do not duplicate them.

---

## 10. Output artifacts -- where logs land

After `Save-LogFile`:

```
.logs/
  <NN>/
    <scriptname>.json          # always present; contains every event
    <scriptname>-error.json    # written ONLY when overallStatus != "ok"
                               #   -> contains the same identity fields as
                               #      <scriptname>.json, plus the full
                               #      errors[] / warnings[] arrays
    <scriptname>-summary.txt   # optional human-readable digest (if your
                               #   script opts in via Write-Summary)
```

Both JSON files include the canonical identity block at the top:

```json
{
  "projectVersion": "1.1.1",
  "invokedFrom":    "run.ps1",
  "gitSha":         "d9d3ee90c118",
  "gitShaFull":     "d9d3ee90c118b0af7a4e06b9bec72bdef32333b9",
  "gitBranch":      "main",
  "gitDirty":       false,
  "gitRemote":      "https://github.com/.../scripts-fixer-v16.git",
  "scriptName":     "os-clean",
  "overallStatus":  "partial",
  "startTime":      "2026-05-07T12:52:45.4351913+08:00",
  "endTime":        "2026-05-07T12:53:11.1641024+08:00",
  "duration":       25.73,
  "errorCount":     1,
  "warnCount":      0,
  "errors":         [ ... ],
  "warnings":       [ ... ]
}
```

If `errorCount > 0` and the `-error.json` sidecar is missing, the run is
**non-conformant**. The most common cause is forgetting to call
`Save-LogFile` on the failure path.

---

## 11. Checklist (pin this above your editor)

Before you commit a new script, verify every box:

- [ ] `Set-StrictMode -Version Latest` at the top.
- [ ] Dot-sources `scripts/shared/logging.ps1`.
- [ ] Calls `Initialize-Logging -ScriptName "..."` exactly once.
- [ ] All user-visible strings come from `log-messages.json`.
- [ ] Every file/path failure goes through `Write-FileError` with
      `-FilePath`, `-Operation`, `-Reason`, optional `-Fallback`.
- [ ] Every pipeline assignment is wrapped in `@(...)`.
- [ ] No `$env:VAR` reads for variables that may be unset.
- [ ] No `\$VAR` inside double-quoted strings.
- [ ] Multi-step loops collect per-step failures into a ledger and append
      the ledger to `$result.Notes` (or print it before exit).
- [ ] Every exit path calls `Save-LogFile -Status <...>`.
- [ ] `.logs/<NN>/<script>-error.json` is produced whenever
      `overallStatus != "ok"`.
- [ ] Console output uses ASCII status glyphs (`[ OK ]`, `[FAIL]`, ...).
- [ ] If destructive: gated by `Confirm-DestructiveAction` from
      `scripts/shared/confirm-prompt.ps1` with `--yes / --non-interactive`
      contract honored.

If any box is unchecked, the script is **not ready for review**.
