#!/usr/bin/env bash
# macOS (Homebrew): installs every build dependency, updates the checkout and
# creates ~/.rysteria-secrets/ with templates for the .env files.
# Databases are not installed: PostgreSQL / MongoDB are yours to provide (point
# POSTGRES_URI / MONGO_URI in master.env at them).
#
# Usage: scripts/macos/setup.sh [--dry-run]

source "$(dirname "${BASH_SOURCE[0]}")/../common/lib.sh"
parse_common_flags "$@"
detect_platform
[ "$RS_OS" = macos ] || die "this is the macOS script, you are on $RS_OS"

command -v brew >/dev/null 2>&1 || die "Homebrew is required: https://brew.sh"

FORMULAE="cmake pkgconf libwebsockets curl libsodium libpq mongo-c-driver node emscripten openjdk"
if [ "$(env_get "$RS_SECRETS_DIR/common.env" CLOUDFLARED_ENABLED)" = 1 ]; then
    FORMULAE="$FORMULAE cloudflared"
fi

log "Homebrew packages"
for formula in $FORMULAE; do
    if brew list --formula "$formula" >/dev/null 2>&1; then
        echo "  $formula already installed"
    else
        run brew install "$formula"
    fi
done

"$RS_COMMON_DIR/sync-repo.sh"
secrets_init
log "setup done. Next: edit $RS_SECRETS_DIR/master.env, then scripts/macos/build.sh"
