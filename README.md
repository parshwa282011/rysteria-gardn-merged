# Rysteria + Gardn: putting it on your servers

This is the full list of what you have to do, in order. Each step says what it
does and what you should see when it worked. Nothing here asks you to edit code.

## What you end up with

```
 players' browsers
      |
      |  https://game.parshwa.blog          rrolf client  +  gardn (/gardn/)
      |  https://api-game.parshwa.blog      master server (accounts, logins, saves)
      |  wss://hc-game / pvp-game / ga-game / ctf-game .parshwa.blog   rrolf game servers
      v
 Cloudflare  ----(tunnel, no open ports)---->  your machine
                                                 |
   edge :8080      master :55554     rrolf-hc :1234   rrolf-pvp :1235
   gardn :9001                       rrolf-garden :1236   rrolf-ctf :1237
                                                 |
                              database (PostgreSQL or MongoDB)
```

| Name | What it is | Port |
|---|---|---|
| `master` | the C master server: accounts, login tokens, all saved data | 55554 |
| `rrolf-hc` / `rrolf-pvp` / `rrolf-garden` / `rrolf-ctf` | the four rrolf game servers | 1234 / 1235 / 1236 / 1237 |
| `gardn` | the gardn game server | 9001 |
| `edge` | small web server: rrolf client at `/`, gardn under `/gardn/` | 8080 |

## What you need before you start

1. **A computer to run it**: a Mac, a Debian/Ubuntu/Raspberry Pi OS machine, or
   Windows with WSL2. 2 GB RAM minimum, 4 GB+ recommended (building the clients
   is the hungry part).
2. **Your domain on Cloudflare** (`parshwa.blog` in the examples) and a free
   Cloudflare account.
3. **A database**, either:
   * PostgreSQL (any recent version), or
   * MongoDB (your own, or MongoDB Atlas).
4. **Optional, for Discord login and password-reset codes**: a Discord account
   to create a Discord application.

## Step 0: check the code on your branches

The new login system needs code in three places. Run these three checks from the
folder that contains `rrolf/` and `gardn/`:

```sh
grep -q -i "x-server-secret" rrolf/Server/Server.c  && echo "rrolf server: OK" || echo "rrolf server: MISSING"
grep -q "rr_auth_start"     rrolf/Client/Game.c     && echo "rrolf client: OK" || echo "rrolf client: MISSING"
test -f gardn/Server/Master.hh                       && echo "gardn: OK"        || echo "gardn: MISSING"
```

All three must say OK. If one says MISSING, that part is not on the branch you
are about to deploy and **logins will not work** (players would be kicked when
they try to join).

On `gardn-update` this integration is done: the game server and client use the
C master (accounts with signup/login, PL-T / PL-P tokens, saves per account).
CrazyGames linking, transfer codes and the in-game "link Discord" relay of the
old Node master are switched off for now; the Account tab has "Link Discord"
(through the master's login) and "Log out" instead.

## Step 1: get the code

On the server:

```sh
# a machine with nothing on it (installs git if needed, clones everything):
curl -fsSL https://raw.githubusercontent.com/parshwa282011/rysteria-gardn-merged/main/scripts/bootstrap.sh | bash
```
(that one-liner only works after the `scripts/` folder and this README are
committed and pushed to the repository), or, if you already cloned it:
```sh
cd rysteria-gardn-merged
git pull
git submodule update --init
```
Pick the folder for your system and use it for **every** command below:

| System | Scripts folder | Called `<os>` below |
|---|---|---|
| macOS | `scripts/macos/` | `macos` |
| Debian, Ubuntu, Raspberry Pi OS | `scripts/debian/` | `debian` |
| Windows | `scripts\windows\*.ps1` (see "Windows" at the end) | |

## Step 2: run setup (installs everything)

```sh
scripts/<os>/setup.sh
```
This installs the compilers and libraries (cmake, libwebsockets, libsodium,
Postgres and Mongo client libraries, Node.js, emscripten), pulls the latest code,
and creates your **secrets folder** (next step). You will be asked for your sudo
password on Linux. Expect 5-20 minutes the first time.

You can add `--dry-run` to any script to see what it *would* do without doing it.

Raspberry Pi tip: add `--no-emscripten` to skip the slow WebAssembly compiler
and build the browser clients on another machine.

## Step 3: fill in the env files

Setup created a folder `~/.rysteria-secrets/` (only you can read it). It lives
**outside** the project, so pulling code or deleting builds never touches it.

```
~/.rysteria-secrets/
  common.env        settings for the scripts and cloudflared
  master.env        the master server: database, secrets, Discord  <- you edit this
  rrolf-hc.env      one small file per game server (usually nothing to edit)
  rrolf-pvp.env
  rrolf-garden.env
  rrolf-ctf.env
  gardn.env
  edge.env
```

When you build, the scripts copy each file into the server's own folder as
`.env`. Game servers and gardn only get the shared password (`SERVER_SECRET`)
and the master's address, never your database login or Discord keys.

### 3a. `master.env`  (open it and change these)

| Key | What to put |
|---|---|
| `DB_TYPE` | `postgres` or `mongo` |
| `POSTGRES_URI` | if postgres, e.g. `postgresql://rysteria:PASSWORD@127.0.0.1:5432/rysteria` |
| `MONGO_URI`, `MONGO_DB_NAME` | if mongo, e.g. `mongodb+srv://user:PASSWORD@cluster.mongodb.net/` and `rysteria` |
| `ALLOWED_ORIGINS` | the page that calls the master: `https://game.parshwa.blog` (already filled) |
| `CLIENT_URL` | where Discord login sends players back: `https://game.parshwa.blog/` (already filled) |
| `DISCORD_CLIENT_ID`, `DISCORD_CLIENT_SECRET`, `DISCORD_BOT_TOKEN` | from Step 5. Leave empty to turn Discord off |
| `DISCORD_REDIRECT_URI` | `https://api-game.parshwa.blog/oauth/discord/callback` (already filled) |

Already filled in for you, do **not** change after launch: `SERVER_SECRET`,
`TOKEN_SECRET_1`, `TOKEN_SECRET_2`, `OTP_PEPPER` (random values the setup
generated). Changing `TOKEN_SECRET_*` logs every player out; losing
`SERVER_SECRET` just means rebuilding so all servers get the new one.

Passwords with special characters inside a database URI must be percent-encoded
(`@` becomes `%40`).

### 3b. `common.env`

| Key | Meaning | Default |
|---|---|---|
| `DOMAIN` | your domain | `parshwa.blog` |
| `CLOUDFLARED_ENABLED` | `1` = `run.sh` also starts the Cloudflare tunnel | `0` |
| `TUNNEL_NAME` | the name you give the tunnel in Step 6 | `rysteria` |
| `TUNNEL_CREDENTIALS` | path of the tunnel's json file from Step 6 | `~/.cloudflared/rysteria.json` |
| `MASTER_HOST`, `MASTER_PORT`, `MASTER_TLS` | where game servers find the master (same machine) | `127.0.0.1`, `55554`, `0` |
| `CLIENT_API_URL` | master address baked into the rrolf client | `https://api-game.<domain>/` |
| `GARDN_WS_URL` | gardn websocket address baked into the gardn client | `wss://game.<domain>/gardn/` |

The last two are written into the browser clients **when you build**. Change them
and you must build again.

### 3c. The per-server files

`rrolf-*.env`, `gardn.env` and `edge.env` only hold things for that one server.
The defaults are right; you normally leave them alone. The server list itself
(names, ports, hostnames) is in `scripts/common/servers.conf`; delete a line to
skip that server.

## Step 4: create the database

**PostgreSQL**
```sh
sudo -u postgres psql -c "CREATE USER rysteria WITH PASSWORD 'choose-a-password';"
sudo -u postgres psql -c "CREATE DATABASE rysteria OWNER rysteria;"
```
then put `postgresql://rysteria:choose-a-password@127.0.0.1:5432/rysteria` in
`POSTGRES_URI`. The tables are created automatically on first start.

**MongoDB / Atlas**: create a database user, allow your server's IP in Atlas
"Network Access", and use the connection string as `MONGO_URI`. Collections and
indexes are created automatically.

The same master code runs on either; switching later means a fresh database
(data is not copied between the two).

## Step 5: Discord (optional but needed for Discord login and password reset)

1. Go to <https://discord.com/developers/applications> and click **New Application**.
2. **OAuth2** page: copy the **Client ID** and **Client Secret** into `master.env`.
   Under **Redirects** add exactly `https://api-game.parshwa.blog/oauth/discord/callback`.
3. **Bot** page: click **Reset Token**, copy it to `DISCORD_BOT_TOKEN`.
4. Invite the bot to your Discord server (OAuth2 > URL Generator > scope `bot`,
   no permissions needed). The bot can only message people who share a server with
   it, and those people must allow direct messages from server members.

Google, Apple and email login/reset show "unavailable: the email service is not
working right now" in the game. That is expected for now.

## Step 6: Cloudflare tunnel (makes your servers reachable, no open ports)

1. In `~/.rysteria-secrets/common.env` set `CLOUDFLARED_ENABLED=1`, then run
   `scripts/<os>/setup.sh` again so cloudflared gets installed.
2. Log in (opens a browser; pick your domain):
   ```sh
   cloudflared tunnel login
   ```
3. Create the tunnel. The name must match `TUNNEL_NAME`:
   ```sh
   cloudflared tunnel create rysteria
   ```
   It prints something like `Created tunnel rysteria ... credentials written to
   /home/you/.cloudflared/<long-id>.json`. Put that exact path in `common.env` as
   `TUNNEL_CREDENTIALS`.
4. Point each hostname at the tunnel (one command each):
   ```sh
   cloudflared tunnel route dns rysteria api-game.parshwa.blog
   cloudflared tunnel route dns rysteria game.parshwa.blog
   cloudflared tunnel route dns rysteria hc-game.parshwa.blog
   cloudflared tunnel route dns rysteria pvp-game.parshwa.blog
   cloudflared tunnel route dns rysteria ga-game.parshwa.blog
   cloudflared tunnel route dns rysteria ctf-game.parshwa.blog
   ```
   (If a hostname already exists in Cloudflare DNS, delete that old record first.)

You do **not** write a tunnel config: `run.sh` generates it from
`servers.conf`. In the Cloudflare dashboard make sure **Network > WebSockets** is
on (it is by default) and SSL/TLS mode is **Full** or higher.

## Step 7: build

```sh
scripts/<os>/build.sh
```
This builds the master, the four game servers, gardn, and both browser clients
into `builds/<os>-<arch>/`. One folder per server, each with its own `.env`:

```
builds/macos-arm64/   (or debian-amd64, debian-arm64 ...)
  master/  rrolf-hc/  rrolf-pvp/  rrolf-garden/  rrolf-ctf/  gardn/  edge/  rrolf-client/  run/
```
Expect 10-30 minutes the first time (the WebAssembly parts are slow). It stops
with a clear message if the database address is still the placeholder.

## Step 8: run

```sh
scripts/<os>/run.sh
```
It starts, in order: master (waits until it is healthy), the four rrolf servers,
gardn, edge, and the Cloudflare tunnel (if enabled). Everything runs in the
background. Check it:

```sh
curl https://api-game.parshwa.blog/health        # {"ok":true,"db":"postgres"}
curl https://game.parshwa.blog/health            # {"ok":true}
```
Then open **https://game.parshwa.blog**, click **Sign up**, make an account, and
play. Gardn is at **https://game.parshwa.blog/gardn/** and uses the same login
(log in on the main page first).

Logs: `builds/<os>-<arch>/run/<name>.log`.

## Everyday commands

| I want to... | Command |
|---|---|
| start everything | `scripts/<os>/run.sh` |
| stop everything (saves players first) | `scripts/<os>/stop.sh` |
| update to the newest code | `stop.sh`, then `setup.sh`, `clean-builds.sh`, `build.sh`, `run.sh` |
| delete old builds | `scripts/<os>/clean-builds.sh` (only deletes `builds/`, refuses while running) |
| do all of it on a fresh machine | `scripts/<os>/up.sh` (setup + build + run) |
| start on every reboot (Linux) | `crontab -e`, add `@reboot /home/you/rysteria-gardn-merged/scripts/debian/run.sh` |

## Make yourself an admin

Dev tools in the game belong to accounts that have the dev flag. Sign up first,
then set it in the database:

PostgreSQL: `UPDATE accounts.accounts SET is_dev = true WHERE username_lower = 'yourname';`
MongoDB: `db.accounts.updateOne({username_lower: "yourname"}, {$set: {is_dev: true}})`

(Log out and back in, or reconnect, to pick it up.)

## Windows

Use PowerShell in the `scripts\windows` folder. Each script runs the Debian one
inside WSL2 Ubuntu and installs WSL/Ubuntu first if you do not have it
(you may need a restart, then run the script again):

```powershell
.\bootstrap.ps1      # empty machine: installs WSL Ubuntu, clones the repo inside it, runs setup
.\setup.ps1  ;  .\build.ps1  ;  .\run.ps1  ;  .\stop.ps1  ;  .\clean-builds.ps1  ;  .\up.ps1
```
The secrets folder is then `~/.rysteria-secrets/` **inside Ubuntu** (open it with
`wsl nano ~/.rysteria-secrets/master.env`). Your database must be reachable from
inside WSL.

## If something goes wrong

| Symptom | Likely cause and fix |
|---|---|
| `build.sh` says "set the postgres connection string" | `POSTGRES_URI` (or `MONGO_URI`) in `master.env` still has the placeholder |
| `run.sh`: "master did not become healthy" | read `builds/.../run/master.log`: usually a wrong database address/password or the database is not reachable |
| Site loads but "Could not reach the account server" | `CLIENT_API_URL` is wrong, the `api-game` DNS route is missing (Step 6.4), or `ALLOWED_ORIGINS` does not exactly equal the page address (including `https://`, no trailing slash) |
| Logging in works but joining a game kicks you | a game server has an old `SERVER_SECRET` (rebuild so every `.env` is rewritten), or Step 0 said MISSING |
| Discord button says unavailable | `DISCORD_CLIENT_ID/SECRET/REDIRECT_URI` empty or the redirect in the Discord portal does not match exactly |
| Password-reset code never arrives | the player is not in a Discord server with your bot, or has DMs from server members turned off |
| gardn says "Not logged in" | log in on the main page first (same address), the token expired (a week), or gardn's `.env` has a different `SERVER_SECRET` |
| "Too many requests" | the built-in rate limiter (sign-ups 5/hour, logins 10 per 10 minutes per address); wait |
| Everything worked, then nothing after a reboot | nothing starts by itself: run `run.sh` (or add the `@reboot` line above) |
| Clean refuses to delete | servers are still running: run `stop.sh` first |

## Good to know

* **Back up your database.** Everything players earn lives there (`pg_dump rysteria > backup.sql`, or Atlas backups). The `~/.rysteria-secrets/` folder is also worth a private backup; lose it and nobody can log in until you create new secrets.
* Players are saved when they leave, every 5 seconds while playing, and on stop. A crash loses at most about 5 seconds for rrolf and up to 60 seconds of gardn progress saves.
* Logging in lasts a week (`PL-P`); after that the player logs in again.
* Never commit `~/.rysteria-secrets/` or any `.env` to git. The old Node master in `rrolf/MasterServer/main.js` still has secrets written inside the code: treat those as leaked and do not reuse them.
* Where things are: master code `rrolf/MasterServer/c/` (has its own README), scripts `scripts/` (has its own README), builds `builds/`, secrets `~/.rysteria-secrets/`.
