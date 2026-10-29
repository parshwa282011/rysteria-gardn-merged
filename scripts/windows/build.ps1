# Windows: runs scripts/debian/build.sh inside WSL2 Ubuntu (installs WSL/Ubuntu if missing).
# Extra arguments are passed through, e.g.  .\build.ps1 --dry-run
. "$PSScriptRoot\_wsl.ps1"
Invoke-Debian -Script "build.sh" -ScriptArgs $args
