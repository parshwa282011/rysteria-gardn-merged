#!/bin/bash
# Cloud-init user-data for the DATABASE instance (Oracle Linux 9, aarch64, VM.Standard.A1.Flex).
# Pair of oracle-cloud-init-game.sh (which runs the game servers on another instance).
#
# What this machine is for:
#   * a local PostgreSQL that the master (game instance) talks to over the private VCN network.
#     Every request is answered here, instantly, and costs nothing.
#   * the first time, the local database is CLONED from the online one (remote-copy.py --pull)
#   * afterwards scripts/common/remote-copy.py --loop (a systemd service) pushes what changed
#     to the online database in ONE batched request every COPY_INTERVAL_SECONDS (default 30 min).
#     Nothing changed = no request. So the online database sees at most 48 requests a day.
#
# Runs once as root on first boot: installs + configures PostgreSQL, clones the repo (for
# remote-copy.py), opens the firewall. Secrets are NOT here. After the instance is up, from your Mac:
#   scripts/push-secrets.sh opc@<db-public-ip> ~/.ssh/<key>     # needs REMOTE_POSTGRES_URI in master.env
#   ssh -i ~/.ssh/<key> opc@<db-public-ip> '~/finish-db.sh'     # clone from online + start the sync
# Do this BEFORE starting the game instance. In the game instance's master.env use:
#   POSTGRES_URI=postgresql://<PG_USER>:<password>@<this instance PRIVATE ip>:5432/<PG_DB>
# (the password is printed at the end of /var/log/rysteria-init.log, or set PG_PASSWORD below)
#
# Log: /var/log/rysteria-init.log    Done marker: /var/log/rysteria-init.done
set -uo pipefail
exec > >(tee -a /var/log/rysteria-init.log) 2>&1

# =====================================================================================
# CONFIG
# =====================================================================================
REPO_URL="https://github.com/parshwa282011/rysteria-gardn-merged.git"
RUN_USER="opc"

PG_USER="rysteria"
PG_DB="rysteria"
PG_PASSWORD="bc9996e7556b829e6446ccdde40f988ab099046e5d1964ce"   # set so you can put it in the game instance's master.env before this instance even exists.
                                # (letters/digits only: keep it that way, it goes into a URL and into SQL). Empty = generated at boot
# Who may connect to PostgreSQL from the network: your VCN CIDR (Networking > VCN > CIDR block).
# Must be the VCN/subnet of the game instance, never 0.0.0.0/0.
ALLOWED_CIDR="10.0.0.0/16"
COPY_INTERVAL_SECONDS=1800      # how often changes are pushed to the online database (batched)
SWAP_SIZE_GB=2

# =====================================================================================
# 1. INSTALL
# =====================================================================================
echo "==> $(date) starting"
HOME_DIR="/home/$RUN_USER"
INSTALL_DIR="$HOME_DIR/rysteria-gardn-merged"
STATE_DIR=/var/lib/rysteria-init
mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"

# ---- low-memory machine (Always Free micro: 0.5-1 GB RAM) ----
echo "==> memory at start:"; free -m
# swap first, so nothing below gets OOM-killed; 'dd' also works where fallocate swap is refused
if [ ! -f /swapfile ] && [ "$SWAP_SIZE_GB" -gt 0 ]; then
    { fallocate -l "${SWAP_SIZE_GB}G" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=$((SWAP_SIZE_GB * 1024)); } \
        && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile \
        && echo '/swapfile none swap sw 0 0' >> /etc/fstab || echo "!! swap setup failed"
fi
# swap only when really needed, keep the file cache, and never let sshd be the OOM victim
cat > /etc/sysctl.d/90-rysteria.conf <<SYSCTL
vm.swappiness = 20
vm.vfs_cache_pressure = 50
SYSCTL
sysctl --system >/dev/null
mkdir -p /etc/systemd/system/sshd.service.d
printf '[Service]\nOOMScoreAdjust=-1000\n' > /etc/systemd/system/sshd.service.d/oom.conf
systemctl daemon-reload
for pid in $(pgrep -x sshd); do echo -1000 > /proc/$pid/oom_score_adj 2>/dev/null || true; done   # the running sshd too

# dnf with a small footprint: only the base repos (less metadata to load), no weak dependencies,
# no cache kept, low priority. (no "dnf -y update": it froze this machine before)
REPOS=""
for r in ol9_baseos_latest ol9_appstream; do
    dnf repolist --all 2>/dev/null | grep -q "^$r " && REPOS="$REPOS --enablerepo=$r"
done
[ -n "$REPOS" ] && REPOS="--disablerepo=* $REPOS"
dnf_install() { nice -n 10 dnf -y $REPOS --setopt=install_weak_deps=False --setopt=keepcache=0 install "$@"; }

dnf_install git curl openssl python3 firewalld
dnf -y $REPOS module enable postgresql:16 || dnf -y $REPOS module enable postgresql:15 || true
dnf_install postgresql-server postgresql      # server + psql + pg_dump (remote-copy.py uses both)
dnf clean all >/dev/null 2>&1 || true
echo "==> memory after install:"; free -m

# =====================================================================================
# 2. POSTGRESQL
# =====================================================================================
PGDATA=/var/lib/pgsql/data
[ -f "$PGDATA/PG_VERSION" ] || postgresql-setup --initdb

# size the memory settings to this machine (the master uses 4 connections, the copier 1-2)
MEM_MB=$(awk '/MemTotal/ { print int($2/1024) }' /proc/meminfo)
SHARED_MB=$((MEM_MB / 5)); [ "$SHARED_MB" -gt 512 ] && SHARED_MB=512; [ "$SHARED_MB" -lt 32 ] && SHARED_MB=32
CACHE_MB=$((MEM_MB / 2))
if ! grep -q '# rysteria' "$PGDATA/postgresql.conf"; then
    cat >> "$PGDATA/postgresql.conf" <<CONF

# rysteria (small machine)
listen_addresses = '*'          # reachable on the private IP; the firewall + pg_hba limit who
shared_buffers = ${SHARED_MB}MB
effective_cache_size = ${CACHE_MB}MB
max_connections = 20
work_mem = 2MB
maintenance_work_mem = 32MB
wal_buffers = 4MB
max_wal_size = 256MB
min_wal_size = 64MB
checkpoint_timeout = 15min
autovacuum_max_workers = 2
autovacuum_work_mem = 32MB
huge_pages = off
jit = off
max_worker_processes = 2
max_parallel_workers_per_gather = 0
CONF
fi
# Postgres is the one thing that must survive memory pressure
mkdir -p /etc/systemd/system/postgresql.service.d
printf '[Service]\nOOMScoreAdjust=-800\n' > /etc/systemd/system/postgresql.service.d/oom.conf
systemctl daemon-reload
# loopback: password instead of ident; VCN: password only for our role and database
sed -i -E 's/^(host\s+all\s+all\s+(127\.0\.0\.1\/32|::1\/128)\s+)ident/\1scram-sha-256/' "$PGDATA/pg_hba.conf"
if ! grep -q '# rysteria' "$PGDATA/pg_hba.conf"; then
    printf '\n# rysteria\nhost    %s    %s    %s    scram-sha-256\n' "$PG_DB" "$PG_USER" "$ALLOWED_CIDR" >> "$PGDATA/pg_hba.conf"
fi
systemctl enable --now postgresql
systemctl restart postgresql

if [ ! -f "$STATE_DIR/pgpass" ]; then
    [ -n "$PG_PASSWORD" ] || PG_PASSWORD="$(openssl rand -hex 24)"
    echo "$PG_PASSWORD" > "$STATE_DIR/pgpass"; chmod 600 "$STATE_DIR/pgpass"
    su - postgres -c "psql -v ON_ERROR_STOP=1 -c \"CREATE ROLE $PG_USER LOGIN PASSWORD '$PG_PASSWORD';\" -c 'CREATE DATABASE $PG_DB OWNER $PG_USER;'" \
        || echo "!! postgres role/db creation failed"
fi
PG_PASSWORD="$(cat "$STATE_DIR/pgpass")"
# the local URI used by remote-copy.py on THIS machine (readable by the normal user only)
( umask 077; echo "postgresql://$PG_USER:$PG_PASSWORD@127.0.0.1:5432/$PG_DB" > "$HOME_DIR/.local-db-uri" )
chown "$RUN_USER:$RUN_USER" "$HOME_DIR/.local-db-uri"

# =====================================================================================
# 3. CLONE (only for scripts/common/remote-copy.py)
# =====================================================================================
if [ ! -d "$INSTALL_DIR/.git" ]; then
    runuser -u "$RUN_USER" -- git clone --depth 1 "$REPO_URL" "$INSTALL_DIR" || echo "!! clone failed"
fi

# =====================================================================================
# 4. FIREWALL: ssh for everyone, PostgreSQL ONLY from ALLOWED_CIDR
#    (also add TCP 5432 from the same CIDR to the OCI security list / NSG)
# =====================================================================================
systemctl enable --now firewalld
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=$ALLOWED_CIDR port port=5432 protocol=tcp accept"
firewall-cmd --reload
firewall-cmd --list-all

# =====================================================================================
# 5. the sync service + the helper you run after pushing the secrets
# =====================================================================================
cat > /etc/systemd/system/rysteria-db-sync.service <<UNIT
[Unit]
Description=Rysteria: local PostgreSQL -> online database, batched (remote-copy.py --loop)
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
User=$RUN_USER
Environment=REMOTE_COPY_INTERVAL=$COPY_INTERVAL_SECONDS
# POSTGRES_URI = this machine's database; REMOTE_POSTGRES_URI comes from ~/.rysteria-secrets/master.env
ExecStart=/bin/bash -c 'POSTGRES_URI="\$\$(cat ~/.local-db-uri)" exec python3 $INSTALL_DIR/scripts/common/remote-copy.py --loop'
Restart=always
RestartSec=60
Nice=10
MemoryMax=150M

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload

cat > "$HOME_DIR/finish-db.sh" <<'FIN'
#!/bin/bash
# Run AFTER scripts/push-secrets.sh (needs REMOTE_POSTGRES_URI in ~/.rysteria-secrets/master.env).
# 1. clones the online database into the local one (only if it was never synced), 2. starts the batched sync.
set -euo pipefail
S=~/.rysteria-secrets
grep -q '^REMOTE_POSTGRES_URI=.' $S/master.env 2>/dev/null || { echo "no REMOTE_POSTGRES_URI in $S/master.env: run scripts/push-secrets.sh from your Mac first"; exit 1; }
export POSTGRES_URI="$(cat ~/.local-db-uri)"
RC=~/rysteria-gardn-merged/scripts/common/remote-copy.py
if [ ! -f $S/remote-copy-state.json ]; then
    echo "==> first run: cloning the online database into the local one"
    python3 $RC --pull || echo "!! pull failed (a brand new online database has no tables yet: that is fine, the sync below will create them once the master has made accounts)"
else
    echo "==> already synced before, not pulling again"
fi
sudo systemctl enable --now rysteria-db-sync
sleep 2
sudo systemctl --no-pager status rysteria-db-sync | head -n 12
python3 $RC --status
echo "==> now start the game instance (its POSTGRES_URI points to this machine's PRIVATE ip, port 5432)"
FIN
chown "$RUN_USER:$RUN_USER" "$HOME_DIR/finish-db.sh"; chmod 755 "$HOME_DIR/finish-db.sh"

touch /var/log/rysteria-init.done
echo "==> $(date) done."
echo "==> PRIVATE ip of this instance: $(hostname -I | awk '{print $1}')"
echo "==> POSTGRES_URI for the game instance's master.env:"
echo "    postgresql://$PG_USER:$PG_PASSWORD@$(hostname -I | awk '{print $1}'):5432/$PG_DB"
