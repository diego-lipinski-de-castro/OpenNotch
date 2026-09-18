#!/bin/sh
# demo.sh — drive the notch through its states without running a real agent.
#
# Exists for comparing the three collapsed variants: switching between them is
# only meaningful if you can see every state on demand.
#
#   ./Tools/demo.sh running | waiting | done | error | many
#   ./Tools/demo.sh tour      walk through all of it, pausing on each
#   ./Tools/demo.sh clear     remove every demo session
set -u

cd "$(dirname "$0")/.."
ON="./bin/opennotch"
[ -x "$ON" ] || { echo "demo: $ON not found or not executable" >&2; exit 1; }

# Two clients so the multi-session and badge paths get exercised.
S1="--source claude-code --session demo-1 --label opennotch --cwd $HOME/Development/OpenNotch"
S2="--source claude-code --session demo-2 --label api --cwd $HOME/Development/acme/services/api"
S3="--source codex --session demo-3 --label web --cwd $HOME/Development/acme/apps/web"

say() { printf '\n\033[1m%s\033[0m %s\n' "$1" "$2"; }
pause() { sleep "${1:-6}"; }

clear_all() {
  $ON clear --source claude-code --session demo-1 2>/dev/null
  $ON clear --source claude-code --session demo-2 2>/dev/null
  $ON clear --source codex --session demo-3 2>/dev/null
}

# done and error compute their duration from the previous running report, so a
# turn has to actually start before it can finish.
finish() {
  # shellcheck disable=SC2086
  $ON report $1 --state running
  sleep "${3:-3}"
  # shellcheck disable=SC2086
  $ON report $1 --state "$2"
}

case "${1:-tour}" in
  running) clear_all; $ON report $S1 --state running ;;
  waiting) clear_all; $ON report $S1 --state running; sleep 2; $ON report $S1 --state waiting ;;
  done)    clear_all; finish "$S1" done ;;
  error)   clear_all; finish "$S1" error ;;

  many)
    clear_all
    $ON report $S1 --state running
    $ON report $S2 --state running; sleep 2; $ON report $S2 --state waiting
    $ON report $S3 --state running
    ;;

  tour)
    clear_all
    say "running" "one turn in flight — this is the state you see most"
    $ON report $S1 --state running
    pause 8

    say "waiting" "blocked on you — the loudest thing the notch ever does"
    $ON report $S1 --state waiting
    pause 8

    say "running" "back in flight"
    $ON report $S1 --state running
    pause 6

    say "done" "finished, with the turn duration; fades after 9s"
    $ON report $S1 --state done
    pause 8

    say "error" "failed"
    finish "$S1" error 2
    pause 8

    say "many" "three sessions, two clients — hover for the panel"
    $ON report $S1 --state running
    $ON report $S2 --state running; sleep 2; $ON report $S2 --state waiting
    $ON report $S3 --state running
    pause 14

    say "clear" "done"
    clear_all
    ;;

  clear) clear_all ;;
  *) echo "demo: unknown state '$1'" >&2; exit 2 ;;
esac
