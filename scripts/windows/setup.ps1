# Windows: runs scripts/debian/setup.sh inside WSL2 Ubuntu (installs WSL/Ubuntu if missing).
# Extra arguments are passed through, e.g.  .\setup.ps1 --dry-run
. "$PSScriptRoot\_wsl.ps1"
Invoke-Debian -Script "setup.sh" -ScriptArgs $args
