# ADR-P: Shell identification as one notification, not a Verify button on every wallet

- Status: Accepted
- Date: 2026-11-15
- Scope: `keycard_ui` (UI only; QML + the strip/tag rendering in WalletCard; no backend or `.rep` change)
- Issue: #2 (supersedes the Verify-wallet decision in ADR-J/ADR-K); relates to
  logos-co/logos-keycard-shell-module#9

## Context

A connected Keycard Shell holds a seed the app cannot read without asking the device: the master
public key is only revealed when the person approves a request on the Shell screen. The previous UI
expressed this as a **"Verify wallet…" action on every identified wallet** whenever any Shell was
connected. Dogfooding surfaced several problems:

- **The question pointed the wrong way.** "Verify wallet" asked each wallet *"are you the Shell?"*, so
  with one Shell and two known wallets the button appeared on both, including a wallet already live on
  a reader. The relationship is Shell -> which wallet, not wallet -> verify.
- **"Verify" was the wrong word.** Nothing about a wallet is being verified; the app is asking the
  Shell which seed is inside it. The codebase already had the right verb (`identify`).
- **A re-seated Shell reached a dead state.** Keying "already identified" off the persistent saved
  association (the shell group) left a re-plugged Shell green-chipped and unusable: its live
  verification had been dropped on disconnect, so the wallet read "No device connected", yet nothing
  prompted a re-identify.

## Decision

1. **Remove "Verify wallet…" from wallet cards entirely.**

2. **A connected, unidentified Shell surfaces as one dismissible notification**, styled apart from
   wallet cards (warning-tinted background, thin amber border, amber dot — not a card background) so it
   never reads as a wallet. It carries the Shell serial, an **Identify** button, and **Dismiss**. Until
   the person identifies, **nothing on the wallet list changes**: no Shell transport strip, no new
   card, no edit to existing cards.

3. **Identify is a single on-tap request**, `backend.identifyWallet(serial)`: it asks the Shell to
   confirm its master public key on-device, then folds the Shell into its wallet (a known seed, names
   kept) or opens a new unknown wallet (state 1 from ADR-N). No target wallet is guessed.

4. **"Identified" is the live, session-scoped signal, not the saved association.** The notification
   and the header chip key off `verifiedMasterKeyId` (the Shell module's live on-device confirmation,
   dropped on disconnect — *"Session verification is temporary: never turn USB presence into a saved
   seed association"*), not the persistent shell group. A re-seated Shell therefore shows the
   notification again and the chip returns to yellow, because the on-device confirmation must be
   re-approved each connection. The app still *remembers* the wallet, so one tap re-folds it.

5. **Header "Shell via USB" chip is yellow while any connected Shell is unidentified**, green once
   identified. (The "Card reader" chip stays green; a PC/SC card is identified on connect.)

6. **Transport strips lead with a green device-type tag.** "Shell USB" / "Card reader" render green
   (connection made at a glance); the serial / card name / id follow in muted secondary text.

7. **The identify notification holds one working state across the Shell's several approvals.** Identify
   today costs more than one on-device approval (the master key, then one per saved account that the
   module re-exports — see Consequences). The button holds **"Approve on Shell…"**, both buttons stay
   disabled, and the copy says upfront to expect more than one approval, so the multi-tap flow reads as
   one operation instead of appearing to reset after the first tap. A per-serial `identifyingSerial`
   flag drives this, cleared on the job's `done`/`failed` or when the Shell verifies or disconnects (it
   does not rely on the polled export state, which dips between approvals).

A dismissed notification returns when that Shell is re-seated (dismissed serials are pruned when the
device leaves). Within a session, re-plugging is the only way back; making the yellow chip a click
target is noted as a possible follow-up.

## Consequences

Positive:

- The Shell is presented as what it is: a connected device of unknown contents, resolved by one
  identify, with no wallet touched until then. No more Verify button on wallets it does not belong to,
  and no dead green-chip state on reconnect.
- The green tags and yellow/green chip make connection state legible at a glance.

Costs / follow-ups:

- **Multi-approval identify is a module cost, not fixed here.** `export()` re-exports every saved
  account's public key from the device to prove it shares the confirmed root (`signer.rs:703-726`,
  `:727-773`), so identify is 1 approval + 1 per saved account; a 10-account wallet is 11 approvals,
  on every reconnect. The fix is host-side in `keycard_shell_module`: export the account-level xpub
  (`m/44'/60'/0'` + chain code) once and derive/compare leaves locally (bitgamma's guidance on
  keycard-tech/keycard-shell#237). This extends **logos-keycard-shell-module#9** (same per-leaf
  pattern as add-accounts). Item 7 is the interim until that lands.
- The transport-line tag assumes two device types; a third would need another tag colour/label.

## Alternatives considered

1. **Keep Verify, scope it to wallets without a live reader.** Rejected: still points the question the
   wrong way and still puts a device operation on wallet cards.
2. **Auto-fire identify on connect (blocking modal).** Rejected: inverts the iOS "trust this computer"
   direction (the modal is on the computer while the action is on the device), seizes the screen on
   every connect, and re-triggers on USB re-enumeration. The dismissible notification keeps "I'll deal
   with it in a sec" and the on-device approval remains the real gate.
3. **Show a progress counter ("approval N of M").** Rejected: `add_status` reports no running count
   (`signer.rs:177`) and the UI does not know the wallet/account total pre-identify, and the xpub fix
   removes the multiple taps anyway.
