# Windows: runs scripts/debian/sync.sh inside WSL2 Ubuntu (installs WSL/Ubuntu if missing).
# Extra arguments are passed through, e.g.  .\sync.ps1 status
. "$PSScriptRoot\_wsl.ps1"
Invoke-Debian -Script "sync.sh" -ScriptArgs $args
