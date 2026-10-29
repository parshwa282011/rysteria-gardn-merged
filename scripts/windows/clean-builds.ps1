# Windows: runs scripts/debian/clean-builds.sh inside WSL2 Ubuntu (installs WSL/Ubuntu if missing).
# Extra arguments are passed through, e.g.  .\clean-builds.ps1 --dry-run
. "$PSScriptRoot\_wsl.ps1"
Invoke-Debian -Script "clean-builds.sh" -ScriptArgs $args
