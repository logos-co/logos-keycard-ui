# Comment to post on logos-co/logos-keycard-shell-module#9

(Extends the xpub-derive issue to a second caller. Plain text, no blockquote, for pasting.)

---

Second caller for the same fix: Shell wallet **identify** has the identical per-leaf cost.

identifyWallet(serial) -> add_accounts({ identify: true }) -> export() confirms the master key once, then re-exports every saved account's public key from the device to prove it shares that root:

- signer.rs:703-726 (the "legacy" loop): for each saved account not yet associated with this Shell's root, commands::get_public(t, &path, false), one GET_PUBLIC APDU = one on-device approval, then a full-key compare. The code comment is explicit: "A short fingerprint cannot prove that legacy accounts share this root. Re-export each saved key and compare its full public key."
- signer.rs:727-773: same per-leaf get_public for the wanted set.

So identify costs 1 approval (master key) + 1 per saved account. A 10-account wallet is an 11-approval identify. This now bites on every reconnect, because session verification is dropped when the Shell disconnects, so identify re-runs each time the Shell is re-seated. Measured on hardware: 1 account = 2 approvals.

The account-xpub approach fixes this caller too: export the account-level extended key (m/44'/60'/0' + chain code) once, derive each saved account's leaf host-side (BIP32 non-hardened) and compare locally. That still satisfies the "prove the full key, not just the 4-byte fingerprint" goal the re-export exists for, while collapsing identify to a single approval.

Minor, optional: add_status currently reports only confirm_on_device / done / failed (signer.rs:177), no running count, so a host can't show "approval N of M" during the multi-tap flow. The xpub fix removes the multiple taps, so this is noted only to avoid it being raised separately.

Interim on our side (keycard_ui fork, demo/keycard-improvements): the identify notification holds one "Approve on Shell..." state across all approvals and tells the person upfront to expect more than one.
