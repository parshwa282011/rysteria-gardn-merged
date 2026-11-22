#!/usr/bin/env bash
# Plays a loud alarm at FULL system volume for about 5 minutes (re-sets the volume on every loop).
# Stop: pkill -f play-alarm.sh ; pkill afplay
osascript -e "display notification \"${1:-OCI instance created}\" with title \"OCI instance CREATED\" sound name \"Sosumi\"" >/dev/null 2>&1
for i in $(seq 1 150); do
    osascript -e 'set volume output muted false' -e 'set volume output volume 100' >/dev/null 2>&1
    afplay -v 2 /System/Library/Sounds/Sosumi.aiff
    afplay -v 2 /System/Library/Sounds/Funk.aiff
done
