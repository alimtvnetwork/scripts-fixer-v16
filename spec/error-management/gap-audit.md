# Gap Audit — PowerShell Error Management

> **Reference spec:** `spec/error-management/powershell-error-management.md`
> **Audit date:** 2026-05-07
> **Scope:** every `.ps1` under `scripts/`, with focus on
> `scripts/os/helpers/clean-categories/*.ps1` (newest, fastest-changing area).
>
> **Question being answered:** *Can a low-context / "blind" AI implement the
> error-management contract from the spec alone, without reading existing
> scripts?*

---

## 1. Headline score

| Dimension                                                          | Score (0-10) |
|--------------------------------------------------------------------|--------------|
| Spec self-containment (can be followed without reading code)       |  9           |
| Spec correctness (matches what the logger actually does)           |  9           |
| Spec coverage (every contract surface is documented)               |  8           |
| **Codebase conformance** to the spec                               |  6           |
| Determinism (same input -> same JSON shape across all scripts)     |  7           |
| Discoverability (helpers are easy to find from the spec)           |  8           |
| **Overall — "blind-AI implementability"**                          |  **7.5 / 10** |

A new author following only `powershell-error-management.md` will produce
a script that **logs correctly**, **survives StrictMode**, and **emits a
conformant sidecar**. They will, however, write *better* CODE RED logs
than ~85 % of the existing `clean-categories/*.ps1` helpers. The spec is
ahead of the code, not behind it.

---

## 2. What the spec gets right (no action needed)

1. **Mandatory envelope** (`Set-StrictMode`, dot-source logger,
   `Initialize-Logging`, `try / Save-LogFile / exit`) is unambiguous and
   matches `scripts/shared/logging.ps1` exactly.
2. **`Write-FileError` signature** matches the function defined in
   `logging.ps1` lines 272–332, including the `Operation` allow-list.
3. **JSON shape** (identity block + `errors[]` / `warnings[]`) matches
   actual sidecar output observed in the user's recent `os-clean` run.
4. **StrictMode survival kit** captures every real crash we hit in the
   last week (`@(...)` wrapping, `$env:VAR`, `\$VAR` expansion).
5. **Decision tree** in §11 is the missing piece every new author asks for.

---

## 3. Conformance audit — `scripts/os/helpers/clean-categories/`

Numbers measured by `grep` over the 60 non-underscore category helpers
(`_sweep.ps1`, `_*.ps1` excluded):

| Metric                                                             | Count        |
|--------------------------------------------------------------------|--------------|
| Total category helpers                                             | 60           |
| Helpers calling **`Write-FileError`** at least once                | **0**        |
| Helpers calling `Write-Log -Level "fail"` / `"error"`              | 8            |
| Helpers with a `try / catch` around the destructive sweep          | ~12          |
| Helpers wrapping pipeline output in `@(...)` (post-hardening)      | 8 / 8 done   |
| Helpers using `[Environment]::GetEnvironmentVariable` for env vars | ~6 (rest read via `_sweep.ps1` accessors) |

### Gap G-1 — CODE RED is documented but not adopted (severity: HIGH)

**Finding.** Zero of the 60 clean-category helpers call `Write-FileError`.
The 8 that report failures use `Write-Log "... FAIL path=$x reason=$y" -Level "fail"`,
which produces a **string** in `errors[]` but no `type:"file-error"`,
no `filePath`, no `operation`, no `module`. CI dashboards that filter on
`type == "file-error"` will see zero file errors from `os-clean`.

**Example of non-conformant code** (`wu-download.ps1` line 27):
```powershell
Write-Log "wu-download FAIL path=$windir reason=$msg" -Level "fail"
```

**Required fix** (per spec §4):
```powershell
Write-FileError `
    -FilePath  $windir `
    -Operation "resolve" `
    -Reason    $msg `
    -Module    "wu-download.ps1"
```

**Impact on blind-AI question.** A new author reading the spec WILL write
the correct pattern. A new author copying an existing `clean-categories/*.ps1`
file WILL inherit the wrong pattern. **Fix the existing files**, then the
spec and the codebase agree.

### Gap G-2 — `_sweep.ps1` swallows file errors silently (severity: HIGH)

`Invoke-PathSweep` (the workhorse used by ~45 categories) currently
catches per-file delete failures and increments `$result.Locked` /
`$result.LockedDetails` without ever calling `Write-FileError`. The
locked-file table is great for humans but invisible to JSON consumers.

**Required fix.** Inside the catch-block of `Invoke-PathSweep`, in
addition to the existing `LockedDetails.Add(...)`, call:
```powershell
Write-FileError `
    -FilePath  $item.FullName `
    -Operation "delete" `
    -Reason    $_.Exception.Message `
    -Fallback  "left in place; counted toward Locked"
```
This is the **single highest-leverage change** in the audit — fixing
`_sweep.ps1` retroactively makes ~45 categories conformant.

### Gap G-3 — No `log-messages.json` for the `os` script's clean subtree (severity: MEDIUM)

`scripts/os/log-messages.json` exists and is loaded by `clean-runner.ps1`,
but the 60 category helpers hard-code their human-facing strings (the
`Label` and `Notes` lines). Spec §1 rule 1 says "no string literals in
`run.ps1` for human output". The category helpers are not `run.ps1`, so
this is a **soft** violation, but it weakens i18n/CI uniformity.

**Recommended fix.** Either (a) add a `clean-categories/log-messages.json`
keyed by category name, or (b) explicitly carve out category helpers
in spec §1 as exempt. (b) is cheaper and documents reality.

### Gap G-4 — Helpers don't call `Initialize-Logging` (correct) but the spec didn't say so (severity: LOW, fixed)

The previous spec (`readme.md`) implied every script calls
`Initialize-Logging`. Helpers must not. The new spec
(`powershell-error-management.md` §1 rule 5) now says so explicitly.

### Gap G-5 — `Write-FileError` allow-list is hard-coded (severity: LOW)

`logging.ps1` line 305 lists 30+ `Operation` verbs. Adding a new verb
requires editing `logging.ps1`. The unknown-verb branch logs a `[ WARN ]`
but still emits the CODE RED line, so this is non-blocking — but a blind
AI will not know which verbs are accepted unless they read the spec.
The spec now reproduces the full allow-list (§4).

### Gap G-6 — `-LiteralPath` discipline is inconsistent (severity: MEDIUM)

A spot-check of 10 helpers shows ~3 still use `-Path` for paths that may
contain `[`, `]`, or `*` (e.g. shadercache filenames). PowerShell
silently expands these as wildcards. Spec §6 rule 6 now mandates
`-LiteralPath`; the codebase needs a sweep.

### Gap G-7 — Top-level catch in `clean.ps1` does not stamp `type:"file-error"` (severity: MEDIUM)

`scripts/os/helpers/clean.ps1` wraps each category in `try/catch` and
records `Category 'X' threw at <file>: <message>` via `Write-Log` only.
This is the same gap as G-1 at the orchestrator level. Fix by routing
through `Write-FileError` with `-Operation "execute" -Module $categoryFile`.

---

## 4. Conformance audit — rest of the repo

Quick metrics from `grep -rl "Write-FileError" scripts/ --include=*.ps1`:

- **44** helper files repo-wide call `Write-FileError`. Coverage is good
  in `scripts/03-...` through `scripts/59-...` (install scripts), and in
  `scripts/shared/`.
- The **`scripts/os/`** tree is the laggard (1 of 7 sub-helpers, 0 of 60
  clean-categories). This is the area being actively edited and is also
  the area with the most CODE RED user reports.
- `scripts/models/`, `scripts/scan/` are conformant.

---

## 5. Spec readability — can a blind AI implement from text alone?

I re-read `powershell-error-management.md` as if I had never seen the
codebase. The following questions could ALL be answered from the spec:

- "What file do I create?" -> §1 (folder structure diagram)
- "What is the minimum entry script?" -> §2 (copy-paste envelope)
- "When do I use `Write-Log` vs `Write-FileError`?" -> §11 (decision tree)
- "What `Operation` verbs are legal?" -> §4 (allow-list)
- "What JSON fields must appear in a file-error event?" -> §4 (mandatory shape)
- "How do I avoid StrictMode crashes?" -> §6 (7 rules)
- "Where do log files go?" -> §10 (artifacts diagram)
- "How do I confirm I'm done?" -> §12 (pre-commit checklist)

The following questions are NOT directly answered and could trip a
low-context AI:

| Unanswered question                                                | Suggested fix                                       |
|--------------------------------------------------------------------|-----------------------------------------------------|
| "Can a helper call `Write-FileError` even if it doesn't `Initialize-Logging`?" | Add 1-line note in §4: "Helpers may call `Write-FileError`; the parent script's logger will receive it." |
| "What if my `Reason` string is empty?"                             | Add: "If `Reason` is empty/whitespace, use `'unknown failure'` rather than omitting the field." |
| "Does `Save-LogFile -Status fail` still write the success log?"    | Add 1 sentence in §2: yes — it always writes `<script>.json`, and additionally `<script>-error.json` when status != ok. |
| "How do I add a new `Operation` verb?"                             | Add: edit `scripts/shared/logging.ps1` `$knownOperations`, then commit both. |

These are **clarifications, not blockers** — a blind AI would still
produce a passing script; they would just produce a *better* one with
the clarifications added.

---

## 6. Action list (ordered by leverage)

| # | Action                                                                                                  | Effort  | Leverage |
|---|---------------------------------------------------------------------------------------------------------|---------|----------|
| 1 | Patch `_sweep.ps1` `Invoke-PathSweep` catch-block to call `Write-FileError`. Fixes ~45 categories at once. | 30 min  | Highest  |
| 2 | Sweep the 8 categories that emit `Write-Log -Level fail` and convert each to `Write-FileError`.         | 45 min  | High     |
| 3 | Patch `clean.ps1` orchestrator catch-block to call `Write-FileError`.                                   | 10 min  | High     |
| 4 | `-Path` -> `-LiteralPath` audit across `clean-categories/*.ps1`.                                        | 1 hour  | Medium   |
| 5 | Add the 4 spec clarifications listed in §5 of this audit.                                               | 10 min  | Medium   |
| 6 | Decide G-3 (carve-out vs. JSON catalog) and document in spec §7.                                        | 15 min  | Low      |

After actions 1–3, the repo's `os-clean` runs will produce
`type:"file-error"` events for every locked file, every failed sweep,
and every category exception — bringing the `clean-categories/` tree from
**0 % CODE RED conformance to ~95 %** in under 1.5 hours of work.

---

## 7. Verdict

- **Spec quality:** A-grade. A blind AI following only this document will
  write a conformant script.
- **Codebase conformance:** B-grade overall, D-grade specifically for
  `scripts/os/helpers/clean-categories/`. The newest area is the least
  conformant, which is the inverse of what you want.
- **Composite blind-AI implementability score: 7.5 / 10.**
  Raise to **9 / 10** by completing actions 1–3 above; raise to
  **9.5 / 10** by also completing 4–5.
