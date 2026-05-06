---
name: Default dev directory naming
description: Default dev directory is always "dev-tool" (hyphenated) everywhere -- code, docs, help text, specs, memory
type: preference
---
The default dev directory folder name is **`dev-tool`** (hyphenated, singular).

**Never** use `devtool`, `devtools`, `dev_tool`, or `dev-tools` in:
- Help text / log messages (e.g. `D:\dev-tool`, not `D:\devtools`)
- Spec docs and readmes
- Sample paths in code comments
- Default fallbacks in `scripts/shared/dev-dir.ps1`

Canonical examples:
- Windows: `D:\dev-tool`, `C:\dev-tool`, `F:\dev-tool`
- Unix: `~/dev-tool`, `/opt/dev-tool`

Exception: the literal string "DevTools" (CamelCase, referring to browser
developer tools) is unrelated and may stay as-is.
