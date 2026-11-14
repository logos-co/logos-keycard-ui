# ADR-J: Compact, content-first administration layout

- Status: Accepted
- Date: 2026-11-14
- Scope: `keycard_ui` (UI only; no backend or `.rep` change)
- Issue: #2 (refines ADR-A, ADR-F, ADR-H)

## Context

On a wide (landscape) desktop window the administration panel stretched to the full tab width.
Every action button became a ~1500px bar and the Details block ran edge to edge, which looks
unmoored and makes a row of full-width buttons read as heavier than they are. The panel also
carried a stack of section headings, "Select card", "Details", "Actions", and per-tier group
labels "Set up and keys" / "Destructive", over content that already names itself: a labeled
Details card, and buttons whose own text says what they do. The red "Destructive" heading was the
only thing marking erase/reset as dangerous, a property that belongs on the actions themselves.

## Decision

Make the panel a compact, self-describing column.

1. **Cap and center the column at 560px.** The content sits in a fixed-width, horizontally
   centered column regardless of window width, so buttons and the Details card keep a sane,
   readable width in landscape instead of spanning the whole tab.
2. **Drop the section headings.** "Select card", "Details", and "Actions" are removed; the
   content carries itself (a labeled Details card, buttons that name their action). Group
   separation now comes from spacing, not headings.
3. **Drop the visible tier labels** "Set up and keys" and "Destructive". The "Advanced" group
   keeps its header, because that header is also the collapse control (ADR-H) — it has a job
   beyond labeling.
4. **Color-code destructive actions instead of labeling the tier.** "Erase keys from card" and
   "Factory reset card" render with a red (`Theme.palette.error`) label and border. The danger
   signal moves onto the buttons a person actually clicks, where it is seen at the moment of
   action, not in a heading above them.
5. **More air between actions.** Per-group button spacing goes from `tiny` to `small`.

The `LogosButton` design-system control has only Primary/Secondary variants and no destructive
variant, so the red is applied by binding the button's label and border color to
`Theme.palette.error` for the danger group (see `docs/upstream-keycard-module-gaps.md` for the
missing-variant note). Destructive actions keep their typed-confirmation gates (ADR-H); the color
is an additional signal, not a replacement for the gate.

## Consequences

Positive:

- The panel reads as a tidy, deliberate column at any window width; no more full-width button bars.
- Less chrome: the eye goes to the card facts and the actions, not to a ladder of headings.
- The danger signal rides on the destructive buttons themselves, visible at the point of action.

Costs:

- Destructive styling is hand-applied (label + border color binding) rather than a DS variant; if
  the design system later ships a destructive `LogosButton` variant, this should move to it.
- 560px is a fixed choice. It suits the current action set; a much denser future panel might want
  to revisit it.

## Alternatives considered

1. Keep full-width, just add max-width to buttons. Rejected: a centered column reads as composed;
   individually capped buttons floating in a wide area do not.
2. Keep the tier headings but shorten them. Rejected: the heading over self-naming content is the
   redundancy; shortening it does not remove it. The Advanced header stays only because it doubles
   as the collapse control.
3. Mark destructive actions with an icon instead of color. Rejected: color is the stronger,
   faster danger signal here, and the typed-confirmation gate already carries the deliberate
   friction; an icon can be added later without undoing this.
