#!/bin/sh
# Generic adapter for clients that invoke a command per event with a JSON
# payload on stdin (Claude Code, Codex, and anything that copies that shape).
#
#   hook-adapter.sh --source <id> --state <state> [--if-state <state>]
#   hook-adapter.sh --source <id> --clear
#
# Recognised payload fields: session_id, cwd, transcript_path, agent_id.
# A client with a different payload does not need this file — it can call
# `opennotch report` directly. See adapters/README.md.
set -u

ON="${OPENNOTCH_BIN:-$(dirname "$0")/opennotch}"
[ -x "$ON" ] || exit 0

source='' state='' ifstate='' clear=0 owner=''
while [ $# -gt 0 ]; do
  case "$1" in
    --source)   source="${2:-}"; shift 2 ;;
    --state)    state="${2:-}"; shift 2 ;;
    --if-state) ifstate="${2:-}"; shift 2 ;;
    --owner)    owner="${2:-}"; shift 2 ;;
    --clear)    clear=1; shift ;;
    *) shift ;;
  esac
done
[ -n "$source" ] || exit 0

input=$(cat 2>/dev/null) || input=''
[ -n "$input" ] || exit 0

if command -v jq >/dev/null 2>&1; then
  fields=$(printf '%s' "$input" | jq -r '[.session_id // "", .cwd // "", .agent_id // "", .transcript_path // ""] | @tsv' 2>/dev/null) || fields=''
  sid=$(printf '%s' "$fields" | cut -f1)
  cwd=$(printf '%s' "$fields" | cut -f2)
  agent=$(printf '%s' "$fields" | cut -f3)
  activity=$(printf '%s' "$fields" | cut -f4)
else
  sid=$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  agent=$(printf '%s' "$input" | sed -n 's/.*"agent_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  activity=$(printf '%s' "$input" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi

[ -n "$sid" ] || exit 0
# A subagent finishing must never move the parent session's state.
[ -z "$agent" ] || exit 0

if [ "$clear" -eq 1 ]; then
  exec "$ON" clear --source "$source" --session "$sid"
fi
[ -n "$state" ] || exit 0

set -- report --source "$source" --session "$sid" --state "$state"
[ -n "$cwd" ] && set -- "$@" --cwd "$cwd"
[ -n "$activity" ] && set -- "$@" --activity "$activity"
[ -n "$ifstate" ] && set -- "$@" --if-state "$ifstate"
[ -n "$owner" ] && set -- "$@" --owner "$owner"

exec "$ON" "$@"
