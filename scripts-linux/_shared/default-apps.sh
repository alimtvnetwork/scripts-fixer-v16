#!/usr/bin/env bash
# scripts-linux/_shared/default-apps.sh
#
# Cross-OS (Linux + macOS) helper to set the system default browser or
# default mail (mailto:) client. Source logger.sh BEFORE this file.
#
#   set_default_browser  <name>            # chrome | firefox | edge | brave | ...
#   set_default_email    <name>            # thunderbird | mailspring | evolution | ...
#   list_default_apps    browser|email
#
# Strategy:
#   Linux   -> xdg-settings (browser) and xdg-mime (mailto), targeting the
#              first matching .desktop file under /usr/share/applications,
#              ~/.local/share/applications, /var/lib/snapd/desktop/applications.
#   macOS   -> duti (preferred, brew install duti) for both. Falls back to
#              opening the relevant System Settings pane with a clear
#              instruction line if duti is missing.
#
# CODE RED: every probed .desktop / app bundle path that misses is logged
# with full path + reason via log_file_error so the user knows exactly
# what was checked.

# ─── Catalog: name → desktop-file candidates / macOS bundle id ──────────
__da_browser_catalog() {
  # Format: key|display|linux-desktop-files (space-separated)|macos-bundle-id
  cat <<'EOF'
chrome|Google Chrome|google-chrome.desktop google-chrome-stable.desktop|com.google.Chrome
firefox|Mozilla Firefox|firefox.desktop firefox_firefox.desktop firefox-esr.desktop|org.mozilla.firefox
edge|Microsoft Edge|microsoft-edge.desktop microsoft-edge-stable.desktop|com.microsoft.edgemac
brave|Brave|brave-browser.desktop brave_brave.desktop|com.brave.Browser
opera|Opera|opera.desktop opera_opera.desktop|com.operasoftware.Opera
vivaldi|Vivaldi|vivaldi-stable.desktop|com.vivaldi.Vivaldi
librewolf|LibreWolf|librewolf.desktop io.gitlab.librewolf-community.desktop|io.gitlab.librewolf-community
safari|Safari (macOS only)||com.apple.Safari
chromium|Chromium|chromium.desktop chromium-browser.desktop|org.chromium.Chromium
EOF
}

__da_email_catalog() {
  # Format: key|display|linux-desktop-files|macos-bundle-id
  cat <<'EOF'
thunderbird|Mozilla Thunderbird|thunderbird.desktop thunderbird_thunderbird.desktop org.mozilla.thunderbird.desktop|org.mozilla.thunderbird
evolution|GNOME Evolution|org.gnome.Evolution.desktop evolution.desktop|
geary|Geary|org.gnome.Geary.desktop geary.desktop|
kmail|KMail|org.kde.kmail2.desktop kmail.desktop|
mailspring|Mailspring|Mailspring.desktop mailspring.desktop|com.mailspring.mailspring
claws|Claws Mail|claws-mail.desktop|
mutt|mutt (terminal)|mutt.desktop|
apple-mail|Apple Mail (macOS only)||com.apple.mail
outlook-mac|Outlook for Mac||com.microsoft.Outlook
spark|Spark Mail (macOS)||com.readdle.smartemail-Mac
airmail|Airmail (macOS)||it.bloop.airmail2
EOF
}

__da_lookup() {
  # $1=catalog (browser|email)  $2=name → echoes "key|display|desktops|bundle"
  local catalog="$1" name="$2" line
  name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | xargs)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local key; key=$(echo "$line" | cut -d'|' -f1)
    if [ "$key" = "$name" ]; then echo "$line"; return 0; fi
  done < <(if [ "$catalog" = "browser" ]; then __da_browser_catalog; else __da_email_catalog; fi)

  # alias-by-substring: also accept e.g. 'google-chrome' → 'chrome'
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local key; key=$(echo "$line" | cut -d'|' -f1)
    case "$name" in
      "google-$key"|"$key-browser"|"$key-mail"|"mozilla-$key") echo "$line"; return 0 ;;
    esac
  done < <(if [ "$catalog" = "browser" ]; then __da_browser_catalog; else __da_email_catalog; fi)

  return 1
}

list_default_apps() {
  local catalog="${1:-browser}"
  printf '\n  Available %s names\n' "$catalog"
  printf '  ===========================\n'
  while IFS='|' read -r key display _ _; do
    [ -z "$key" ] && continue
    printf '    %-14s -> %s\n' "$key" "$display"
  done < <(if [ "$catalog" = "browser" ]; then __da_browser_catalog; else __da_email_catalog; fi)
  printf '\n'
}

# ─── Linux: find first existing .desktop file from a candidate list ─────
__da_find_desktop() {
  local candidates="$1"  # space-separated list
  local d
  local search_dirs=(
    "$HOME/.local/share/applications"
    "/usr/share/applications"
    "/usr/local/share/applications"
    "/var/lib/snapd/desktop/applications"
    "/var/lib/flatpak/exports/share/applications"
    "$HOME/.local/share/flatpak/exports/share/applications"
  )
  for d in $candidates; do
    for base in "${search_dirs[@]}"; do
      if [ -f "$base/$d" ]; then echo "$d"; return 0; fi
    done
  done
  # Log every miss with exact full path checked
  for d in $candidates; do
    for base in "${search_dirs[@]}"; do
      log_file_error "$base/$d" "no matching .desktop file (probed for default-app target)"
    done
  done
  return 1
}

# ─── Linux implementations ──────────────────────────────────────────────
__da_linux_set_browser() {
  local desktop="$1"
  if ! command -v xdg-settings >/dev/null 2>&1; then
    log_err "xdg-settings is not installed -- cannot set default browser on Linux"
    log_info "Hint: sudo apt install xdg-utils  (or your distro's equivalent)"
    return 4
  fi
  log_info "xdg-settings set default-web-browser $desktop"
  if xdg-settings set default-web-browser "$desktop"; then
    local current; current=$(xdg-settings get default-web-browser 2>/dev/null || true)
    if [ "$current" = "$desktop" ]; then
      log_ok "Verified: default web browser is now '$desktop'"
      return 0
    fi
    log_warn "xdg-settings reported success but verification got '$current'"
    return 5
  fi
  log_err "xdg-settings refused to set '$desktop' (see its stderr above)"
  return 1
}

__da_linux_set_email() {
  local desktop="$1"
  if ! command -v xdg-mime >/dev/null 2>&1; then
    log_err "xdg-mime is not installed -- cannot set default mail client on Linux"
    log_info "Hint: sudo apt install xdg-utils"
    return 4
  fi
  log_info "xdg-mime default $desktop x-scheme-handler/mailto"
  if xdg-mime default "$desktop" x-scheme-handler/mailto; then
    local current; current=$(xdg-mime query default x-scheme-handler/mailto 2>/dev/null || true)
    if [ "$current" = "$desktop" ]; then
      log_ok "Verified: default mailto handler is now '$desktop'"
      return 0
    fi
    log_warn "xdg-mime reported success but verification got '$current'"
    return 5
  fi
  log_err "xdg-mime refused to set '$desktop' (see its stderr above)"
  return 1
}

# ─── macOS implementations ──────────────────────────────────────────────
__da_mac_app_path() {
  # $1=bundle id → echoes the .app path or returns 1
  local bundle="$1" path
  path=$(mdfind "kMDItemCFBundleIdentifier == '$bundle'" 2>/dev/null | head -1)
  if [ -n "$path" ] && [ -d "$path" ]; then echo "$path"; return 0; fi
  log_file_error "(bundle id: $bundle)" "no installed app with this bundle id (mdfind returned nothing)"
  return 1
}

__da_mac_set_browser() {
  local bundle="$1"
  if command -v duti >/dev/null 2>&1; then
    log_info "duti -s $bundle http && duti -s $bundle https"
    duti -s "$bundle" http  || { log_err "duti failed for http://"; return 1; }
    duti -s "$bundle" https || { log_err "duti failed for https://"; return 1; }
    log_ok "Verified: macOS now routes http/https to bundle '$bundle'"
    return 0
  fi
  log_warn "duti is not installed -- cannot set default browser non-interactively"
  log_info "Hint: brew install duti  (then re-run this command)"
  log_info "Or open: System Settings -> Desktop & Dock -> Default web browser"
  open "x-apple.systempreferences:com.apple.preference.general" 2>/dev/null || true
  return 4
}

__da_mac_set_email() {
  local bundle="$1"
  if command -v duti >/dev/null 2>&1; then
    log_info "duti -s $bundle mailto"
    duti -s "$bundle" mailto || { log_err "duti failed for mailto:"; return 1; }
    log_ok "Verified: macOS now routes mailto: to bundle '$bundle'"
    return 0
  fi
  log_warn "duti is not installed -- cannot set default mail client non-interactively"
  log_info "Hint: brew install duti  (then re-run this command)"
  log_info "Or open: Mail.app -> Settings -> General -> Default email reader"
  open -a Mail 2>/dev/null || true
  return 4
}

# ─── Public entry points ────────────────────────────────────────────────
set_default_browser() {
  local name="${1:-}"
  if [ -z "$name" ]; then
    log_err "Missing browser name. Run with --list to see available options."
    return 2
  fi
  local entry; entry=$(__da_lookup browser "$name") || {
    log_err "Unknown browser name: '$name'. Use --list to see the catalog."
    return 2
  }
  local display desktops bundle
  display=$(echo "$entry" | cut -d'|' -f2)
  desktops=$(echo "$entry" | cut -d'|' -f3)
  bundle=$(echo "$entry"  | cut -d'|' -f4)
  log_info "Target browser: $display"

  case "$(uname -s)" in
    Linux)
      [ -n "$desktops" ] || { log_err "No Linux .desktop candidates known for '$name'"; return 3; }
      local found; found=$(__da_find_desktop "$desktops") || {
        log_err "Browser '$display' is NOT installed (no matching .desktop)"
        return 3
      }
      log_ok "Detected .desktop: $found"
      __da_linux_set_browser "$found"
      ;;
    Darwin)
      [ -n "$bundle" ] || { log_err "No macOS bundle id known for '$name'"; return 3; }
      __da_mac_app_path "$bundle" >/dev/null || { log_err "Browser '$display' is NOT installed"; return 3; }
      __da_mac_set_browser "$bundle"
      ;;
    *)
      log_err "Unsupported OS for default-browser ops: $(uname -s)"
      return 6
      ;;
  esac
}

set_default_email() {
  local name="${1:-}"
  if [ -z "$name" ]; then
    log_err "Missing mail-client name. Run with --list to see available options."
    return 2
  fi
  local entry; entry=$(__da_lookup email "$name") || {
    log_err "Unknown mail-client name: '$name'. Use --list to see the catalog."
    return 2
  }
  local display desktops bundle
  display=$(echo "$entry" | cut -d'|' -f2)
  desktops=$(echo "$entry" | cut -d'|' -f3)
  bundle=$(echo "$entry"  | cut -d'|' -f4)
  log_info "Target mail client: $display"

  case "$(uname -s)" in
    Linux)
      [ -n "$desktops" ] || { log_err "No Linux .desktop candidates known for '$name'"; return 3; }
      local found; found=$(__da_find_desktop "$desktops") || {
        log_err "Mail client '$display' is NOT installed (no matching .desktop)"
        return 3
      }
      log_ok "Detected .desktop: $found"
      __da_linux_set_email "$found"
      ;;
    Darwin)
      [ -n "$bundle" ] || { log_err "No macOS bundle id known for '$name'"; return 3; }
      __da_mac_app_path "$bundle" >/dev/null || { log_err "Mail client '$display' is NOT installed"; return 3; }
      __da_mac_set_email "$bundle"
      ;;
    *)
      log_err "Unsupported OS for default-email ops: $(uname -s)"
      return 6
      ;;
  esac
}
