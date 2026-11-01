# Sourced by split-mac.sh and split-pi.sh (top folder of the repository): runs
# scripts/common/split.sh on the right machine of secrets/nodes.conf over ssh, or here
# with --local. The first line of nodes.conf is the "mac" side (the main machine with
# the master and the database), the second line is the "pi" side.

split_launch() { # <mac|pi> <script's arguments...>
    local role="$1" me_script="$2"
    shift 2
    local action="$role" node="" key="" local_run=0 allow_old=0 worker_opts=()
    [ -f "$HOME/.ssh/id_c1" ] && key="$HOME/.ssh/id_c1"
    while [ $# -gt 0 ]; do
        case "$1" in
        --off) action=off ;;
        --status) action=status ;;
        --tunnel-check) action=tunnel-check ;;
        --local) local_run=1 ;;
        --allow-old) allow_old=1 ;;
        --node) shift; node="${1:?--node needs a name from nodes.conf}" ;;
        --key) shift; key="${1:?--key needs a file}" ;;
        --dry-run | --no-apply | --no-start | --no-start-pi) worker_opts+=("$1") ;;
        --remote) worker_opts+=("$1" "${2:?--remote needs names}"); shift ;;
        -h | --help) sed -n 2,/^set/p "$me_script" | sed '$d; s/^# \{0,1\}//'; return 0 ;;
        *) echo "unknown option: $1 (see --help)" >&2; return 2 ;;
        esac
        shift
    done

    local nodes="$ROOT/secrets/nodes.conf"
    [ -f "$nodes" ] || nodes="$ROOT/dual-server-syncing/nodes.conf"
    [ -f "$nodes" ] || { echo "error: no secrets/nodes.conf" >&2; return 1; }
    # name os lan ssh repo, best first: line 1 = mac side, line 2 = pi side
    local lines n1 n2
    lines="$(awk '$1 !~ /^#/ && NF >= 5 { print }' "$nodes")"
    n1="$(printf '%s\n' "$lines" | sed -n 1p)"
    n2="$(printf '%s\n' "$lines" | sed -n 2p)"
    [ -n "$n1" ] && [ -n "$n2" ] || { echo "error: $nodes needs two machines (main one first)" >&2; return 1; }
    local mac_name mac_os mac_lan mac_ssh mac_repo pi_name pi_os pi_lan pi_ssh pi_repo
    read -r mac_name mac_os mac_lan mac_ssh mac_repo _ <<<"$n1"
    read -r pi_name pi_os pi_lan pi_ssh pi_repo _ <<<"$n2"
    mac_lan="${mac_lan%%:*}"; pi_lan="${pi_lan%%:*}"

    local target_name target_ssh target_repo
    if [ "$role" = mac ]; then target_name="$mac_name"; target_ssh="$mac_ssh"; target_repo="$mac_repo"
    else target_name="$pi_name"; target_ssh="$pi_ssh"; target_repo="$pi_repo"; fi
    if [ -n "$node" ]; then
        local line
        line="$(printf '%s\n' "$lines" | awk -v n="$node" '$1 == n { print; exit }')"
        [ -n "$line" ] || { echo "error: $node is not in $nodes" >&2; return 1; }
        read -r target_name _ _ target_ssh target_repo _ <<<"$line"
    fi

    # what the worker needs to know about the other machine
    local args=("$action")
    if [ "$action" = mac ]; then
        args+=(--pi-addr "$pi_lan" --pi-ssh "$pi_ssh" --pi-repo "$pi_repo" --pi-os "$pi_os")
    elif [ "$action" = pi ]; then
        args+=(--mac-addr "$mac_lan")
    fi
    local ssh_opts=(-o BatchMode=yes -o ConnectTimeout=10)
    [ -z "$key" ] || ssh_opts+=(-i "$key" -o IdentitiesOnly=yes)

    if [ "$local_run" = 1 ]; then
        [ -z "$key" ] || [ "$action" != mac ] || args+=(--key "$key")
        exec "$ROOT/scripts/common/split.sh" "${args[@]}" ${worker_opts[@]+"${worker_opts[@]}"}
    fi

    echo "==> $role side: $target_name ($target_ssh)"
    # the worker is part of the repository: the machine has to have this commit
    local want have
    want="$(git -C "$ROOT" rev-parse HEAD)"
    have="$(ssh -n "${ssh_opts[@]}" "$target_ssh" "cd '$target_repo' && git rev-parse HEAD" 2>/dev/null || echo "?")"
    if [ "$have" = "?" ]; then echo "error: cannot ssh to $target_ssh (or $target_repo is not a repository)" >&2; return 1; fi
    if ! ssh -n "${ssh_opts[@]}" "$target_ssh" "test -x '$target_repo/scripts/common/split.sh'" 2>/dev/null; then
        echo "error: $target_name has no scripts/common/split.sh yet. Commit and push this repository, then ./quick-deploy.sh (or git pull there)" >&2
        return 1
    fi
    if [ "$have" != "$want" ] && [ "$allow_old" = 0 ]; then
        echo "error: $target_name is at ${have:0:7}, this computer at ${want:0:7}. Run ./quick-deploy.sh first (it pushes, updates and builds), or --allow-old" >&2
        return 1
    fi
    # the key the main machine uses to reach the other one (restarting its servers): the first that works
    if [ "$action" = mac ]; then
        local k found="" worked=0 opt
        for k in "" "~/.ssh/id_c1" "~/.ssh/id_ed25519" "~/.ssh/id_rsa"; do
            opt=""
            [ -z "$k" ] || opt="-i $k -o IdentitiesOnly=yes"
            if ssh -n "${ssh_opts[@]}" "$target_ssh" "bash -l -c 'ssh -n -o BatchMode=yes -o ConnectTimeout=8 $opt $pi_ssh true'" >/dev/null 2>&1; then
                found="$k"; worked=1; break
            fi
        done
        if [ "$worked" = 0 ]; then
            echo "error: $mac_name cannot ssh to $pi_ssh with a key. Split mode needs it (to restart the other machine's servers): ssh-copy-id $pi_ssh from $mac_name" >&2
            return 1
        fi
        [ -z "$found" ] || args+=(--key "$found")
    fi
    local quoted="" a
    for a in "${args[@]}" ${worker_opts[@]+"${worker_opts[@]}"}; do quoted="$quoted $(printf '%q' "$a")"; done
    ssh -n "${ssh_opts[@]}" "$target_ssh" "bash -l -c \"cd '$target_repo' && scripts/common/split.sh$quoted\""
}
