# Adding a client

OpenNotch knows nothing about any particular agent. A client is plugged in by
making it report state through `opennotch`, the CLI installed at
`~/.opennotch/bin/opennotch`. There are three ways in, cheapest first.

## 1. The client has event hooks with a JSON payload

Claude Code, Codex and Cursor all invoke a command per event with JSON on stdin.
`_lib/hook-adapter.sh` already speaks that shape, so a new client of this kind
is *only* an event mapping. Copy `claude-code/install.sh`, change the config
file it writes to, and map that client's event names:

```sh
map SessionStart     "--state idle --owner mytool"
map UserPromptSubmit "--state running --owner mytool"
map Stop             "--state done"
map SessionEnd       "--clear"
```

### Payload fields

Each is read with a fallback, because the next client along needed one:

| Wanted | Read from |
|---|---|
| session id | `conversation_id`, else `session_id` |
| directory | `cwd`, else `workspace_roots[0]` |
| liveness | `transcript_path` |
| subagent | `agent_id` — when set, the event is ignored |

`conversation_id` wins because Cursor sends `session_id` on only two of its
events and `conversation_id` on all of them; keying on the former would file one
conversation under two different sessions. Claude Code and Codex do not send
`conversation_id` at all, so nothing changes for them.

### File shape

Two shapes exist, and `merge-hooks.sh --style` picks one:

```jsonc
// nested (default) — Claude Code, Codex
{ "hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "..." } ] } ] } }
// flat — Cursor
{ "version": 1, "hooks": { "stop": [ { "type": "command", "command": "..." } ] } }
```

### Timeouts

`merge-hooks.sh --timeout <n>` writes the client's own unit. Claude Code, Codex
and Cursor count seconds; Gemini counts milliseconds. The default is 5, which is
right for the first three and would be five thousandths of a second for Gemini —
and a hook killed that fast is indistinguishable from a client that never fired.

### One event, several outcomes

Some clients report *how* a turn ended rather than firing a different event for
each way. `--state-map <field>:<value>=<state>,...` reads a payload field and
picks the state from it, falling back to `--state` for anything unlisted:

```sh
map stop "--state done --state-map status:completed=done,aborted=idle,error=error"
```

## 2. The client has hooks but a different payload

Skip `hook-adapter.sh` and call the CLI directly from your own adapter script:

```sh
opennotch report --source mytool --session "$MY_ID" --state running \
  --label "$(basename "$PWD")" --owner mytool --activity "$MY_LOG"
```

## 3. The client has no hooks at all

Wrap the process. This needs no integration from the tool whatsoever:

```sh
opennotch wrap --source mytool --label "nightly build" -- ./run-build.sh
```

`wrap` reports `running` for the lifetime of the command, then `done`, or
`error` if it exits non-zero, and passes the exit code through.

## States

| State | Meaning | Look |
|---|---|---|
| `idle` | registered, nothing happening | invisible |
| `running` | a turn is in flight | the client's mark, still, + elapsed |
| `waiting` | blocked on the human | amber pulse |
| `done` | finished | green check + duration |
| `error` | failed | red |

Repeating `running` is a heartbeat: the start time is kept, so the timer does
not reset. `done` and `error` compute the duration from it. `--if-state` makes
a report conditional, for events that also fire outside a turn.

## Staying visible after a crash

Pass `--owner <pattern>` (walks the process tree for a matching command) or
`--pid`. OpenNotch drops sessions whose process is gone, so a killed terminal
does not leave a spinner behind. `--activity <file>` gives a second signal: a
session whose file has not been touched for 30 minutes stops being shown, which
covers turns interrupted without a closing event.

## Branding

Optional. Gives the client a name and colour in the expanded panel:

```sh
opennotch source --id mytool --name "My Tool" --symbol "hammer" --accent "#7C5CFF"
```

`--symbol` is an SF Symbol name. This writes `~/.opennotch/sources.json`, which
the app reads at runtime — no rebuild needed.

For the client's own mark to stand beside the cutout while a turn runs, give it
vector artwork rather than an SF Symbol, by adding `path` (an SVG `d` attribute)
and `viewBox` to its entry in that file. The whole path grammar is supported,
elliptical arcs included — which matters, because most icon sets round their
corners with arcs. Claude Code, Codex and Cursor ship marks; a client without
one gets a plain outline instead.
