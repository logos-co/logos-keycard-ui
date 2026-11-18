# ADR-0026: Unpaired card — offer factory reset; show "More details" only when it has more

- Status: Accepted
- Date: 2026-11-18
- Scope: `keycard_ui` (UI only; CardAdministration; no backend or `.rep` change)
- Issue: #2 (refines the action map in `docs/keycard-state-action-map.md`)

## Context

A 3.x card that is inserted but **not paired** (`secureChannel === 1 && !paired`) offered only one
action, **Pair this app**. Two gaps showed up in use:

- If the person cannot pair (the pairing password was set at setup and is lost), there was **no way
  forward** — the card was a dead end in the UI. Factory reset is exactly the escape for that case,
  and it needs no PIN and no pairing: the `factory_reset` flow takes no secret, and Keycard's reset
  is a command the applet accepts without a secure channel when the card reports the reset capability
  (`capabilities & 16`).
- The card-details box showed a **"More details"** link, which runs the full status read (PIN/PUK
  attempts, free pairing slots, this app's slot). None of that is meaningful for an unpaired card
  (no slot yet) or an uninitialized one (no PIN), so the link led to an empty or irrelevant readout.

## Decision

- **Offer factory reset on an unpaired 3.x card**, next to Pair this app, gated on the reset
  capability (`capabilities & 16`). It renders in the red Destructive action group.
- **Show "More details" only when the card is initialized and paired** (reuse `needsStatusRead`).
  For an unpaired or uninitialized card the link is hidden; the basic identity rows (fingerprint,
  version, keys, authenticity) still show.

## Consequences

Positive:

- An unpaired card you cannot pair is no longer a dead end: factory reset recovers it.
- "More details" only appears when it has more to show, so it never opens an empty or N/A readout.

Costs / follow-ups:

- Whether `keycard_module` actually completes a factory reset on an unpaired card without a secure
  channel is confirmed from the flow (no PIN/pairing step) and the capability flag, but the module's
  behavior in that exact state is a hardware check; if it rejects the reset, the module path needs a
  look.

## Alternatives considered

1. **Leave the unpaired card with only Pair.** Rejected: a lost pairing password makes the card
   unusable with no recovery path in the app.
2. **Keep "More details" always and let the status op return nothing.** Rejected: a link that opens
   an empty/irrelevant readout is worse than no link; gate it on when it has content.
