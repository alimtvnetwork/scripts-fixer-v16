#!/usr/bin/env bash
# scripts-linux/default-apps/run.sh
#
# Thin entry point invoked by root run.sh as:
#   ./run.sh browser <name> [--list] [--dry-run]
#   ./run.sh email   <name> [--list] [--dry-run]
#
# Loads logger + default-apps.sh from _shared, then calls the right
# function. --list prints the catalog and exits. --dry-run prints what
# would happen and exits 0.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
. "$ROOT_DIR/_shared/logger.sh"
# shellcheck disable=SC1091
. "$ROOT_DIR/_shared/file-error.sh"
# shellcheck disable=SC1091
. "$ROOT_DIR/_shared/default-apps.sh"

KIND="${1:-}"; shift || true
if [ -z "$KIND" ] || { [ "$KIND" != "browser" ] && [ "$KIND" != "email" ]; }; then
  log_err "Usage: run.sh browser|email <name> [--list] [--dry-run]"
  exit 2
fi

NAME=""; LIST=0; DRYRUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --list)    LIST=1; shift ;;
    --dry-run) DRYRUN=1; shift ;;
    --yes)     shift ;;       # accepted for parity with Windows side
    -h|--help)
      printf '\nUsage: run.sh %s <name> [--list] [--dry-run]\n' "$KIND"
      list_default_apps "$KIND"
      exit 0
      ;;
    -*)        log_warn "Ignoring unknown flag: $1"; shift ;;
    *)         [ -z "$NAME" ] && NAME="$1" || log_warn "Extra positional ignored: $1"; shift ;;
  esac
done

if [ "$LIST" -eq 1 ]; then
  list_default_apps "$KIND"
  exit 0
fi

if [ -z "$NAME" ]; then
  log_err "Missing $KIND name. Run: ./run.sh $KIND --list"
  exit 2
fi

if [ "$DRYRUN" -eq 1 ]; then
  log_info "DRY-RUN: would set default $KIND to '$NAME' on $(uname -s)"
  log_info "DRY-RUN: no xdg-settings/xdg-mime/duti calls were made."
  exit 0
fi

case "$KIND" in
  browser) set_default_browser "$NAME" ;;
  email)   set_default_email   "$NAME" ;;
esac
