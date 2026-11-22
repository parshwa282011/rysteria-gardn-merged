#!/usr/bin/env bash
# Waits until the grabber log says CREATED, then plays a loud alarm at FULL system volume (repeats until stopped).
# Usage: scripts/alarm-on-created.sh <grabber log file>      Stop it: pkill -f alarm-on-created.sh ; pkill afplay
log="${1:?usage: alarm-on-created.sh <grab.log>}"
# line by line (BSD grep -q waits for a full buffer on a pipe and would never fire)
while IFS= read -r line; do
    case "$line" in CREATED*) break ;; esac
done < <(tail -n +1 -F "$log" 2>/dev/null)
pkill -f "tail -n +1 -F $log" 2>/dev/null
msg="$(grep -h 'CREATED\|public IP' "$log" | tr '\n' ' ')"
"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/play-alarm.sh" "$msg"
