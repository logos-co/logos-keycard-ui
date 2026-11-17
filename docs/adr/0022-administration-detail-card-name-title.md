# ADR-0022: Administration detail panel — card name as the title, lighter status reads

- Status: Accepted
- Date: 2026-11-17
- Scope: `keycard_ui` (UI only; CardAdministration; no backend or `.rep` change)
- Issue: #2 (supersedes the Administration detail parts of ADR-0006 and ADR-0015)

## Context

The Administration detail panel (ADR-0006, restyled in ADR-0015) showed the selected card's
identity as a block of labeled rows inside a bordered card: a "Card name:  <name>" row with a
"More details" button beside it, then fingerprint, key id, version, keys and authenticity. Two
rough edges showed up in use:

- The card name read as just another field, when it is the one human-facing label for the card.
- "More details" re-runs a status read, and the panel also re-read the on-card name after **every**
  guided operation closed. Once the name became the headline, that re-read flashed "Checking…" in
  the title on every modal close, even for operations that cannot change the name.

## Decision

- **The card name is the detail panel's title.** It is a bold title **above** the details card, on
  the panel background, instead of a "Card name:" row inside it. An un-named card falls back to
  "Keycard". The fingerprint, key id, version, private-keys and authenticity rows stay inside the
  card as before.
- **"More details" becomes a link at the end of the details card**, not a button in the header. It
  still triggers the same no-PIN `status` read (`runStatusOp("status")`).
- **The on-card name is re-read only after a successful Update name** (`set_name`), not on every
  guided-flow close. A card-identity change (factory reset, erase) is already handled by the
  `changed` path, which re-selects the card and re-reads on its own, so no name flash is lost there.

## Consequences

Positive:

- The card the person is administering is named at a glance, consistent with how the Wallets tab
  titles a wallet.
- The title no longer flickers "Checking…" when closing a PIN change, a phrase check, or any other
  operation that leaves the name untouched.

Costs / follow-ups:

- The name shown while a status read is genuinely in flight (first selection of a card) still passes
  through "Checking…" briefly; that is the one case where the read is real.

## Alternatives considered

1. **Keep the "Card name:" row and just stop the re-read.** Rejected: the name is the panel's
   identity and reads better as the title; the row duplicated what a title should carry.
2. **Re-read the name on every close but debounce the "Checking…" text.** Rejected as papering over
   an unnecessary read; gating the read to `set_name` removes the work, not just the flicker.
