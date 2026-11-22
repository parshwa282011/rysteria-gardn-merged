#!/bin/bash
# Cloud-init user-data for the GAME instance (Oracle Linux 9, aarch64: VM.Standard.A1.Flex / A4.Flex).
# Paste into "Show advanced options > Management > Cloud-init script" when creating the instance,
# or run it by hand on an instance that already exists:   sudo bash oracle-cloud-init-game.sh
#
# Runs once as root, in this order:
#   1. install everything (compilers, libs, Node, emscripten, nginx, swap)   -- no cloudflared, no PostgreSQL
#   2. clone the repo
#   3. firewall: ssh + https (443) only
#   4. leave a helper (~/finish-setup.sh) that builds and starts everything AFTER you push the secrets
#
# HOW IT IS REACHED (replaces the Cloudflare tunnel):
#   browser --https--> Cloudflare (orange cloud, DNS A records -> this instance's public IP)
#           --https:443--> nginx on this machine --by hostname--> the servers on 127.0.0.1
#   nginx routes the same hostnames the tunnel did (api-game -> master 55554, game -> edge 8080,
#   hc-game -> rrolf 1234, ...), generated from scripts/common/servers.conf by oracle-finish-game.sh.
#   The game servers listen on 127.0.0.1 only; the only public port is 443, and the OCI security
#   list only lets Cloudflare's address ranges reach it (so TRUST_PROXY_HEADER=CF-Connecting-IP is safe).
#   Cloudflare dashboard: SSL/TLS mode "Full" (nginx uses a self-signed certificate) or, better,
#   "Full (strict)" with a Cloudflare Origin certificate in /etc/nginx/origin.pem + origin.key.
# This instance runs ALL the game servers (master, rrolf x4, gardn, edge) and serves the clients.
# The database lives on the other instance (oracle-cloud-init-db.sh): in master.env
#   POSTGRES_URI=postgresql://<user>:<password>@<db instance PRIVATE ip>:5432/<db>
# Secrets are NOT in this script. From your Mac, once the instance is up (or just ./quick-deploy-oracle.sh game):
#   scripts/push-secrets.sh opc@<public-ip> ~/.ssh/<key>
#   ssh -i ~/.ssh/<key> opc@<public-ip> 'nohup ~/finish-setup.sh > ~/finish-setup.log 2>&1 &'
#   ssh -i ~/.ssh/<key> opc@<public-ip> 'tail -f ~/finish-setup.log'
#
# Log of this script: /var/log/rysteria-init.log    Done marker: /var/log/rysteria-init.done
set -uo pipefail
exec > >(tee -a /var/log/rysteria-init.log) 2>&1

# =====================================================================================
# CONFIG
# =====================================================================================
REPO_URL="https://github.com/parshwa282011/rysteria-gardn-merged.git"
RUN_USER="opc"

# Opened in firewalld: ssh and https only. The OCI security list is the second firewall: 22 for you, 443 for Cloudflare.
EXTRA_TCP_PORTS="22 443"
CLONE_SUBMODULES="${CLONE_SUBMODULES:-1}"   # 0 = skip the (big) submodules, e.g. when quick-deploy-oracle.sh copies them anyway

SWAP_SIZE_GB=4                # the emscripten link step is hungry; 6 GB RAM is tight
EMSDK_VERSION="6.0.12"           # the version the Mac builds with; emscripten 7.x breaks gardn (missing #includes)

# =====================================================================================
# 1. INSTALL EVERYTHING
# =====================================================================================
echo "==> $(date) starting"
HOME_DIR="/home/$RUN_USER"
INSTALL_DIR="$HOME_DIR/rysteria-gardn-merged"
STATE_DIR=/var/lib/rysteria-init
mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"

# swap first, so nothing below gets OOM-killed
if [ ! -f /swapfile ] && [ "$SWAP_SIZE_GB" -gt 0 ]; then
    fallocate -l "${SWAP_SIZE_GB}G" /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile \
        && echo '/swapfile none swap sw 0 0' >> /etc/fstab || echo "!! swap setup failed"
fi

dnf -y install oracle-epel-release-el9 || true
dnf config-manager --set-enabled ol9_codeready_builder || true
dnf config-manager --set-enabled ol9_developer_EPEL || true   # libsodium, libwebsockets, mongo-c-driver come from here

dnf -y groupinstall "Development Tools"
dnf -y install git curl ca-certificates openssl python3 tar xz bzip2 unzip which \
    gcc gcc-c++ clang cmake make pkgconf-pkg-config firewalld \
    libcurl-devel openssl-devel libpq-devel nginx rsync policycoreutils-python-utils
# emscripten's closure compiler wants Java 21+ (and it must be the default java, OL9 ships 1.8 as well)
dnf -y install java-21-openjdk-headless || dnf -y install java-17-openjdk-headless
J="$(ls /usr/lib/jvm/ | grep -E '^java-(21|17)-openjdk' | sort -r | head -1)"
[ -z "$J" ] || alternatives --set java "$(ls -d /usr/lib/jvm/$J/bin/java 2>/dev/null || ls /usr/lib/jvm/$J*/bin/java | head -1)" || true
# emsdk needs python 3.10+, OL9's default python3 is 3.9
dnf -y install python3.11 || dnf -y install python3.12 || echo "!! no python >= 3.10"
runuser -l "$RUN_USER" -c 'mkdir -p ~/.local/bin && ln -sf "$(command -v python3.12 || command -v python3.11)" ~/.local/bin/python3'   # emcc starts "python3"
# one by one: a missing package must not abort the rest
for pkg in libwebsockets-devel libsodium-devel mongo-c-driver-devel; do
    dnf -y install "$pkg" || echo "!! could not install $pkg"
done

# Node.js 20 (gardn host + edge use global fetch)
dnf -y module enable nodejs:20 || true
dnf -y install nodejs npm || echo "!! could not install nodejs"

# emscripten (builds the two WASM clients and the gardn server), as the normal user
if [ ! -d "$HOME_DIR/emsdk" ]; then
    export EMSDK_PYTHON="$(command -v python3.12 || command -v python3.11)"
    runuser -l "$RUN_USER" -c "export EMSDK_PYTHON=$EMSDK_PYTHON; git clone --depth 1 https://github.com/emscripten-core/emsdk.git ~/emsdk && ~/emsdk/emsdk install $EMSDK_VERSION && ~/emsdk/emsdk activate $EMSDK_VERSION" \
        || echo "!! emsdk install failed: clients can't be built (retry: ~/emsdk/emsdk install $EMSDK_VERSION)"
fi

# =====================================================================================
# 2. CLONE
# =====================================================================================
if [ -d "$INSTALL_DIR/.git" ]; then
    echo "==> $INSTALL_DIR already exists, skipping clone"
else
    SUB="--recurse-submodules"; [ "$CLONE_SUBMODULES" = 1 ] || SUB=""
    runuser -u "$RUN_USER" -- git clone $SUB "$REPO_URL" "$INSTALL_DIR" || { echo "!! clone failed"; exit 1; }
fi

# =====================================================================================
# 3. FIREWALL: ssh + https. Nothing else: the game servers sit behind nginx on 127.0.0.1
#    (ssh is added first so you can't lock yourself out)
# =====================================================================================
systemctl enable --now firewalld
firewall-cmd --permanent --add-service=ssh
for p in $EXTRA_TCP_PORTS; do firewall-cmd --permanent --add-port="$p/tcp"; done
firewall-cmd --reload
firewall-cmd --list-all
# SELinux: let nginx connect to the servers on localhost
setsebool -P httpd_can_network_connect 1 || echo "!! setsebool failed"
systemctl enable nginx        # started by oracle-finish-game.sh once its configuration exists
rm -f /etc/nginx/conf.d/default.conf

# =====================================================================================
# 4. systemd unit + the helper you run after pushing the secrets
# =====================================================================================
# A USER service (systemctl --user), not a system one: SELinux (enforcing on Oracle Linux) does not let a
# system service execute scripts and programs that live in /home, but the user's own session may.
# Linger = it starts at boot without anybody logged in.
loginctl enable-linger "$RUN_USER"
UID_RUN="$(id -u "$RUN_USER")"
sudo -u "$RUN_USER" mkdir -p "$HOME_DIR/.config/systemd/user"
cat > "$HOME_DIR/.config/systemd/user/rysteria.service" <<UNIT
[Unit]
Description=Rysteria game servers (master, rrolf, gardn, edge)
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
KillMode=process
TimeoutStartSec=600
ExecStart=%h/rysteria-gardn-merged/scripts/debian/run.sh
ExecStop=%h/rysteria-gardn-merged/scripts/debian/stop.sh

[Install]
WantedBy=default.target
UNIT
chown "$RUN_USER:$RUN_USER" "$HOME_DIR/.config/systemd/user/rysteria.service"
systemctl start "user@$UID_RUN.service" || true
runuser -u "$RUN_USER" -- env XDG_RUNTIME_DIR="/run/user/$UID_RUN" systemctl --user daemon-reload || true
runuser -u "$RUN_USER" -- env XDG_RUNTIME_DIR="/run/user/$UID_RUN" systemctl --user enable rysteria || true

cat > "$HOME_DIR/finish-setup.sh" <<'FIN'
#!/bin/bash
# Run AFTER scripts/push-secrets.sh (the work is done by the repo: scripts/oracle-finish-game.sh --help)
exec ~/rysteria-gardn-merged/scripts/oracle-finish-game.sh "$@"
FIN
chown "$RUN_USER:$RUN_USER" "$HOME_DIR/finish-setup.sh"; chmod 755 "$HOME_DIR/finish-setup.sh"

touch /var/log/rysteria-init.done
echo "==> $(date) done. Next: push the secrets, then run ~/finish-setup.sh (see the top of this script)."
