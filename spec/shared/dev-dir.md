# Spec: dev-dir.ps1

## Overview

Shared module for resolving and initializing the dev directory. Uses **smart
drive detection** to automatically pick the best available drive based on
existence and free space, removing the need for hardcoded drive letters.

**File:** `scripts/shared/dev-dir.ps1`
**Smart detection added in:** v0.5.0

---

## Smart Drive Selection

### Priority Order

| Priority | Candidate | Condition |
|----------|-----------|-----------|
| 1 | `E:\dev-tool` | E: drive exists and has >= 10 GB free |
| 2 | `D:\dev-tool` | D: drive exists and has >= 10 GB free |
| 3 | Best other drive | Any non-system fixed drive (DriveType=3), most free space wins, >= 10 GB |
| 4 | User prompt | Shows all available drives with free space; user types a path |
| 5 | System drive fallback | `C:\dev-tool` (last resort if user provides no input) |

### Minimum Free Space

The threshold is defined as `$script:MinFreeSpaceGB = 10` (10 GB). A drive
must have at least this much free space to qualify. This ensures enough room
for database installs, tools, and project data.

### Config Mode

All `config.json` files use:

```json
{
  "devDir": {
    "mode": "smart",
    "default": "auto",
    "override": ""
  }
}
```

| Field | Description |
|-------|-------------|
| `mode` | `"smart"` triggers auto-detection. Legacy `"json-or-prompt"` also triggers smart mode for backwards compatibility |
| `default` | `"auto"` means use smart detection. Any explicit path (e.g. `"F:\\dev-tool"`) uses that path directly |
| `override` | If non-empty, this path is used unconditionally (bypasses smart detection) |

---

## Functions

### Get-SavedDevPath / Set-SavedDevPath / Remove-SavedDevPath

Manage the persistent dev directory override stored in `scripts/dev-path.json`.

| Function | Description |
|----------|-------------|
| `Get-SavedDevPath` | Returns the saved path string, or `$null` if no file or empty |
| `Set-SavedDevPath -Path <dir>` | Writes `{"path": "<dir>"}` to `scripts/dev-path.json` |
| `Remove-SavedDevPath` | Deletes `scripts/dev-path.json` |

Set via `.\run.ps1 path D:\dev-tool`. Read automatically by `Resolve-DevDir`.

---

### Test-DriveQualified

Checks whether a single drive letter exists and meets the minimum free space
requirement.

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-DriveLetter` | string | Yes | Single drive letter without colon (e.g. `"E"`) |

#### Returns

`$true` if the drive exists and has >= 10 GB free, `$false` otherwise.

#### Implementation

1. Check drive existence via `Get-PSDrive`
2. Query free space via `Get-CimInstance Win32_LogicalDisk` (WMI)
3. Fall back to `PSDrive.Free` if WMI fails
4. Compare against `$script:MinFreeSpaceGB`

---

### Find-BestDevDrive

Selects the best drive for the dev directory by checking candidates in
priority order.

#### Parameters

None.

#### Returns

A drive letter string (e.g. `"E"`) or `$null` if no drive qualifies.

#### Execution Flow

1. Test E: drive via `Test-DriveQualified` -- return `"E"` if qualified
2. Test D: drive via `Test-DriveQualified` -- return `"D"` if qualified
3. Query all fixed disks (`Win32_LogicalDisk`, `DriveType=3`)
4. Exclude system drive (`$env:SystemDrive`) and already-checked E:/D:
5. Filter by minimum free space
6. Sort remaining candidates by free space descending
7. Return the letter with the most free space, or `$null` if none qualify

---

### Resolve-SmartDevDir

Orchestrates smart drive detection with an interactive user prompt fallback.

#### Parameters

None.

#### Returns

A dev directory path string (e.g. `"E:\dev-tool"`, `"D:\dev-tool"`, or user-provided).

#### Execution Flow

1. Call `Find-BestDevDrive`
2. If a drive is found: return `"<letter>:\dev-tool"`
3. If no drive qualifies:
   - Display warning with threshold
   - List all fixed drives with their free space
   - Prompt user: `"Enter dev directory path (e.g. C:\dev, F:\dev)"`
   - If user provides input: return that path
   - If user presses Enter with no input: return `Get-SafeDevDirFallback` (system drive `\dev`)

---

### Resolve-DevDir

Main entry point for dev directory resolution. Called by every script's
`run.ps1`.

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-DevDirConfig` / `-Config` | PSCustomObject | No | The `devDir` block from `config.json` |

#### Returns

A validated dev directory path string.

#### Resolution Priority

1. **`$env:DEV_DIR`** -- Set by the orchestrator; if present, used directly
   (validated via `Resolve-UsableDevDir`)
2. **Saved path** -- From `scripts/dev-path.json` (set via `.\run.ps1 path <dir>`)
3. **Config override** -- `devDir.override` in `config.json`; if non-empty,
   used directly
4. **Smart detection** -- If mode is `"smart"` or `"json-or-prompt"`,
   calls `Resolve-SmartDevDir`
5. **Config default** -- Legacy fallback to `devDir.default` value
6. **System drive** -- `C:\dev-tool` as absolute last resort

---

### Resolve-UsableDevDir

Validates and normalizes a dev directory path. Expands environment variables,
resolves to a full path, and checks that the target drive exists.

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-PathValue` | string | No | The path to validate |

#### Returns

The validated full path, or the safe fallback (`C:\dev`) if validation fails.

#### Validation Steps

1. Empty/null path: return fallback
2. Expand environment variables (e.g. `%USERPROFILE%`)
3. Resolve to full path via `[System.IO.Path]::GetFullPath()`
4. If drive-qualified (`X:\...`): verify drive exists via `Get-PSDrive`
5. If drive missing: return fallback

---

### Get-SafeDevDirFallback

Returns `<SystemDrive>\dev` (typically `C:\dev`). Used as the absolute last
resort when all other resolution methods fail.

---

### Initialize-DevDir

Creates the dev directory and optional subdirectories on disk.

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-DevDir` / `-Path` | string | Yes | The dev directory path to create |
| `-Subdirectories` | string[] | No | Additional subdirectories to create inside the dev dir |

#### Returns

The final dev directory path (may differ from input if fallback was used).

#### Behaviour

1. Validate path via `Resolve-UsableDevDir`
2. Create directory if missing (`New-Item -ItemType Directory`)
3. On failure: fall back to system drive `\dev` (unless already there, then throw)
4. Create each subdirectory if missing

---

## Edge Cases

| Condition | Behaviour |
|-----------|-----------|
| E: drive exists but has < 10 GB free | Skipped with `driveLowSpace` warning; tries D: next |
| No E: or D: drive on the system | Scans all other fixed drives |
| Only the system drive exists | Prompts user; falls back to `C:\dev` |
| `$env:DEV_DIR` is set | Used directly, bypasses all detection |
| Config override is set | Used directly, bypasses smart detection |
| User enters empty string at prompt | Falls back to `C:\dev` |
| Drive exists but WMI query fails | Falls back to `PSDrive.Free` for space check |
| Path contains environment variables | Expanded via `[System.Environment]::ExpandEnvironmentVariables()` |
| Path points to non-existent drive | Falls back to `C:\dev` with warning |

---

## Log Messages

Drive detection messages in `scripts/shared/log-messages.json`:

| Key | Level | Message |
|-----|-------|---------|
| `driveAutoDetecting` | info | Auto-detecting best drive for dev directory (E: > D: > best available)... |
| `driveNotFound` | info | Drive {drive} not found -- skipping |
| `driveLowSpace` | warn | Drive {drive} has only {free} GB free (minimum {min} GB required) -- skipping |
| `driveQualified` | info | Drive {drive} qualified: {free} GB free |
| `drivePreferred` | success | Selected preferred drive: {drive} |
| `driveScanningOthers` | info | E: and D: not available -- scanning other fixed drives... |
| `driveAutoSelected` | success | Auto-selected drive {drive} ({free} GB free) |
| `driveNoneQualified` | warn | No drive with enough free space found -- will prompt user |

---

## Usage

Called automatically by every `run.ps1`:

```powershell
. (Join-Path $sharedDir "dev-dir.ps1")

$devDir = Resolve-DevDir -Config $config.devDir
Initialize-DevDir -Path $devDir
$env:DEV_DIR = $devDir
```

The orchestrator (`scripts/12-install-all-dev-tools`) sets `$env:DEV_DIR`
once, so child scripts skip detection and reuse the same directory.

---

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| E: preferred over D: | User preference -- E: is typically a secondary data drive |
| 10 GB minimum threshold | Enough for multiple database installs + projects without risking disk-full errors |
| WMI over PSDrive for space | `Win32_LogicalDisk` reports accurate free space for all fixed disk types |
| Non-system drive preference | Keep dev tools separate from the OS drive to avoid clutter and improve backup strategy |
| Auto-pick then prompt | Reduces friction for most users (auto works) while handling edge cases (prompt) |
| `$env:DEV_DIR` takes top priority | Allows orchestrator to lock the path for all child scripts in a single run |
| Legacy `json-or-prompt` mode triggers smart | Backwards compatible -- existing configs work without changes |
