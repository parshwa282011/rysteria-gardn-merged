# Windows with nothing on it: installs WSL2 Ubuntu if needed, clones the merged
# repository INSIDE WSL (fast file system) and runs the Debian setup there.
. "$PSScriptRoot\_wsl.ps1"
Assert-Wsl
$script = @'
set -euo pipefail
dir="$HOME/rysteria-gardn-merged"
[ -d "$dir/.git" ] || { sudo apt-get update && sudo apt-get install -y git && git clone --recurse-submodules https://github.com/parshwa282011/rysteria-gardn-merged.git "$dir"; }
exec "$dir/scripts/debian/setup.sh"
'@
wsl -d Ubuntu -- bash -lc $script
