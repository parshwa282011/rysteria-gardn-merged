# Windows: runs scripts/debian/mail.sh inside WSL2 Ubuntu (setup, start, stop, dns, status).
# Extra arguments are passed through, e.g.  .\mail.ps1 setup
. "$PSScriptRoot\_wsl.ps1"
Invoke-Debian -Script "mail.sh" -ScriptArgs $args
