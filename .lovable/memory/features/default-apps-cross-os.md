---
name: default-apps-cross-os
description: os browser and os email subcommands set the default web browser / mailto handler across Windows, Linux, and macOS using the platform-native mechanism
type: feature
---

# `os browser` / `os email` -- cross-OS default-app setters

Two sibling subcommands, identical surface, different payload:

- `os browser <name>` -- set default web browser
- `os email   <name>` -- set default mail (`mailto:`) client

## Per-OS strategy (all CODE RED on missing paths)

| OS | Browser | Mail | Constraint |
|----|---------|------|------------|
| Windows 10/11 | `Start-Process ms-settings:defaultapps?registeredAppUser=<AppName>` then verify `HKCU\...\UrlAssociations\http\UserChoice\ProgId` | same deeplink + verify `mailto\UserChoice\ProgId` (also writes legacy `HKCU\Software\Clients\Mail` as best-effort) | `UserChoice` is hash-signed; programmatic registry writes are silently rejected, so the user MUST click "Set default" in the Settings dialog. Helper waits up to 60s and re-reads the key to verify. |
| Linux | `xdg-settings set default-web-browser <desktop>` | `xdg-mime default <desktop> x-scheme-handler/mailto` | Requires `xdg-utils`. `.desktop` candidates probed under standard XDG dirs + snap + flatpak. |
| macOS | `duti -s <bundle> http && duti -s <bundle> https` | `duti -s <bundle> mailto` | Without `duti` (recommended: `brew install duti`), helper opens the relevant System Settings pane and prints clear next-step instructions. |

## File map

- `scripts/os/helpers/_default-apps-catalog.ps1` -- shared Windows catalog (alias list, install probes, ProgId, AppName, Choco package)
- `scripts/os/helpers/browser.ps1` -- Windows browser helper
- `scripts/os/helpers/email.ps1` -- Windows email helper
- `scripts-linux/_shared/default-apps.sh` -- shared bash library (Linux + macOS), exports `set_default_browser`, `set_default_email`, `list_default_apps`
- `scripts-linux/default-apps/run.sh` -- thin entry point invoked by root `run.sh`
- Dispatcher wiring: `scripts/os/run.ps1` (cases `browser` / `email`), `scripts-linux/run.sh` (cases `browser` / `email` → `defapp-passthrough`)

## CLI shape (identical on all OSes)

```
<browser|email> <name>          # do it
<browser|email> --list          # print catalog of supported names + aliases
<browser|email> <name> --dry-run  # detect + plan only, no changes
<browser|email> <name> --yes    # skip the 60s wait/verify loop (Windows CI)
```

## Exit codes

- `0` ok / already set
- `2` missing or unknown name
- `3` app not installed (probe paths logged with reasons)
- `4` underlying tool missing (xdg-utils / duti / Settings deeplink failed)
- `5` change not verified within timeout (Windows: user did not click "Set default")
- `6` unsupported OS

## Catalog summary

- **Browsers**: chrome, firefox, edge, brave, opera, vivaldi, librewolf (+ chromium / safari on POSIX)
- **Mail clients**: outlook, outlook-new, thunderbird, mailbird, em-client, windows-mail (+ evolution, geary, kmail, mailspring, claws, mutt, apple-mail, outlook-mac, spark, airmail on POSIX)
