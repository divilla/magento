#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
integration_lock
command -v apih >/dev/null
integration_reset
printf 'Running APIHydra against http://localhost:8081 (default parallelism 1)...\n'
apih ./apih-tests
