#!/usr/bin/env bash
# For a machine with nothing on it: clones the merged repository (with rrolf and
# gardn) and runs the setup script for this OS.
#
#   curl -fsSL https://raw.githubusercontent.com/parshwa282011/rysteria-gardn-merged/main/scripts/bootstrap.sh | bash
#
# Environment: INSTALL_DIR (default ~/rysteria-gardn-merged), RS_REPO_URL
set -euo pipefail

REPO_URL="${RS_REPO_URL:-https://github.com/parshwa282011/rysteria-gardn-merged.git}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/rysteria-gardn-merged}"

case "$(uname -s)" in
Darwin) os=macos ;;
Linux) os=debian ;;
*) echo "unsupported OS (Windows: use scripts/windows/bootstrap.ps1)" >&2; exit 1 ;;
esac

command -v git >/dev/null 2>&1 || {
    if [ "$os" = debian ]; then
        sudo apt-get update && sudo apt-get install -y git
    else
        echo "install git first (xcode-select --install)" >&2
        exit 1
    fi
}

if [ -d "$INSTALL_DIR/.git" ]; then
    echo "==> $INSTALL_DIR exists, using it"
else
    echo "==> cloning $REPO_URL into $INSTALL_DIR"
    git clone --recurse-submodules "$REPO_URL" "$INSTALL_DIR"
fi
exec "$INSTALL_DIR/scripts/$os/setup.sh" "$@"
