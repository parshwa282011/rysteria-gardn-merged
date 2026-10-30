for h in api-game game hc-game default-game pvp-game ga-game garden-game ctf-game; do
  cloudflared tunnel route dns --overwrite-dns rysteria2 $h.parshwa.blog
done