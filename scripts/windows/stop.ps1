# Windows: runs scripts/debian/stop.sh inside WSL2 Ubuntu (installs WSL/Ubuntu if missing).
# Extra arguments are passed through, e.g.  .\stop.ps1 --dry-run
. "$PSScriptRoot\_wsl.ps1"
Invoke-Debian -Script "stop.sh" -ScriptArgs $args
