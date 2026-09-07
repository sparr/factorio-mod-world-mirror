#!/usr/bin/env bash
# Unit tier: lib/ against no game at all, in the same Lua 5.2 that Factorio runs.
# Anything about what the engine really does belongs in test/ft, which drives a
# real game; see test/ft/README.md.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

if [[ ! -x .luarocks/bin/busted ]]; then
    echo "busted is not installed. Run:" >&2
    echo "  luarocks --lua-version 5.2 --tree .luarocks install busted" >&2
    exit 2
fi

eval "$(luarocks --lua-version 5.2 --tree .luarocks path)"
exec .luarocks/bin/busted "$@"
