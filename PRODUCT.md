# Product

## Register

product

## Users

Developers who run coding agents from a terminal on a MacBook with a notch, usually
several at once, across more than one client (Claude Code, Codex, or any process
wrapped by the CLI). Their attention is elsewhere by definition: in an editor, a
browser, another repo, another terminal tab. The job to be done is knowing, without
looking for it, whether an agent turn is running, has stopped and needs an answer,
or has finished.

The failure this product exists to remove is the check loop: tabbing back to a
terminal to find out nothing has changed, or worse, finding out an agent has been
sitting on a permission prompt for six minutes.

Distribution is open source. Strangers install it against clients we have never
seen, so defaults have to be correct with zero configuration.

## Product Purpose

OpenNotch turns the MacBook notch into a status light for coding agents. The cutout
is a physical hole that cannot be drawn into, so the app parks a borderless
always-on-top panel over it: exactly cutout-sized and painted black when idle
(therefore invisible), growing wings and a shallow lip when something happens. Hover
reveals a panel listing every live session.

Success is peripheral: the user learns the state of every agent without deciding to
look, and never opens the hover panel except to disambiguate. The app knows nothing
about any particular agent; state arrives through one CLI and clients are plugged in
by mapping their events onto five states.

## Brand Personality

System-native ghost. Indistinguishable from macOS itself: the system's type, the
system's timings, the system's accessibility settings, no personality of its own.
That is the point, not a limitation. The illusion that Apple shipped this is the
product, and any visible authorship breaks it.

Voice in UI copy is the system's voice: plain, short, lowercase-sentence-case,
stating facts. "Needs you", "done in 1:38", "failed after 12s". No exclamation, no
encouragement, no personality in the strings.

Three words: invisible, exact, inherited.

## Anti-references

- **Glowing AI product.** Purple-blue gradient auras, "intelligence" shimmer, bloom
  behind glyphs, animated gradients on state change. This is the default look of
  agent tooling right now and it is the single loudest way to break the illusion.
- **Corporate SaaS chrome.** Cards, badges, pills, drop shadows, generic dashboard
  vocabulary imported into a 400pt panel. The hover panel is a menu, not a dashboard.
- **Toy or cute.** Bouncy overshoot, elastic springs, emoji, mascot energy,
  rounded-everything. Motion here is physical, not playful.

## Design Principles

1. **Idle is the real default state.** The app is invisible the overwhelming majority
   of the time. Any pixel, any animation, any attention spent at rest is a tax paid
   continuously for a benefit collected rarely.

2. **Defend the seam.** Every decision is measured against whether the panel still
   reads as the notch itself rather than a rectangle underneath it. Geometry,
   blackness, and timing all serve that one illusion; when a feature and the seam
   conflict, the seam wins.

3. **Inherit, do not invent.** Where macOS has an answer (type, easing curves,
   control metaphors, accessibility settings), take it. Inventing a convention here
   costs the ghost personality and buys nothing.

4. **State outranks identity.** What is happening is always more important than which
   client it is happening to. Client marks and accents are permitted to carry
   identity only where they cannot be confused for status.

5. **A tunable is a decision not made.** Shipped to strangers, the defaults are the
   product. Configuration exists for relocating state and debugging, not for
   recovering from a design choice we declined to commit to.

## Accessibility & Inclusion

Target: WCAG 2.1 AA for the hover panel. The collapsed state is an ambient
indicator rather than a reading surface, but it still must not be the only
carrier of a state.

- **Never color-only.** Every state carries a distinct silhouette as well as a
  hue: a turning mark, a pulsing dot, a check, a bang. State lightness is a
  deliberate ladder (waiting 0.82, done 0.70, error 0.62 in OKLCH) so the states
  stay ordered under deuteranopia and protanopia, where the hues collapse.
- **Honor Reduce Motion.** The spinner and the pulse resolve to their static
  silhouettes when the system asks. The dot is kept, because it is the one shape
  no other state uses.
- **Contrast.** Text opacities are named roles, not numbers, and the floor is
  4.5:1 against the body. Increase Contrast raises the whole scale. There is no
  translucency or vibrancy anywhere in the panel, so Reduce Transparency has
  nothing to act on; if a material is ever introduced, that changes.
- **VoiceOver.** The panel header and each session row are announced as single
  labelled elements. The collapsed indicator is not yet labelled.
