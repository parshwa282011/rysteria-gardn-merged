// The website is served as static assets (see wrangler.jsonc). This code only runs for /gardn,
// /gardn/ and /health:
//   - a websocket to /gardn/ is passed on to the machine behind the tunnel (ORIGIN_HOST),
//     which is where the gardn server answers it;
//   - the page /gardn/ (an ordinary GET) is the static gardn/index.html;
//   - /gardn without the slash goes to /gardn/ (the page links its files relatively).
export default {
    async fetch(request, env) {
        const url = new URL(request.url);
        if (url.pathname === "/health") {
            return Response.json({ ok: true, worker: true, origin: Boolean(env.ORIGIN_HOST) });
        }
        const isUpgrade = (request.headers.get("Upgrade") || "").toLowerCase() === "websocket";
        if (isUpgrade) {
            if (!env.ORIGIN_HOST) return new Response("no origin set", { status: 503 });
            const origin = new URL(request.url);
            origin.protocol = "https:";
            origin.hostname = env.ORIGIN_HOST;
            origin.port = "";
            // fetch() with an Upgrade header is how a Worker passes a websocket on
            return fetch(new Request(origin, request));
        }
        if (url.pathname === "/gardn") {
            return Response.redirect(url.origin + "/gardn/" + url.search, 302);
        }
        return env.ASSETS.fetch(request);
    },
};
