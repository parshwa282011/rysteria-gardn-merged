# The website on a Cloudflare Worker

What can run on Cloudflare itself: the **website** (the rrolf client, the gardn client, login, account, leaderboard and
stats pages). What cannot: the master (C), the rrolf game servers, and the gardn server. Those need real processes and
stay on your machines behind the cloudflared tunnel, as before.

```
browser ---> Cloudflare Worker (this folder)          static files, free, up even when your machines are off
   |            '-- websocket to /gardn/ ----------->  tunnel hostname ORIGIN_HOST -> edge -> gardn
   '--------> api-game / hc-game / pvp-game / ...  ->  tunnel -> master and game servers (unchanged)
```

| file | what |
|---|---|
| `wrangler.jsonc` | the Worker: static assets from `./dist`, the routes that run code first, `ORIGIN_HOST` |
| `worker.js` | passes the gardn websocket to `ORIGIN_HOST`, redirects `/gardn` to `/gardn/`, answers `/health` |
| `../scripts/build-web.sh` | builds both clients and lays the site out in `dist/` the way `scripts/common/edge.js` serves it |
| `../.github/workflows/deploy-web.yml` | builds and deploys on every push to `main` that touches `rrolf/`, `gardn/` or this folder |

## Set up the deploy (once)

1. Cloudflare dashboard > My Profile > API Tokens > Create Token > template **Edit Cloudflare Workers**.
2. ```sh
   gh secret set CLOUDFLARE_API_TOKEN  -R parshwa282011/rysteria-gardn-merged
   gh secret set CLOUDFLARE_ACCOUNT_ID -R parshwa282011/rysteria-gardn-merged --body <the id in the dashboard address>
   ```
3. Push. Or run the workflow by hand: `gh workflow run deploy-web.yml -R parshwa282011/rysteria-gardn-merged`.

The first deploy creates the Worker `rysteria-web` and puts it on `rysteria-web.<your account>.workers.dev`.
Build it yourself with `scripts/build-web.sh` (needs emscripten, about half a minute) and try it with
`cd cloudflare && npx wrangler dev`.

## What you will see on workers.dev, and why it is not the real site yet

The pages and clients decide where the servers are from the **hostname** they are served on
(`game.parshwa.blog` in `rrolf/Client/DOM.c`, and `apiBase()` in the pages). On `workers.dev` they load and draw, but
do not connect to a game. The Worker only becomes the real site when it serves `game.parshwa.blog`.

## Moving game.parshwa.blog to the Worker

This changes where the live site comes from, so do it when you can watch it. The tunnel keeps serving everything
except the static files.

1. **A second name for the edge.** In `scripts/common/servers.conf` change the edge line's hostname from `game` to
   `game,origin-game`, deploy, so the tunnel also answers `origin-game.parshwa.blog`:
   `cloudflared tunnel route dns --overwrite-dns rysteria2 origin-game.parshwa.blog`. Check
   `https://origin-game.parshwa.blog/health` and `/gardn/`.
2. `ORIGIN_HOST` in `wrangler.jsonc` is that name already.
3. **Flip the name.** Cloudflare dashboard > DNS: delete the record `game` (the CNAME to the tunnel). Uncomment the
   `routes` line in `wrangler.jsonc` and deploy (push, or `npx wrangler deploy`). A few seconds to a minute without the site.
4. Check `https://game.parshwa.blog/`, `/login`, `/gardn/`, and that a game connects.

To go back: remove the custom domain from the Worker (Workers > rysteria-web > Settings > Domains) and run
`cloudflared tunnel route dns --overwrite-dns rysteria2 game.parshwa.blog`. The `edge` process still serves everything itself.

## Keep the gardn client and server on the same version

The gardn client and server refuse each other when their version hash differs ("Outdated Version"). The hash is now
the **commit time of gardn** (`scripts/common/build-hash.sh`), used by `scripts/<os>/build.sh` for the servers and by
`build-web.sh` for the client, so the same gardn commit gives the same number everywhere. After a gardn change: push
(the Action rebuilds the site) and deploy the servers (`quick-deploy.sh`) from the same commit. Between the two, a
browser may be told it is outdated. A build from a gardn folder with uncommitted changes falls back to the time now,
which never matches a Worker.

## Limits

* Static files are served by Cloudflare without running your code. Only `/gardn`, `/gardn/` (the page and the websocket
  share a path) and `/health` run `worker.js`, so each gardn page load and each gardn connection is one Worker request.
  Check the current free-plan request limit on Cloudflare's pricing page.
* Websockets to the rrolf servers do not go through the Worker: the client connects to `*-game.parshwa.blog` directly.
* The petal icons for the stats pages are made with headless Chrome, which `ubuntu-latest` has. If that step fails the
  site still deploys with plain tiles (`--no-icons` skips it).
