# Windows: runs scripts/debian/up.sh inside WSL2 Ubuntu (installs WSL/Ubuntu if missing).
# Extra arguments are passed through, e.g.  .\up.ps1 --dry-run
. "$PSScriptRoot\_wsl.ps1"
Invoke-Debian -Script "up.sh" -ScriptArgs $args
