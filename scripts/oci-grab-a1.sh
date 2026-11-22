#!/usr/bin/env bash
# Keeps trying to create an Always Free Ampere A1 instance until Oracle has capacity ("Out of host
# capacity" is the usual answer). Needs the OCI CLI:  brew install oci-cli && oci setup config
#
# 1. scripts/oci-grab-a1.sh --discover      lists your compartments, availability domains, VCN subnets, images
# 2. fill the SETTINGS below (or pass them as environment variables)
# 3. caffeinate -i scripts/oci-grab-a1.sh   runs until it succeeds (caffeinate: keeps the Mac awake)
#
# Free tier limit for A1: 4 OCPU + 24 GB RAM in total, across all your A1 instances, and 200 GB of boot volumes.
set -uo pipefail

# ============================== SETTINGS ==============================
: "${COMPARTMENT_ID:=ocid1.tenancy.oc1..aaaaaaaatlvqffdcmyxxejkwt2n3jn3td4cspod7tktljkteiidus5evg5ya}"   # the tenancy = root compartment
: "${SUBNET_ID:=ocid1.subnet.oc1.phx.aaaaaaaaxndz5k7su7arej4gmfue25mpizg43huq33q2yshjtljatvppwdfa}"   # "servers" 10.0.1.0/24, the PUBLIC subnet
: "${SSH_KEY_FILE:=$HOME/.ssh/id_c1.pub}"   # public key put on the instance (login: opc)
: "${DISPLAY_NAME:=game}"
: "${OCPUS:=1}"                  # A1.Flex: 1-4 on the free tier
: "${MEMORY_GB:=6}"              # 1-24 on the free tier (up to 6 GB per OCPU)
: "${BOOT_VOLUME_GB:=}"          # empty = the image default (~47 GB). A number = that size (50 minimum, 200 free in total)
: "${IMAGE_ID:=}"                # empty = the newest Oracle Linux 9 aarch64 image
: "${USER_DATA_FILE:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/oracle-cloud-init-game.sh}"   # cloud-init script ("" = none)
: "${AVAILABILITY_DOMAINS:=}"    # empty = try every AD of the region, one after the other; or "AD-1,AD-2" names from --discover
: "${RETRY_SECONDS:=60}"         # pause between rounds (be kind to the API: under 30 gets rate limited)
: "${ASSIGN_PUBLIC_IP:=true}"
SHAPE="VM.Standard.A1.Flex"
# ======================================================================

die() { echo "error: $*" >&2; exit 1; }
command -v oci >/dev/null 2>&1 || die "OCI CLI not found: brew install oci-cli, then oci setup config"
command -v jq >/dev/null 2>&1 || die "jq not found: brew install jq"

if [ "${1:-}" = "--discover" ]; then
    tenancy="$(awk -F= '/^tenancy/ {gsub(/ /,"",$2); print $2; exit}' ~/.oci/config)"
    comp="${COMPARTMENT_ID:-$tenancy}"
    echo "== compartment used: $comp"
    echo "== availability domains"; oci iam availability-domain list --compartment-id "$tenancy" --query 'data[].name' --output json | jq -r '.[]'
    echo "== subnets (prohibit-public-ip-on-vnic=false means public)"
    oci network subnet list --compartment-id "$comp" --all --output json | jq -r '.data[] | [."display-name", ."cidr-block", ."prohibit-public-ip-on-vnic", .id] | @tsv'
    echo "== newest Oracle Linux 9 aarch64 images"
    oci compute image list --compartment-id "$comp" --operating-system "Oracle Linux" --operating-system-version 9 --shape "$SHAPE" \
        --sort-by TIMECREATED --sort-order DESC --limit 3 --output json | jq -r '.data[] | [."display-name", .id] | @tsv'
    echo "== your sub-compartments (if any)"
    oci iam compartment list --compartment-id "$tenancy" --all --output json | jq -r '.data[] | [.name, .id] | @tsv'
    exit 0
fi

[ -n "$COMPARTMENT_ID" ] || die "set COMPARTMENT_ID (run --discover)"
[ -n "$SUBNET_ID" ] || die "set SUBNET_ID (run --discover)"
[ -f "$SSH_KEY_FILE" ] || die "SSH public key $SSH_KEY_FILE not found"
[ -z "$USER_DATA_FILE" ] || [ -f "$USER_DATA_FILE" ] || die "user data file $USER_DATA_FILE not found"

tenancy="$(awk -F= '/^tenancy/ {gsub(/ /,"",$2); print $2; exit}' ~/.oci/config)"
if [ -z "$IMAGE_ID" ]; then
    IMAGE_ID="$(oci compute image list --compartment-id "$COMPARTMENT_ID" --operating-system "Oracle Linux" --operating-system-version 9 \
        --shape "$SHAPE" --sort-by TIMECREATED --sort-order DESC --limit 1 --query 'data[0].id' --raw-output)" || die "can't find an image"
fi
if [ -n "$AVAILABILITY_DOMAINS" ]; then
    IFS=',' read -ra ADS <<<"$AVAILABILITY_DOMAINS"
else
    ADS=()
    while IFS= read -r line; do ADS+=("$line"); done < <(oci iam availability-domain list --compartment-id "$tenancy" --query 'data[].name' --output json | jq -r '.[]')
fi
[ "${#ADS[@]}" -gt 0 ] || die "no availability domains"

echo "image:  $IMAGE_ID"
echo "shape:  $SHAPE, $OCPUS OCPU, $MEMORY_GB GB, boot ${BOOT_VOLUME_GB:+${BOOT_VOLUME_GB} GB}${BOOT_VOLUME_GB:-default size}, name $DISPLAY_NAME"
echo "ADs:    ${ADS[*]}   retry every ${RETRY_SECONDS}s"

launch_args=(compute instance launch
    --compartment-id "$COMPARTMENT_ID" --shape "$SHAPE"
    --shape-config "{\"ocpus\": $OCPUS, \"memoryInGBs\": $MEMORY_GB}"
    --image-id "$IMAGE_ID" --subnet-id "$SUBNET_ID" --assign-public-ip "$ASSIGN_PUBLIC_IP"
    --display-name "$DISPLAY_NAME"
    --ssh-authorized-keys-file "$SSH_KEY_FILE"
    --wait-for-state RUNNING)
[ -z "$USER_DATA_FILE" ] || launch_args+=(--user-data-file "$USER_DATA_FILE")
[ -z "$BOOT_VOLUME_GB" ] || launch_args+=(--boot-volume-size-in-gbs "$BOOT_VOLUME_GB")

report_created() { # <instance id> <ad>
    printf '\a\nCREATED %s in %s\n' "$1" "$2"
    local ip
    ip="$(oci compute instance list-vnics --instance-id "$1" --query 'data[0]."public-ip"' --raw-output 2>/dev/null)"
    echo "public IP:  ${ip:-<none, see the console>}"
    echo "ssh:        ssh -i ${SSH_KEY_FILE%.pub} opc@${ip:-<ip>}"
    echo "the cloud-init script is running on it now: sudo tail -f /var/log/rysteria-init.log"
    # loud alarm at full volume (scripts/play-alarm.sh), ~5 minutes; ALARM=0 turns it off
    [ "${ALARM:-1}" = 0 ] || "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/play-alarm.sh"
}

# an instance of this name that exists (a launch that timed out may have worked anyway)
existing_instance() {
    oci compute instance list --compartment-id "$COMPARTMENT_ID" --display-name "$DISPLAY_NAME" --all --output json 2>/dev/null |
        jq -r '[.data[] | select(."lifecycle-state" != "TERMINATED" and ."lifecycle-state" != "TERMINATING")][0].id // empty'
}

attempt=0
while true; do
    for ad in "${ADS[@]}"; do
        attempt=$((attempt + 1))
        printf '[%s] try %d in %s ... ' "$(date +%H:%M:%S)" "$attempt" "$ad"
        out="$(oci "${launch_args[@]}" --availability-domain "$ad" 2>&1)"
        rc=$?
        if [ $rc -eq 0 ]; then
            report_created "$(echo "$out" | jq -r '.data.id')" "$ad"
            exit 0
        fi
        if echo "$out" | grep -qiE 'TooManyRequests|"status": 429'; then
            echo "rate limited, backing off"; sleep 120
        elif echo "$out" | grep -qiE 'out of (host )?capacity|OutOfHostCapacity|InternalError'; then
            echo "no capacity"
        elif echo "$out" | grep -qiE 'timed out|timeout|ConnectionError|Max retries|RemoteDisconnected|Remote end closed|ServiceUnavailable|"status": 50[0-9]|Temporary failure|Name or service not known'; then
            # network or server hiccup. The request may have reached Oracle and worked: look before trying again
            echo "network/server hiccup, checking whether it was created anyway"
            sleep 5
            found="$(existing_instance)"
            if [ -n "$found" ]; then report_created "$found" "$ad"; exit 0; fi
            sleep 20
        else
            echo "FAILED (not a capacity or network problem):"; echo "$out" | head -n 20; exit 1
        fi
        sleep 3
    done
    sleep "$RETRY_SECONDS"
done
