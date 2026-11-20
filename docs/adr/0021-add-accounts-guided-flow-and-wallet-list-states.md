# ADR-0021: Guided Add-accounts flow, and wallet-list visibility + locked-wallet states

- Status: Accepted
- Date: 2026-11-16
- Scope: `keycard_ui` (UI only; AddAccountsFlow + KeycardView; no backend change)
- Issue: #2 (continues the administration-flow conversion begun in ADR-0018/0020)

## Context

Two rough edges remained after the administration rework:

1. **Add accounts** was still the old single scrolling form, out of step with every
   administration operation, which is now a guided, one-concern-per-screen `CardFlow`.
2. The **Wallets list** accumulated residue and showed a misleading control. Testing a card
   through factory-reset / re-seed cycles mints a new seed each time; the backend keeps a
   `seed:` record per seed with no Forget path for an empty one, so old seeds lingered as
   stray "Unknown wallet" cards. The "Not identified yet" block rendered even with no card
   connected (its own copy says "A connected Keycard"), and sat at the END of the list where
   it would be missed. A locked wallet offered an active **Unlock** button even with no card
   on the reader, where unlocking is impossible: the Signer asks for *that card's* PIN.

## Decision

### Add accounts → a guided flow (`AddAccountsFlow.qml`)

A dedicated component reusing CardFlow's chrome (title line keeping the wallet + connection in
view, centred "Step N of 4", fixed modal size, working / success / error phases, `PinDots` for
the PIN) but keeping its own small state machine, because Add accounts is **not** an
`administer` plan: it reads public keys from the device and commits a selection through
`backend.addAccounts`, with the outcome arriving on the polled `exporting` state.

Four steps: **Choose** (account type + first index, as radio buttons, with a live derivation
path) → **Authorise** (card PIN as circles, or the Shell unlock instruction; a 3.x card's
pairing folds in here) → **Select** (a device-read page with pagination: one account per
on-device approval on a Shell, five on a card; already-added accounts marked; up to 20) →
**Name** (optional per account). A wrong PIN on the read routes back to Authorise with the
message; the modal never resizes.

Presentation pass (from on-hardware review):

- Each **account in Select and Name is its own card** — a darker inset fill plus a 1px border.
  The dialog surface is `backgroundSecondary`, so a `backgroundSecondary` block is invisible;
  blocks use `background` (inset) with `borderSubtle`, hover lifts to `backgroundTertiary`.
- In **Select, the whole block is the hit area** (tap anywhere toggles). The checkbox is a
  non-interactive indicator and the row carries a single `TapHandler`, so there is one toggle
  path and no double-fire. Already-added rows are dimmed and inert; the 20-cap blocks new taps.
- The step header gains top spacing so it breathes like the administration modals.

### Wallet list: show what is real, in the right order

- **Visibility rule.** A wallet is shown only when the person has **committed** to it (saved
  accounts, a locked/sealed wallet, or a name they gave it) **or** its Keycard is connected
  right now. A seed record with no accounts, not locked and not present is residue from a past
  card and is hidden. The keyless-card ("Not identified yet") block shows only while such a
  card is actually connected.
- **Order.** The "Not identified yet" block renders **above** the wallet cards, where a
  just-connected card is seen first, instead of after a potentially long wallet list.
- **Locked wallet.** Titled **"Locked wallet"** (not "Unknown wallet"). The description no
  longer repeats "Locked"; off the reader it reads "Connect this wallet's Keycard, then unlock
  it in the Signer app…", and the control becomes a disabled **"Connect card to unlock"**.
  With the card present it is an active **Unlock** and the copy explains the Signer asks for
  this card's PIN. Unlock is gated on `g.connected`, so a dead button is never offered. A
  **lock glyph** sits before the name so the state reads at a glance.
- **No wallet identifier while locked, deliberately.** The title stays the generic "Locked
  wallet" rather than an id-bearing name. The only identity that matches the unlocked card is
  the **master fingerprint** (the "Wallet ID"), and it is computed from the wallet's accounts,
  which are sealed while locked (verified: it exists in no plaintext store). The keyUid *is*
  available, but it is a different value from the fingerprint, so a keyUid-based name would
  imply a link to the unlocked wallet that it cannot honour. Showing nothing identifying is the
  honest choice; the real id appears as the Wallet ID line once unlocked.

## Consequences

Positive:

- Add accounts shares the guided framework's look and error handling with every other card
  operation; the account list and naming read as discrete, tappable cards.
- The Wallets list shows only wallets the person actually has or has connected, newest card
  first, and never offers an Unlock that cannot work.

Costs / follow-ups:

- The stray empty-seed records are **hidden**, not purged: the backend still mints a `seed:`
  record per seed with no Forget path for an empty one. A `keycard_module` issue to purge or
  allow forgetting empty seed records would remove the residue at the source.
- The old inline flow had a per-wallet **connection picker** (reader + Shell connected at
  once); AddAccountsFlow uses the default connection. A rare state; the picker can return to
  the Authorise step if needed.
- Add accounts still requires the device connected even where the master pubkey is already
  cached (EVM derivation is public); see the standing note on device-free add.

## Alternatives considered

1. **Extend CardFlow for Add accounts.** Rejected: the interactive preview / pagination /
   multi-select / naming do not map onto CardFlow's linear `administer` plan machine.
2. **Fix the residue in the backend first.** Deferred: the UI visibility rule removes the
   user-visible problem immediately and needs no module release; the backend purge is filed
   as a follow-up.
3. **Separate checkbox and row hit areas in Select.** Rejected as fiddly; a single whole-block
   tap with the checkbox as indicator is clearer and avoids double-toggling.
