---
name: OpenNotch
description: A status light for coding agents, drawn into the MacBook notch.
colors:
  body: "#000000"
  ink: "oklch(0.97 0.006 250)"
  ink-primary: "#E6E9ED"
  ink-secondary: "#B3B6B8"
  ink-tertiary: "#797B7D"
  ink-rule: "#131414"
  state-waiting: "oklch(0.82 0.16 80)"
  state-done: "oklch(0.7 0.13 152)"
  state-error: "oklch(0.62 0.2 27)"
  state-running: "oklch(0.74 0.028 250)"
  state-idle: "oklch(0.55 0.008 250)"
  accent-claude-code: "#D97757"
  accent-codex: "#10A37F"
typography:
  title:
    fontFamily: "SF Pro Text, -apple-system, system-ui, sans-serif"
    fontSize: "12.5pt"
    fontWeight: 500
  body:
    fontFamily: "SF Pro Text, -apple-system, system-ui, sans-serif"
    fontSize: "12pt"
    fontWeight: 400
  label:
    fontFamily: "SF Pro Text, -apple-system, system-ui, sans-serif"
    fontSize: "11pt"
    fontWeight: 500
    fontFeature: "tnum"
  caption:
    fontFamily: "SF Pro Text, -apple-system, system-ui, sans-serif"
    fontSize: "10pt"
    fontWeight: 400
  micro:
    fontFamily: "SF Pro Rounded, -apple-system, system-ui, sans-serif"
    fontSize: "9pt"
    fontWeight: 500
    fontFeature: "tnum"
rounded:
  flare-active: "7px"
  flare-expanded: "10px"
  lip-active: "11px"
  lip-expanded: "22px"
spacing:
  hairline: "1px"
  lip: "6px"
  row: "9px"
  control: "10px"
  panel: "12px"
  panel-inset: "16px"
  wing: "30px"
components:
  notch-collapsed:
    backgroundColor: "{colors.body}"
    rounded: "{rounded.lip-active}"
    height: "38px"
  panel:
    backgroundColor: "{colors.body}"
    rounded: "{rounded.lip-expanded}"
    width: "424px"
    padding: "0 16px 12px"
  session-row:
    height: "42px"
    textColor: "{colors.ink-primary}"
    typography: "{typography.title}"
  session-row-location:
    textColor: "{colors.ink-tertiary}"
    typography: "{typography.caption}"
  row-detail-running:
    textColor: "{colors.state-running}"
    typography: "{typography.label}"
  row-detail-waiting:
    textColor: "{colors.state-waiting}"
    typography: "{typography.label}"
  row-detail-done:
    textColor: "{colors.state-done}"
    typography: "{typography.label}"
  row-detail-error:
    textColor: "{colors.state-error}"
    typography: "{typography.label}"
  hairline:
    backgroundColor: "{colors.ink-rule}"
    height: "1px"
  footer-control:
    textColor: "{colors.ink-tertiary}"
    typography: "{typography.caption}"
---

# Design System: OpenNotch

## 1. Overview

**Creative North Star: "The Status Light"**

OpenNotch is an appliance, not an app. You learn what amber means once, and after
that you never read the interface again: you catch it at the edge of vision and
already know. Every decision follows from that. A status light that asks to be
studied has failed, so the system is built to be legible at a glance and
forgettable the rest of the time.

The surface is a borderless panel parked over the MacBook's physical cutout. At
rest it is exactly cutout-sized and painted pure black, which makes it invisible:
the design is literally nothing for the overwhelming majority of its life. When
something happens it grows wings beside the cutout and a shallow lip underneath,
so the hardware appears to widen. Hovering opens a 424pt panel listing every live
session. That panel is a menu, not a dashboard, and it is sized to be closed again
immediately.

This system rejects the visual vocabulary of the category it lives in. No gradient
auras, no bloom, no shimmer, no purple-blue "intelligence" glow. No cards, badges,
pills, or drop shadows. No bounce, no overshoot, no mascot. Those are all ways of
announcing that software is present, and the entire value here depends on the
opposite claim: that nothing was installed, and the notch simply gained a
behaviour.

**Key Characteristics:**

- Invisible at rest; the idle state draws zero pixels the user can perceive.
- Pure black on exactly one surface, tinted neutrals everywhere else.
- Every state readable without color, by silhouette and by lightness order.
- A type scale spanning 3.5pt, with hierarchy carried by opacity instead of size.
- Zero shadows, zero blur, zero translucency, anywhere in the product.
- The system's own type, easing, and accessibility settings, inherited wholesale.

## 2. Colors

A near-monochrome surface interrupted by one of four instrument colors, each of
which means exactly one thing. The palette is authored in OKLCH and converted to
sRGB at runtime, because lightness is the channel doing the real work here and
lightness is the one thing hex does not let you control.

### Primary

- **Signal Amber** (`{colors.state-waiting}`, renders `#FAB72A`): a turn is blocked
  on a human. The loudest thing the product can do, and the only color permitted to
  dominate a surface. It is the highest-lightness value in the palette on purpose:
  amber outranks everything.

### Secondary

- **Clear Green** (`{colors.state-done}`, renders `#58B575`): a turn finished. Shown
  with a duration, then retired after 9 seconds. Terminal, not celebratory.
- **Fault Red** (`{colors.state-error}`, renders `#E6443D`): a turn failed. The
  darkest state color, so it reads as weight rather than alarm.

### Tertiary

Client identity, never state. These are supplied by the clients themselves through
`sources.json` and are the only colors in the system OpenNotch does not choose.

- **Claude Terracotta** (`{colors.accent-claude-code}`): the Claude Code mark.
- **Codex Green** (`{colors.accent-codex}`): the Codex badge.

### Neutral

- **The Body** (`{colors.body}`): the panel itself. Pure, untinted black.
- **Standby Grey** (`{colors.state-running}`, renders `#9EADBC`): a turn in flight.
  Deliberately near-achromatic, because running is the normal case and does not
  deserve a color.
- **Ink** (`{colors.ink}`): the single text tint, hue 250 at chroma 0.006. Never
  used directly. It is composited over the body at four fixed opacities, which are
  the only text colors in the product: `{colors.ink-primary}` at 95% for session
  names, `{colors.ink-secondary}` at 74% for the panel headline,
  `{colors.ink-tertiary}` at 50% for everything supporting, and
  `{colors.ink-rule}` at 8% for separators.
- **Idle Grey** (`{colors.state-idle}`): a registered session doing nothing.

### Named Rules

**The Lightness Ladder Rule.** States are ordered by OKLCH lightness, never by hue:
waiting 0.82, running 0.74, done 0.70, error 0.62. A user with deuteranopia or
protanopia loses the hues and keeps the order. Any new state must be inserted into
the ladder at a lightness that does not collide with its neighbours, and adding one
that merely picks a free hue is prohibited.

**The One Black Rule.** `#000000` is permitted on exactly one surface: the panel
body, because it has to be indistinguishable from a hole in the display. Every
other neutral is tinted toward hue 250. Using untinted black or white anywhere else
is forbidden.

**The Ink Floor Rule.** No text may fall below 4.5:1 against the body. In practice
that means no opacity under 0.50, measured, not estimated. The tertiary role sits
at 0.50 and measures 4.93:1; 0.45 measures 4.13:1 and fails. When Increase Contrast
is on, the whole ladder rises rather than a single role being patched.

## 3. Typography

**Display Font:** none. The product has no display type and never will.
**Body Font:** SF Pro Text, via the system font stack.
**Label/Mono Font:** SF Pro Rounded for numerals in the collapsed indicator; SF Pro
Text with tabular figures everywhere else.

**Character:** Entirely inherited. The product uses the system face at system
weights and adds nothing of its own, because a recognisable typeface would be an
authorship signature and the whole illusion depends on there being none.

### Hierarchy

The full range is 9pt to 12.5pt. This is a 424pt panel that exists to be read in
under a second, so a conventional type scale would be absurd here; there is no room
for a 1.25 ratio and nothing that would benefit from one.

- **Title** (500 weight, 12.5pt): the session name. The largest type in the product.
- **Body** (400 weight, 12pt): the empty state, and the only running prose.
- **Label** (500 weight, 11pt, tabular): the panel headline, and each row's timing
  column. Tabular figures are mandatory because this text ticks once a second.
- **Caption** (400 weight, 10pt): the directory line under each session name, and
  the footer controls.
- **Micro** (500 weight, 9pt to 9.5pt, rounded, tabular): the client name in a row,
  and the elapsed time beside the cutout. SF Pro Rounded here only, matching the
  system's own treatment of small numerals in the menu bar.

### Named Rules

**The Opacity Hierarchy Rule.** With 3.5pt between the smallest and largest type,
size cannot carry hierarchy and must not be asked to. Rank is expressed through the
ink ladder: primary, secondary, tertiary. Reaching for a larger point size to make
something more important is the wrong instrument; drop everything around it a rung
instead.

**The Ticking Digit Rule.** Any number that updates on a timer is set with tabular
figures. A timer whose width changes as it counts is the single most obvious tell
that a piece of UI was not made by the platform vendor.

## 4. Elevation

Physical, not simulated. The panel sets `hasShadow = false` and there is no
`box-shadow`, no blur, no vibrancy, and no material anywhere in the product. This
is not minimalism as a preference; it is a consequence of what the thing imitates.
A shadow would prove the panel is a window sitting on top of the screen, which is
precisely the illusion being defended. The notch casts no shadow, so neither does
this.

Depth is carried entirely by the silhouette. Three geometric moves do the work of
an elevation scale: the outward flare at the top corners (`{rounded.flare-active}`
collapsed, `{rounded.flare-expanded}` expanded), the corner radius at the bottom
(`{rounded.lip-active}` collapsed, `{rounded.lip-expanded}` expanded), and the
depth of the lip below the cutout (`{spacing.lip}`). Growing the flare and the
radius together is what reads as the hardware widening rather than a rectangle
appearing underneath it.

### Named Rules

**The No-Shadow Rule.** Shadows, glows, blurs, and materials are forbidden
throughout, including on hover and focus. If a surface needs separating from
another surface, use a 1px hairline at `{colors.ink-rule}` or nothing at all.

**The Seam Rule.** Every geometry change is judged by one test: does the panel
still read as the notch itself, or as a rectangle stuck underneath it? When a
feature and the seam conflict, the seam wins.

## 5. Components

A menu, not a dashboard. Rows and hairlines, aligned to a single baseline grid, in
the vocabulary AppKit would have used. Cards, badges, pills, and containers are
prohibited outright: a 424pt panel has no room for chrome, and chrome is the
loudest way to announce that this was not shipped by the platform.

### The Notch Silhouette (signature component)

The defining element, and the only custom drawing in the product.

- **Shape:** square at the top so it sits flush with the screen edge, rounded at the
  bottom, and flared *outward* at the top corners. The outward flare is the whole
  trick; without it the shape reads as a panel, with it the shape reads as the
  cutout growing.
- **Fill:** `{colors.body}`, always. The silhouette is never tinted.
- **States:** idle draws the cutout exactly and is therefore invisible. Active adds
  `{spacing.wing}` on each side and a `{spacing.lip}` lip below. Expanded grows to
  `424px` wide with the radii stepping up together.
- **Motion:** `smooth(duration: 0.32)` on hover, `smooth(duration: 0.38)` on
  becoming active. `smooth` is the system's spring with the bounce removed; a damped
  spring overshoots, and on a 92pt-per-side width change that overshoot reads as a
  wobble at the end of the expansion.
- **Content handoff:** content inside the silhouette fades out in 0.07s and fades in
  after a 0.10s delay, never both at once. Content that appears at full opacity while
  the shape is still a third of its width shows the middle band of a 424pt panel
  clipped to a notch, which reads as a glitch rather than a reveal.

### Status Glyph

- **Style:** the state's own silhouette at 11pt to 15pt, colored by the state.
  Running is a 72% circular arc turning once every 0.85s, or the client's own vector
  mark turning once every 2.6s when it has one. Waiting is a filled dot pulsing
  between 62% and 100% scale over 0.7s. Done is a checkmark, failed is an
  exclamation, both at 600 weight.
- **Reduce Motion:** the arc and the pulse resolve to their static silhouettes. The
  dot is retained rather than swapped, because it is the one shape no other state
  uses.

### Session Row

- **Shape:** no shape. A 42pt row, separated from its neighbour by a 1px hairline at
  `{colors.ink-rule}`. Never a card.
- **Structure:** status glyph, then a two-line stack of session name
  (`{typography.title}` at `{colors.ink-primary}`) over working directory
  (`{typography.caption}` at `{colors.ink-tertiary}`), then a right-aligned stack of
  timing (`{typography.label}`, colored by state) over client name when more than
  one client is live.
- **Internal spacing:** `{spacing.row}` between columns, 1px between the two lines.
- **Ordering:** rows sort by urgency, not by recency. Whatever is blocked on a human
  is always on top.
- **Why two lines:** two sessions in folders both called `api` are indistinguishable
  from the name alone. The directory line is not decoration.

### Footer Controls

- **Style:** a system checkbox and a plain text button at `{typography.caption}` in
  `{colors.ink-tertiary}`, separated from the list by a hairline.
- **Treatment:** unstyled. These are AppKit controls doing exactly what AppKit
  controls do, which is the correct amount of design for a launch-at-login toggle.

## 6. Do's and Don'ts

### Do:

- **Do** author every color in OKLCH and let the converter in `Palette.swift`
  produce sRGB. Lightness is the load-bearing channel.
- **Do** give every state a distinct silhouette as well as a hue, and verify the
  lightness ladder holds before adding one.
- **Do** measure contrast rather than eyeballing it. The floor is 4.5:1 against the
  body, and 0.45 opacity already fails it.
- **Do** use the four ink roles for text. Adding a fifth opacity to solve a local
  problem breaks the ladder for everyone.
- **Do** use tabular figures on anything that ticks.
- **Do** honor Reduce Motion and Increase Contrast. Inheriting the system's
  accessibility settings is part of the personality, not a compliance chore.
- **Do** keep `#000000` for the panel body, where it is the only correct value.
- **Do** separate surfaces with a 1px hairline at `{colors.ink-rule}` or with
  nothing.

### Don't:

- **Don't** ship the **glowing AI product**: no purple-blue gradient auras, no
  "intelligence" shimmer, no bloom behind glyphs, no animated gradients on state
  change. This is the default look of agent tooling and the loudest way to break the
  illusion.
- **Don't** import **corporate SaaS chrome**: no cards, badges, pills, drop shadows,
  or dashboard vocabulary. The hover panel is a menu, not a dashboard.
- **Don't** make it **toy or cute**: no bouncy overshoot, no elastic springs, no
  emoji, no mascot energy, no rounded-everything. Motion here is physical, not
  playful.
- **Don't** add a shadow, blur, vibrancy, or material anywhere, including on hover
  and focus.
- **Don't** use a larger point size to signal importance. Use the ink ladder.
- **Don't** let a client's accent color carry state. Identity and status are
  separate channels, and the moment a client's brand color means "running", the
  product is lying.
- **Don't** introduce untinted black or white outside the panel body.
- **Don't** add a display typeface, a custom font, or a weight above 600.
- **Don't** add a tunable to avoid making a decision. The defaults are the product.

**Audit test:** screenshot the collapsed indicator and desaturate it. If you cannot
tell running from waiting from failed, the silhouettes are wrong, no matter how
good the colors look.
