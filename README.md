# OpenNotch

Turns the MacBook notch into a status light for coding agents: whether a turn is
**running**, **waiting for you**, or **finished** — across every session of every
client you have installed.

The notch's own pixels are a physical cutout and cannot be drawn into, so the app
parks a borderless always-on-top panel over it. Idle, that panel is exactly the
size of the cutout and painted black, so it is invisible. When something happens
it grows wings beside the cutout and a status bar underneath, which reads as the
notch itself lighting up. Hover it for a panel listing every session, whatever
needs you first.

```
   ◜ client mark ◝              ◜ elapsed ◝
      ( ✳  ▓▓▓▓▓ the notch ▓▓▓▓▓  1:38 )
```

## States

| State | Look |
|---|---|
| Idle | nothing — the panel matches the cutout exactly |
| Running | the client's own mark, breathing, + live elapsed time |
| Waiting for you | amber pulsing dot |
| Finished | green check + how long the turn took, fades after 9s |
| Failed | red, with the duration |

While a turn runs, the glyph beside the cutout is the client's own mark — the
Claude symbol for Claude Code — in the client's colour, and it breathes: each
arm of the mark reaches out and draws back by about a point, on a slow
two-and-a-half-second cycle, while the mark keeps its place, its size and its
colour. Two waves wrapped around it turn against each other, so the arms rise
and fall in an order that never settles into a direction — there is nothing
going round for the eye to follow. Running is the normal case, and the normal
case has to be something you can sit beside all day.

Nothing in the product rotates. **Waiting** keeps every louder register to
itself: it takes the whole glyph up and down in size and down to half opacity on
every beat, with one extra beat at the moment it starts, where running never
changes size, position or opacity at all. Motion that asks for you still means
waiting and nothing else.

In the hover panel a running turn gets no badge at all: the row already names
the client on the left and shows a clock on the right, and running is the
ordinary case. A badge is for the exceptions. The mark in the row's leading
column breathes for exactly as long as that session's turn does, the same way
the collapsed one does — and when the turn finishes it does not cut off where it
stood, it eases back to the mark as drawn over about half a second and then
stops being redrawn at all. Marks that are not breathing cost nothing.

Identity and state never share a slot. In the hover panel the leading column is
always the client's mark and the trailing column is always the state, so the one
moment you most need to know *which* client is asking for something is not the
moment the client stops being named.

Several sessions at once collapse to a count; hover for the list, sorted so the
sessions blocked on you are on top. Each row carries the session's name and the
directory it is working in, because two sessions in folders called `api` are
otherwise indistinguishable. The client is named on the right when more than one
is running.

## Install

```sh
./install.sh          # app + CLI + an adapter for every client found
./install.sh --uninstall
```

Adapters are only installed for clients that exist on the machine. Everything is
idempotent, every config file is backed up first, and no existing hooks are
touched.

## Clients

OpenNotch knows nothing about any particular agent. State arrives through one
CLI, `~/.opennotch/bin/opennotch`, and a client is plugged in by mapping its
events onto five states.

| Client | Mechanism | Notes |
|---|---|---|
| Claude Code | hooks in `~/.claude/settings.json` | `Notification` is the "waiting" signal |
| Codex | hooks in `~/.codex/hooks.json` | has `PermissionRequest` and `Interrupt`, so it is more precise |
| Cursor | hooks in `~/.cursor/hooks.json` | no event means "blocked on you", so it never shows amber |
| Gemini | hooks in `~/.gemini/settings.json` | `Notification` is the "waiting" signal, as in Claude Code |
| anything else | `opennotch wrap -- <cmd>` | no integration needed from the tool |

Cursor is the one client with a gap. Its hook vocabulary has nothing that means
a human is being waited on: `beforeShellExecution` looks like it does and fires
before Cursor has decided whether to ask, so on an auto-approving setup it would
turn the notch amber on every command the agent ran. Amber is the loudest thing
this product does and the only one that asks for you, so it is left unspent
rather than spent wrongly. Cursor sessions show running, done and error.

Adding one is a directory under `adapters/` — see **[adapters/README.md](adapters/README.md)**.
The shortest version:

```sh
# a tool with JSON hooks: just map its events
map UserPromptSubmit "--state running --owner mytool"
map Stop             "--state done"

# a tool with nothing: wrap the process
opennotch wrap --source mytool --label "nightly build" -- ./run-build.sh
```

Unregistered clients still work — they get a name derived from their id and a
generic badge. Registering is one optional line:

```sh
opennotch source --id mytool --name "My Tool" --symbol "hammer" --accent "#7C5CFF"
```

A client can supply its own mark as SVG path data instead of an SF Symbol, which
is what makes it the running glyph rather than just a badge. Add `path` and
`viewBox` to its entry in `~/.opennotch/sources.json`:

```json
{ "sources": { "mytool": { "name": "My Tool", "accent": "#7C5CFF",
                           "path": "M50 0 L100 100 L0 100 Z",
                           "viewBox": "0 0 100 100" } } }
```

## How it works

```
client event ──> adapter ──> opennotch report ──> ~/.opennotch/sessions/<source>.<id>.json
                                                            │
                                              DispatchSource watch
                                                            ▼
                                                    OpenNotch.app
```

One small JSON file per session, namespaced by client so two clients cannot
collide. The app watches the directory and re-reads on change.

Sessions do not get stuck: each file records the owning process, so a killed
terminal is dropped rather than spinning forever, and a session whose activity
file has not been touched for 30 minutes stops being shown — which covers turns
interrupted without a closing event. Subagent events are ignored, so a subagent
finishing never marks the whole session done.

## Layout

```
~/.opennotch/
  bin/opennotch           the CLI every client reports through
  bin/hook-adapter.sh     shared adapter for JSON-hook clients
  sessions/*.json         live state, one file per session
  sources.json            optional per-client name/icon/colour
```

## Notes

- `OPENNOTCH_DIR` relocates all of the above (handy for testing).
- `OPENNOTCH_DEBUG=1` logs hover polling and window placement.
- `Tools/demo.sh tour` walks the notch through every state without an agent.
- On a display without a cutout the idle panel is an invisible hover strip at
  the top centre, and the active state is a black bar hanging from the top with
  the same silhouette.
- `Tools/render-states.sh` draws every state to PNGs without putting anything on
  screen, which is how the shape and the panel get looked at: it compiles the
  app's own views, so it is the real thing rather than a mock, and it works on a
  machine whose display is asleep.
- Tunables: `NotchMetrics.swift` (sizes), `Palette.swift` (colours, authored in
  OKLCH), `Motion.swift` (every animation in the product), `SessionStore.doneLinger`
  / `.staleAfter` (timings).
