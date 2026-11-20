# ADR-M: One entry point per action; a connection chip per transport

- Status: Accepted
- Date: 2026-11-14
- Scope: `keycard_ui` (UI only; no backend or `.rep` change)
- Issue: #2 (refines ADR-B)

## Context

Two header issues surfaced dogfooding the Wallets tab:

1. The header carried an **"Open wallet via USB…"** button (opening a `shellSheet` dialog that
   picked a Shell device and started the add-accounts flow). But each Shell already appears as its
   own "Keycard via Shell" wallet block with an **Add accounts** button that starts the exact same
   flow (`openAdd`). Two controls, same action, one of them detached from the thing it acts on.
2. The connection chip (ADR-B) showed a single state: `cards > 0 ? "Card connected" : shell > 0 ?
   "Shell connected" : "No card detected"`. With **both** a reader card and a Shell connected, the
   first branch won and the chip read only "Card connected", hiding the Shell entirely, exactly when
   the user most needs to know both are present.

## Decision

1. **Remove the "Open wallet via USB…" button and its `shellSheet` dialog.** Adding accounts from a
   Shell happens from the Shell's own wallet block (its "Add accounts"), the designated place; the
   header duplicate is gone.
2. **Show one connection chip per live transport.** When ready: a green "Card via reader" if a
   reader card is present, and a green "Shell via USB" if a Shell is present; both show together
   when both are connected. A single fallback chip remains for the startup states ("Starting" /
   "Not responding") and for the nothing-connected case ("No card detected", warning).

On wording: the chip says "Shell via USB", not "Card connected via Shell". A Shell is a USB signer,
and the view's own help text notes that a Shell connection means USB is present, not that a given
seed/card is inside; "Card via Shell" would over-claim. "Card via reader" is exact (the reader count
is cards actually present). This keeps each chip truthful about what is known.

## Consequences

Positive:

- One way to add accounts from a Shell, anchored to the Shell's own block.
- Both transports are visible at once; neither hides the other.
- The chip copy stays accurate to what each transport actually guarantees.

Costs:

- The header can now show two chips; at very narrow widths they share the row with the title and
  refresh. Acceptable at the view's desktop sizing; revisit if this view gets a compact layout.

## Alternatives considered

1. Keep the "Open wallet via USB…" button. Rejected: it duplicates the Shell block's Add accounts
   and sits away from the wallet it acts on.
2. Keep one chip but switch its text when both are connected (e.g. "Card + Shell"). Rejected: a
   merged label is less scannable than two plain green chips, and still has to pick one color/state.
3. Use the user's "Card connected via Shell / via reader" wording. Deferred: accurate for the
   reader, over-claims for the Shell (USB present ≠ card/seed inside); "Shell via USB" is the
   truthful form. Trivially changed if the product prefers the symmetric phrasing.
