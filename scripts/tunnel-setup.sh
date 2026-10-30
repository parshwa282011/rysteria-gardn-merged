for h in api-game game hc-game default-game pvp-game ga-game garden-game ctf-game; do
  cloudflared tunnel route dns --overwrite-dns 12c85dfb-7d87-40ca-845e-dba81444c475 $h.parshwa.blog
done