#!/bin/bash

# Source shared utilities if needed
if [ -f "$(dirname "$0")/lib/utils.sh" ]; then
  source "$(dirname "$0")/lib/utils.sh"
fi

show_help() {
  cat <<EOF
Premise CLI - Developer toolkit for Premise Health

Usage:
  premise <command> [options]

Commands:
  stale      Find and report stale branches in repos
  clone      Clone repos by group/subgroup, preserving hierarchy

Run 'premise <command> --help' for command-specific options.
EOF
}

COMMAND="$1"
shift

case "$COMMAND" in
  stale)
    exec "$(dirname "$0")/stale.sh" "$@"
    ;;
  clone)
    exec "$(dirname "$0")/clone.sh" "$@"
    ;;
  ""|help|-h|--help)
    show_help
    ;;
  *)
    echo "Unknown command: $COMMAND"
    show_help
    exit 1
    ;;
esac
