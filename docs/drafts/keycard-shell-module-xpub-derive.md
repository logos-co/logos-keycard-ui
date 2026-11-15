# Export the account xpub once and derive leaves host-side (Shell + card add-accounts)

**For:** `logos-co/logos-keycard-shell-module` (and `keycard_module` for inserted cards).
**TL;DR:** Adding/previewing accounts currently exports each leaf public key
(`m/44'/60'/0'/0/i`) from the device one at a time. On a Keycard Shell every export needs an
on-device confirmation, so listing N addresses costs N taps (+ ~2 first-use taps per connection).
The Shell firmware author says this is the wrong host pattern: export the **account-level xpub at
`m/44'/60'/0'` once**, then derive the leaves host-side. One tap, any number of addresses.

## Evidence
- Keycard Shell issue + maintainer guidance: https://github.com/keycard-tech/keycard-shell/issues/237
  — bitgamma (Shell firmware author): *"you should not export the keys one-by-one, but rather only
  export the xpub of `m/44'/60'/0'` and derive the leaves host-side. This way you only need to
  export a single public key and can derive as many addresses as you want in milliseconds, without
  round trips."*
- Measured on real hardware (Shell, latest firmware, dogfooding Basecamp keycard_ui): ~2 taps
  first-use overhead per connection (master-key verify + connect consent) + 1 tap per exported
  address. 5 addresses = 5 taps; 1 address on a fresh connection = 3 taps.

## Proposed change
In the add-accounts / preview path of `keycard_shell_module` (and `keycard_module`):
1. Export the extended public key (compressed pubkey + chain code) at the **account** level,
   `m/44'/60'/0'`, in a single device call (one Shell confirmation).
2. Derive the requested receive leaves `m/44'/60'/0'/0/i` host-side with BIP32 **non-hardened**
   derivation from that xpub. No further device round-trips.
3. Return the leaf public keys / addresses to the caller exactly as today, so `keycard_ui` needs no
   change beyond dropping its interim per-page-of-1 workaround.

Bitcoin already follows this shape in the UI backend (receive addresses are derived from the saved
account xpub, `keycard_ui_backend.cpp:171`); this brings EVM account export in line.

## Why it matters
First-run "add accounts" is the first thing a user does with a Shell. Today it feels stuck
(confirm, screen clears, confirm again…). The xpub approach makes it a single confirmation and lets
the picker show any range of addresses instantly.

## Second caller: Shell wallet **identify** has the same cost (found 2026-11-15)

The same per-leaf export shows up a second time, in the **identify** path (link a connected Shell
to its wallet). `identifyWallet(serial)` → `keycard_shell_module.add_accounts({ identify: true })`
→ `export()` which, after confirming the master key once, **re-exports every saved account's public
key from the device** to prove it shares this root:

- `signer.rs:703-726` — the "legacy" loop: for each saved account not yet associated with this
  Shell's root, `commands::get_public(t, &path, false)` (one `GET_PUBLIC` APDU = one on-device
  approval), then compares the full key. The code comment: *"A short fingerprint cannot prove that
  legacy accounts share this root. Re-export each saved key and compare its full public key."*
- `signer.rs:727-773` — the wanted loop, same per-leaf `get_public`.

So identify costs **1 approval (master key) + 1 per saved account**. A wallet with 10 accounts is an
11-approval identify, and identify is now required on every Shell reconnect (session verification is
dropped on disconnect by design). Measured: 1 account = 2 approvals.

**Same fix.** Once the account-level xpub (`m/44'/60'/0'` + chain code) is exported once, every saved
account's leaf public key can be derived host-side (BIP32 non-hardened) and compared locally, with no
further device round-trips. That satisfies the "prove the full key, not just the fingerprint" goal
the re-export was there for, while collapsing identify to a single approval.

Minor secondary point: today `add_status` reports only `confirm_on_device` / `done` / `failed`
(`signer.rs:177`), with no running count, so a host cannot show "approval N of M" progress during the
multi-tap flow. The xpub fix removes the multiple taps, making a progress counter unnecessary; noted
only so it is not raised separately.

## Interim (shipped in our keycard_ui fork)
- Add/preview: preview page size reduced to 1 for Shell connections, so the common add-one-account
  flow is the fewest taps the current module allows.
- Identify: the notification holds a single "Approve on Shell…" state across all the approvals and
  tells the person upfront to expect more than one, so the multi-tap flow reads as one operation.
Both to be reverted/simplified once the module exports the account xpub and derives leaves host-side.
