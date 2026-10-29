# Shared by the other windows scripts. The servers are built and run inside WSL2
# Ubuntu (libwebsockets, libsodium, emscripten and cloudflared all behave on
# Linux); the Debian scripts do the actual work.

function Assert-Wsl {
    if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
        throw "WSL is not available. Enable it first (Windows 10 2004+ or 11): wsl --install"
    }
    $distros = (wsl -l -q 2>$null) -join "`n"
    if ($distros -notmatch "Ubuntu") {
        Write-Host "Installing Ubuntu for WSL (a restart and the Ubuntu first-run setup may be needed)..."
        wsl --install -d Ubuntu
        Write-Host "Finish the Ubuntu first-run setup, then run this script again."
        exit 1
    }
}

function Invoke-Debian {
    param([string]$Script, [string[]]$ScriptArgs = @())
    Assert-Wsl
    $repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
    $wslRepo = (wsl -d Ubuntu wslpath -a $repo).Trim()
    $line = "scripts/debian/$Script " + ($ScriptArgs -join " ")
    # building inside /mnt/c works but is slow: clone into the WSL home for speed
    wsl -d Ubuntu --cd $wslRepo -- bash -lc $line
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
