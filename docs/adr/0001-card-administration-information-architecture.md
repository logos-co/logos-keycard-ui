# ADR-A: Card administration information architecture

- Status: Accepted
- Date: 2026-11-13
- Scope: `keycard_ui` (UI only; no backend or `.rep` change)
- Issue: #2 (supersedes the modal + dropdown presentation of `CardAdministration.qml`)

## Context

`keycard_ui` presents one scrolling surface of Keycard wallets and their accounts.
Card management lives behind a single header button, "Card administration...", which
opens a modal (`src/qml/CardAdministration.qml`). Inside the modal the user picks a
card, then picks one operation from a single dropdown, then fills the fields for that
operation.

The dropdown's contents are computed from the selected card's state
(`CardAdministration.qml:27-37`, the `choices` list). Depending on whether the card is
initialized, its secure-channel generation, its pairing state, and its capability bits,
the list ranges over roughly fifteen operations:

- Not initialized: Set up card.
- Always: Card status, Check card authenticity.
- 3.x unpaired: Pair this app.
- Initialized: Create / Import / Check recovery phrase; Change PIN; Change PUK;
  Unblock PIN; Change pairing password; Remove a pairing slot; Name stored on card;
  NFC text message; Read / Write card data (advanced); Generate keys without backup
  (advanced); Erase keys from card.
- Capable cards: Factory reset card.

Several of these are destructive. The code already gates them well:

- Typed confirmations: `factory_reset` requires "RESET", `remove_key` requires "ERASE",
  `generate_key` requires "NO BACKUP", `write_data` requires "WRITE"
  (`CardAdministration.qml:47`).
- PIN gating per operation (`needsPin`, line 41).
- A "the card changed, select it again" guard that clears secrets and blocks the action
  (lines 54, 67).
- Administration is reader-only: these operations are not exposed over a Keycard Shell
  USB connection (line 104), and the modal says so.

## Problem

1. Discovery. Every administrative action is three steps deep (button, then card pick,
   then dropdown) before the user can even see what the card supports.
2. Risk legibility. The dropdown gives a destructive operation (Factory reset, Erase
   keys, Generate without backup) the same visual weight as a read-only one (Card
   status). Risky actions look the same as safe ones.
3. Framing. Administration is a first-class capability of the app, but the UI presents
   it as a secondary modal, which understates it and hides the card's current state.

## Steelman of the current design

The modal plus dropdown is a defensible, deliberate choice, and any replacement must
keep what it gets right:

1. Administration is rare and advanced. A modal keeps it out of the everyday wallet
   flow, which reduces accidental destructive actions.
2. A single dropdown compactly encodes about fifteen state-varying operations without a
   large always-visible surface. The state logic already hides operations the selected
   card cannot perform.
3. The modal serializes one operation at a time with a focused set of fields and typed
   confirmations. It is a safety container, not just a menu.
4. Reader-only is enforced and explained at the point of entry.

The weakness is not safety. It is discoverability and risk legibility.

## Decision

Replace the modal-and-dropdown presentation with two top-level areas in the app and a
risk-grouped action list, while preserving every safety property above.

1. Top-level areas. Introduce two sections in the app, "Wallets" (the existing accounts
   surface) and "Administration" (card management), using the same top-level section
   pattern the sibling wallet apps already use (for example `eth_wallet_ui`'s tab strip
   over a `StackLayout`). This matches the title and subtitle adopted in #1 ("Keycard"
   / "Wallets and card administration").

2. Card state, shown first. In Administration, show the selected card's state up front
   (initialized or not, holds recovery keys or not, version, PIN and PUK attempts left,
   free pairing slots) rather than requiring the user to run "Card status" to learn it.
   This data is already returned by the `status` operation and the cards model.

3. Actions as a grouped, visible list, not a dropdown. Render the operations that are
   available for the current card state (reuse the existing `choices` computation
   verbatim) as a visible list grouped by risk tier:
   - Routine, no secret or key change: Card status, Check authenticity.
   - Setup and keys, recoverable changes: Set up card, Create / Import / Check recovery
     phrase, Change PIN / PUK, Unblock PIN, pairing management, Name on card, NFC text,
     Read / Write data.
   - Destructive, irreversible without a backup: Generate keys without backup, Erase
     keys, Factory reset. This group is placed last, visually separated, and marked with
     the error color.

4. Keep the per-operation form. Selecting an action opens the same focused fields the
   modal already uses. We change how the action is reached (a grouped list instead of a
   dropdown), not how it is performed.

5. Preserve every safety invariant unchanged: reader-only (Administration is disabled
   and explained for a Shell-only connection), the typed confirmations, the PIN gates,
   and the "card changed, reselect" guard.

Design lens (safety switch with per-action confirmation gates by risk level, from the
Logos virtual-world material): the fix for "risky actions look the same as safe ones" is
to make the risk tier visible and to keep a confirmation gate on each high-risk action,
which is exactly what the grouped list plus the existing typed confirmations provide.

## Consequences

Positive:

- Administration is discoverable in one step and its actions are visible at a glance.
- The card's state is legible without running an operation to find it.
- Risk is visible: destructive actions are separated, marked, and last, and still gated.
- The app's framing matches reality (two first-class areas), consistent with #1.

Costs and risks:

- More vertical space than a dropdown. The action list must collapse to a single column
  on narrow or phone widths (per the responsive rules), with the destructive group still
  last and the primary action reachable by thumb.
- The two-area navigation must fit inside a single Basecamp tab. We use an in-view
  section control, not host-level tabs.
- Re-presenting about fifteen state-varying actions as a list must preserve the state
  gating exactly. We reuse the existing `choices` logic rather than re-deriving
  availability, so we cannot offer an action a card does not support.

## Alternatives considered

1. Keep the modal, only group the dropdown (option groups by risk). Cheaper, but leaves
   administration three steps deep and does not make the card's state or the risk tiers
   legible. Rejected: it does not address discoverability.
2. Split Administration into its own Basecamp app or module. Too heavy, and it separates
   one physical card's management from its wallets even though they share card and
   connection state. Rejected.
3. Inline the administrative actions on each wallet card. Scatters destructive operations
   next to everyday ones, which is worse for safety. Rejected.

## Open questions (implementation detail, do not block the decision)

- The exact section control to match the sibling apps (a shared control versus a local
  Segmented component). Confirm against the sibling wallet views at implementation.
- Risk-tier placement of two non-destructive but state-writing operations ("Name on
  card", "NFC text"): proposed in the Setup and keys tier, since they write to the card
  but are recoverable and non-destructive.
- Compact-width layout of the grouped action list and the card-state header.
