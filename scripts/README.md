# Deployment scripts

One folder per OS, all calling the shared logic in `common/`:

| | macOS | Debian / Ubuntu / Raspberry Pi OS | Windows |
|---|---|---|---|
| folder | `macos/` | `debian/` (arm64 or amd64 is detected) | `windows/*.ps1` (runs `debian/` inside WSL2 Ubuntu) |

```
setup.sh         install dependencies, git pull the merged repo + submodules,
                 create ~/.rysteria-secrets/ with .env templates
build.sh         build every server + both clients into builds/<os>-<arch>/<name>/
run.sh           start master, game servers, gardn, edge; cloudflared if enabled
stop.sh          stop them (players and saves are flushed first)
clean-builds.sh  delete builds/ (only that) so the next build starts clean
up.sh            setup + build + run
```
Every script takes `--dry-run` (print, don't do). `bootstrap.sh` / `windows\bootstrap.ps1`
start from an empty machine.

## Secrets: `~/.rysteria-secrets/` (override with `SECRETS_DIR`)

Outside the checkout and outside `builds/`, mode 700/600, never overwritten:

* `common.env` – `CLOUDFLARED_ENABLED`, tunnel name + credentials, domain, the URLs
  baked into the clients.
* `master.env` – the single source of truth (database, secrets, Discord keys).
* `<server>.env` – values for one server only (`rrolf-default.env`, `rrolf-hc.env`,
  `rrolf-garden.env`, `gardn.env`, `edge.env`).

`build.sh` writes `builds/<os>-<arch>/<name>/.env` for each server: the master gets
`master.env`; game servers and gardn get **only** the shared `SERVER_SECRET`, the
master address and their own file – never database credentials, token secrets or
Discord keys.

## Servers

Edit `common/servers.conf` to add or remove processes (name, kind, biome, port,
public hostname). `edge` serves the rrolf client at `/` and gardn under `/gardn/`
on one hostname; with cloudflared enabled, `run.sh` generates the tunnel ingress
from the same file.
