# Adding a client

OpenNotch knows nothing about any particular agent. A client is plugged in by
making it report state through `opennotch`, the CLI installed at
`~/.opennotch/bin/opennotch`. There are three ways in, cheapest first.

## 1. The client has event hooks with a JSON payload

Claude Code and Codex both invoke a command per event with JSON on stdin
containing `session_id`, `cwd` and `transcript_path`. `_lib/hook-adapter.sh`
already speaks that shape, so a new client of this kind is *only* an event
mapping. Copy `claude-code/install.sh`, change the config file it writes to,
and map that client's event names:

```sh
map SessionStart     "--state idle --owner mytool"
map UserPromptSubmit "--state running --owner mytool"
map Stop             "--state done"
map SessionEnd       "--clear"
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
| `running` | a turn is in flight | the client's mark, turning, + elapsed |
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

For the client's mark to *replace the spinner* while a turn runs, give it vector
artwork rather than an SF Symbol, by adding `path` (an SVG `d` attribute) and
`viewBox` to its entry in that file. Everything except elliptical arcs is
supported. Claude Code ships with one; anything else falls back to the spinner.
