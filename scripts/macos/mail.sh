#!/usr/bin/env bash
# macos: the mail server (setup, start, stop, dns, status).
# The work is done by scripts/common/mail.sh; see the comments there.
exec "$(dirname "${BASH_SOURCE[0]}")/../common/mail.sh" "$@"
