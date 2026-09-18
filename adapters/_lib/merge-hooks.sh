#!/bin/sh
# Add or remove an OpenNotch entry in a Claude-Code-shaped hooks JSON file.
# Both ~/.claude/settings.json and ~/.codex/hooks.json use this structure:
#   { "hooks": { "<Event>": [ { "hooks": [ {type,command,timeout} ] } ] } }
#
#   merge-hooks.sh --file <path> --event <Event> --command <cmd>
#   merge-hooks.sh --file <path> --remove <substring>
#
# Always writes through a temp file that is validated first. Never redirect jq
# straight onto the target: the shell truncates it before jq can fail.
set -eu

command -v jq >/dev/null 2>&1 || { echo "opennotch: jq is required" >&2; exit 1; }

file=''; event=''; command_=''; remove=''
while [ $# -gt 0 ]; do
  case "$1" in
    --file)    file="${2:-}"; shift 2 ;;
    --event)   event="${2:-}"; shift 2 ;;
    --command) command_="${2:-}"; shift 2 ;;
    --remove)  remove="${2:-}"; shift 2 ;;
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
  jq --arg needle "$remove" '
    def strip($n):
      map(.hooks |= map(select((.command // "") | contains($n) | not)))
      | map(select(((.hooks // []) | length) > 0));
    if has("hooks") then
      .hooks |= (with_entries(.value |= strip($needle))
                 | with_entries(select((.value | length) > 0)))
    else . end
    | if (.hooks // {}) == {} then del(.hooks) else . end
  ' "$file" > "$tmp"
else
  [ -n "$event" ] && [ -n "$command_" ] || { echo "merge-hooks: --event and --command are required" >&2; exit 2; }
  jq --arg ev "$event" --arg cmd "$command_" '
    .hooks = (.hooks // {})
    | .hooks[$ev] = ((.hooks[$ev] // [])
        | if any(.[]; (.hooks // []) | any((.command // "") == $cmd)) then .
          else . + [{hooks: [{type: "command", command: $cmd, timeout: 5}]}] end)
  ' "$file" > "$tmp"
fi

jq empty "$tmp" 2>/dev/null || { echo "merge-hooks: refusing to write invalid JSON" >&2; exit 1; }
[ -s "$tmp" ] || { echo "merge-hooks: refusing to write empty file" >&2; exit 1; }
mv -f "$tmp" "$file"
