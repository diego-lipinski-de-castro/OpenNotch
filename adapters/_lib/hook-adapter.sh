#!/bin/sh
# Generic adapter for clients that invoke a command per event with a JSON
# payload on stdin (Claude Code, Codex, and anything that copies that shape).
#
#   hook-adapter.sh --source <id> --state <state> [--if-state <state>]
#   hook-adapter.sh --source <id> --state <state> --state-map <field>:<v>=<state>,...
#   hook-adapter.sh --source <id> --clear
#
# Payload fields, each with the fallback the next client along needed:
#   id        conversation_id, else session_id
#   cwd       cwd, else workspace_roots[0]
#   activity  transcript_path
#   subagent  agent_id
#
# conversation_id is preferred because Cursor only sends session_id on two of
# its events and conversation_id on all of them — keying on session_id there
# would file the same conversation under two different sessions. Claude Code and
# Codex do not send conversation_id at all, so they are unaffected.
#
# A client with a payload this cannot describe does not need this file — it can
# call `opennotch report` directly. See adapters/README.md.
set -u

ON="${OPENNOTCH_BIN:-$(dirname "$0")/opennotch}"
[ -x "$ON" ] || exit 0

source='' state='' ifstate='' clear=0 owner='' statemap=''
while [ $# -gt 0 ]; do
  case "$1" in
    --source)    source="${2:-}"; shift 2 ;;
    --state)     state="${2:-}"; shift 2 ;;
    --if-state)  ifstate="${2:-}"; shift 2 ;;
    --owner)     owner="${2:-}"; shift 2 ;;
    --state-map) statemap="${2:-}"; shift 2 ;;
    --clear)     clear=1; shift ;;
    *) shift ;;
  esac
done
[ -n "$source" ] || exit 0

input=$(cat 2>/dev/null) || input=''
[ -n "$input" ] || exit 0

# One string field out of the payload, by name.
json_str() {
  if [ "$HAVE_JQ" -eq 1 ]; then
    printf '%s' "$input" | jq -r --arg k "$1" '.[$k] // "" | tostring' 2>/dev/null
  else
    printf '%s' "$input" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
  fi
}

HAVE_JQ=0
command -v jq >/dev/null 2>&1 && HAVE_JQ=1

if [ "$HAVE_JQ" -eq 1 ]; then
  fields=$(printf '%s' "$input" | jq -r '[
      (.conversation_id // .session_id // ""),
      (.cwd // (.workspace_roots[0]? // "")),
      (.agent_id // ""),
      (.transcript_path // "")
    ] | @tsv' 2>/dev/null) || fields=''
  sid=$(printf '%s' "$fields" | cut -f1)
  cwd=$(printf '%s' "$fields" | cut -f2)
  agent=$(printf '%s' "$fields" | cut -f3)
  activity=$(printf '%s' "$fields" | cut -f4)
else
  sid=$(json_str conversation_id)
  [ -n "$sid" ] || sid=$(json_str session_id)
  cwd=$(json_str cwd)
  [ -n "$cwd" ] || cwd=$(printf '%s' "$input" | sed -n 's/.*"workspace_roots"[[:space:]]*:[[:space:]]*\[[[:space:]]*"\([^"]*\)".*/\1/p')
  agent=$(json_str agent_id)
  activity=$(json_str transcript_path)
fi

[ -n "$sid" ] || exit 0
# A subagent finishing must never move the parent session's state.
[ -z "$agent" ] || exit 0

if [ "$clear" -eq 1 ]; then
  exec "$ON" clear --source "$source" --session "$sid"
fi
[ -n "$state" ] || exit 0

# One event, several outcomes: Cursor's `stop` carries a status saying whether
# the turn finished, failed, or was interrupted, and those are three different
# things to show. Anything unlisted falls through to --state.
if [ -n "$statemap" ]; then
  field=${statemap%%:*}
  value=$(json_str "$field")
  if [ -n "$value" ]; then
    OLDIFS=$IFS; IFS=,
    for pair in ${statemap#*:}; do
      case "$pair" in
        "$value="*) state=${pair#*=} ;;
      esac
    done
    IFS=$OLDIFS
  fi
fi

set -- report --source "$source" --session "$sid" --state "$state"
[ -n "$cwd" ] && set -- "$@" --cwd "$cwd"
[ -n "$activity" ] && set -- "$@" --activity "$activity"
[ -n "$ifstate" ] && set -- "$@" --if-state "$ifstate"
[ -n "$owner" ] && set -- "$@" --owner "$owner"

exec "$ON" "$@"
