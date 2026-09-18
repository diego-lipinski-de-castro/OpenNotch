#!/bin/sh
# Add or remove an OpenNotch entry in a hooks JSON file, in either of the two
# shapes the clients use.
#
#   nested (default) — Claude Code, Codex:
#     { "hooks": { "<Event>": [ { "hooks": [ {type,command,timeout} ] } ] } }
#   flat — Cursor:
#     { "version": 1, "hooks": { "<event>": [ {type,command,timeout} ] } }
#
#   merge-hooks.sh --file <path> [--style nested|flat] [--timeout <n>] --event <Event> --command <cmd>
#   merge-hooks.sh --file <path> [--style nested|flat] --remove <substring>
#
# Always writes through a temp file that is validated first. Never redirect jq
# straight onto the target: the shell truncates it before jq can fail.
set -eu

command -v jq >/dev/null 2>&1 || { echo "opennotch: jq is required" >&2; exit 1; }

# Seconds for Claude Code, Codex and Cursor; milliseconds for Gemini. There is
# no portable unit, so the caller states it — 5 meaning milliseconds would kill
# the hook before it could report anything, and it would look like the client
# was simply never firing.
file=''; event=''; command_=''; remove=''; style='nested'; timeout=5
while [ $# -gt 0 ]; do
  case "$1" in
    --file)    file="${2:-}"; shift 2 ;;
    --event)   event="${2:-}"; shift 2 ;;
    --command) command_="${2:-}"; shift 2 ;;
    --remove)  remove="${2:-}"; shift 2 ;;
    --style)   style="${2:-}"; shift 2 ;;
    --timeout) timeout="${2:-}"; shift 2 ;;
    *) echo "merge-hooks: unknown option $1" >&2; exit 2 ;;
  esac
done
[ -n "$file" ] || { echo "merge-hooks: --file is required" >&2; exit 2; }

mkdir -p "$(dirname "$file")"
if [ ! -s "$file" ]; then printf '{}\n' > "$file"; fi
jq empty "$file" 2>/dev/null || { echo "merge-hooks: $file is not valid JSON" >&2; exit 1; }

tmp="$file.opennotch.$$"
trap 'rm -f "$tmp"' EXIT

if [ -n "$remove" ]; then
  jq --arg needle "$remove" --arg style "$style" '
    def stripNested($n):
      map(.hooks |= map(select((.command // "") | contains($n) | not)))
      | map(select(((.hooks // []) | length) > 0));
    def stripFlat($n):
      map(select((.command // "") | contains($n) | not));
    if has("hooks") then
      .hooks |= (with_entries(.value |= (if $style == "flat"
                                         then stripFlat($needle)
                                         else stripNested($needle) end))
                 | with_entries(select((.value | length) > 0)))
    else . end
    | if (.hooks // {}) == {} then del(.hooks) else . end
  ' "$file" > "$tmp"
elif [ "$style" = "flat" ]; then
  [ -n "$event" ] && [ -n "$command_" ] || { echo "merge-hooks: --event and --command are required" >&2; exit 2; }
  jq --arg ev "$event" --arg cmd "$command_" --argjson t "$timeout" '
    .version = 1
    | .hooks = (.hooks // {})
    | .hooks[$ev] = ((.hooks[$ev] // [])
        | if any(.[]; (.command // "") == $cmd) then .
          else . + [{type: "command", command: $cmd, timeout: $t}] end)
  ' "$file" > "$tmp"
else
  [ -n "$event" ] && [ -n "$command_" ] || { echo "merge-hooks: --event and --command are required" >&2; exit 2; }
  jq --arg ev "$event" --arg cmd "$command_" --argjson t "$timeout" '
    .hooks = (.hooks // {})
    | .hooks[$ev] = ((.hooks[$ev] // [])
        | if any(.[]; (.hooks // []) | any((.command // "") == $cmd)) then .
          else . + [{hooks: [{type: "command", command: $cmd, timeout: $t}]}] end)
  ' "$file" > "$tmp"
fi

jq empty "$tmp" 2>/dev/null || { echo "merge-hooks: refusing to write invalid JSON" >&2; exit 1; }
[ -s "$tmp" ] || { echo "merge-hooks: refusing to write empty file" >&2; exit 1; }
mv -f "$tmp" "$file"
