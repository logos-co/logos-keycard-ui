# ADR-I: Hide the card picker for a single card; one refresh for the panel

- Status: Accepted
- Date: 2026-11-14
- Scope: `keycard_ui` (UI only; no backend or `.rep` change)
- Issue: #2 (refines ADR-F)

## Context

ADR-F gave administration a "Select card" title and a picker above the Details panel, and the
panel carried its own refresh button beside the picker. Two observations in use:

1. The common case is **one** administrable card: a person has a single reader with a single card
   in it. A one-item dropdown is a control with no choice to make. It reads as a step the user must
   clear before reaching Details, when there is nothing to select.
2. The panel's refresh duplicated the one already in the app-block header. The header's
   `refreshButton` calls the same `backend.refresh()`, and the panel re-selects and re-reads the
   card automatically whenever the card list changes (`onUsableCardsChanged`). Two buttons, one
   behaviour, in a small panel.

## Decision

1. **Show the "Select card" title and the picker only when more than one administrable card is
   present** (`usableCards.length > 1`). With exactly one card, the panel auto-selects it and goes
   straight to Details; there is no picker row and no title. The picker reappears the moment a
   second reader-and-card makes the choice real.
2. **Remove the refresh control from the administration panel.** Re-scanning is the app-block
   header's job (`refreshButton` → `backend.refresh()`), and the panel already re-selects and
   re-reads on `onUsableCardsChanged` after a scan, so nothing is lost.

The picker widget itself stays instantiated (hidden, not destroyed) so the auto-select logic that
reads `picker.currentIndex` keeps working at one card and at many.

## Consequences

Positive:

- The single-card path, the common one, lands directly on the card's Details with no dead control
  in the way.
- One refresh affordance for the whole Keycard view, where the user already looks for it.
- The multi-card case is unchanged: a real choice still gets a real picker.

Costs:

- Re-scanning is now only in the header, one level up from the panel. Acceptable: it is the same
  button a person uses to detect a card in the first place, and it is always visible.

## Alternatives considered

1. Always show the picker (ADR-F as-is). Rejected: a one-item dropdown is chrome, not a choice.
2. Keep the panel refresh too, for proximity. Rejected: it duplicates the header's, and the panel
   re-reads automatically after any scan, so the second button earned nothing.
3. Keep the title but drop only the dropdown at one card. Rejected: a "Select card" heading with
   nothing to select under it is the same empty-gesture problem one level down.
