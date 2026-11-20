# ADR-0023: Blocked-card state from the status read, not `cards()`; read on insert

- Status: Accepted
- Date: 2026-11-18
- Scope: `keycard_ui` (UI only; CardAdministration + KeycardView; no backend or `.rep` change)
- Issue: #2 (updates the title fallback from ADR-0022; builds on the state map in
  `docs/keycard-state-action-map.md`)

## Context

A **blocked** Keycard (the PIN retry counter has reached 0 after too many wrong PINs; the canonical
Keycard/Status term is "blocked", recoverable with the PUK) was not recognised in the UI:

- **Administration** showed the full has-seed action set (Check recovery phrase, Change PIN, Change
  PUK, Update name, Erase keys, Factory reset) for a blocked card, then collapsed to the recovery
  actions a moment later. All of the hidden-later actions need the current PIN, so they could only
  fail.
- **Wallets** offered **Add accounts** on the blocked card's "Unknown wallet", which cannot work
  without unlocking the card.

Root cause: the action gating keyed on `cards()`'s `pinRetries`, but **`cards()` reports a stale
`pinRetries` for a card and carries no `pukRetries` at all** (`docs/keycard-state-action-map.md`
already flags the missing `pukRetries`). The authoritative counts come only from the no-PIN `status`
action, which returns both `pinRetries` and `pukRetries`. A card reading "PIN attempts left: 0" in
"More details" still showed the wrong buttons because the gating never saw the status value.

Two further UX asks followed from live testing: the state should be read **when the card is
inserted**, not when the user opens the Administration tab; and the UI should **know the state before
it shows actions**, so the full list never flashes then collapses.

## Decision

- **The blocked state is derived from the `status` read (`pinRetries` + `pukRetries`), never from
  `cards()`.** `pinRetries === 0` is blocked (LOCKED, PUK-recoverable); `pukRetries === 0` is
  blocked with the PUK used up (FROZEN, factory-reset-only).
- **Read on insert, cache per card.** `KeycardView` already runs a no-PIN `status` read per card on
  `onCardsChanged` (to show the card name); it now caches `{ pin, puk }` by `adminId`
  (`cardStateCache`) from that same read, with no extra calls, and passes the cache into the
  Administration panel. By the time either view needs the state, it is already known.
- **Administration gates actions on the true state.** PIN blocked → **Unblock PIN + Factory reset**;
  PUK used up → **Factory reset only** (checked first, because a frozen-PUK card is usually also
  PIN-locked and `unblock_pin` cannot help). The action list stays hidden behind a brief **"Reading
  card…"** until the state is known, so the wrong set is never shown.
- **Administration shows the blocked state as a red flag, not a banner.** A bold red **"This card is
  blocked"** sits at the top of the card-data list, above the fingerprint. No separate notice
  surface; the available actions carry the way out.
- **Wallets withholds Add accounts** when the card is blocked, and on an unidentified card **until
  its state is read** (treat unknown as "don't offer until confirmed"), showing **"Reading card…"**
  then either the blocked note or, if clear, Add accounts. A wallet that already has accounts is
  known-usable and does not wait. **Card administration** stays available on the connection strip, so
  there is always a path to unblock or reset.
- **Terminology: "blocked".** Matches the Keycard help, Status help and the `CardFlow` copy already
  shipped ("The PIN is blocked", "The PUK is blocked"). The ADR-0022 title fallback changes from
  "Keycard" to a muted **"Name is empty"**, so the fallback no longer reads as if that were the name.

## Consequences

Positive:

- A blocked card reads correctly from the first frame: the right actions only, a red blocked flag,
  and no "Add accounts" that cannot succeed.
- No flash of the full action list, because the state is read on insert and the list waits on it.
- One reliable source of truth for the block state across both views, keyed on the authoritative
  `status` read rather than the unreliable `cards()` snapshot.

Costs / follow-ups:

- The Wallets tab depends on a per-card `status` read landing; a card inserted and opened in the same
  instant shows "Reading card…" for that brief window. This is deliberate (never offer before
  confirming) and short.
- The panel still re-reads `status` once on selection for the on-card name; after an op that changes
  the counts (e.g. Unblock PIN) that local read is the fresh value, overriding the insert-time cache.
- **Upstream follow-up:** adding `pukRetries` (and a fresh `pinRetries`) to each `cards()` entry would
  let the Wallets tab gate without a separate status read at all; the per-card read is a UI-side
  workaround for the gap `docs/keycard-state-action-map.md` records.

## Alternatives considered

1. **Trust `cards()`'s `pinRetries`.** Rejected: it is stale in practice and has no `pukRetries`, so
   a PIN-blocked card shows the wrong buttons and a PUK-frozen card is invisible to the gating.
2. **Keep the banner for the blocked state.** Rejected per design review: a red line at the top of
   the card data reads as part of the card, not a separate alert, and the actions carry the guidance.
3. **Gate Add accounts only on a confirmed-blocked card.** Rejected: that still flashes the button on
   app start before the read lands; withholding until the state is known removes the flash.
