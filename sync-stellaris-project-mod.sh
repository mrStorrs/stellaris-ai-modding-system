#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  cat <<'EOF'
Usage: sync-stellaris-project-mod.sh modFolder

Registers one project-backed Stellaris mod, enables it in the active playset,
and places it immediately after any declared dependencies.
EOF
  exit 1
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  cat <<'EOF'
Usage: sync-stellaris-project-mod.sh modFolder

Registers one project-backed Stellaris mod, enables it in the active playset,
and places it immediately after any declared dependencies.
EOF
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

SOURCE_ROOT="$SCRIPT_DIR" \
MOD_NAME="$1" \
"$SCRIPT_DIR/sync-stellaris-project-mods.sh"
