# ADR-0029: The Keycard app depends on the signer manager, so forgets and enrolments reach it

- Status: Accepted
- Date: 2026-11-23
- Scope: `keycard_ui` — `metadata.json` `dependencies` only. One line; no code change.

## Context

`keycard_module` and `keycard_shell_module` both talk to `signer_manager_module`: they
**enrol** a Keycard seed into it (so the Signer and other apps can use the account) and they
**forget** a seed from it (so a removed wallet disappears everywhere). Both call it, and both
subscribe once, at their own start-up, to its `wallets_changed` / `wallets_locked` events to run
a catch-up reconcile sweep.

`signer_manager_module` is **lazy-loaded**: nothing starts it until an app that lists it as a
dependency opens, and in practice that was only the Signer / Keys apps (`evm_signer_ui`,
`evm_keystore_ui`). The Keycard app declared only `keycard_module` and `keycard_shell_module`,
neither of which pulled the signer manager in. So whenever the Keycard app was used **while the
Signer app was closed**, the signer manager was not running, and two things broke:

1. **Enrolment was dropped.** Add accounts fires `enroll_seed` fire-and-forget; with the manager
   down the seed never reached it, and nothing re-enrolled on reconnect. The account then failed
   to send with "this account's wallet isn't known yet / unlock it in the Signer app".
   (`logos-co/logos-keycard-module#10`.)
2. **Forget did not propagate.** `forget_seed` failed with "failed to acquire remote object
   'signer_manager_module' (module not loaded)", and because the keycard modules' one-time
   subscription to the manager had also failed, the catch-up reconcile sweep never armed for that
   session. A wallet forgotten in Keycard lingered in the Signer until a later run where the
   Keycard modules happened to start with the manager already up (open Signer first, then Keycard).
   This is the limitation ADR-0028 recorded as a follow-up.

The root is the same for both: the signer manager was not loaded for the Keycard session.

## Decision

Declare `signer_manager_module` as a dependency of the Keycard app, alongside the two keycard
modules:

```json
"dependencies": [
  { "name": "keycard_module",        "version": "~0.2.0" },
  { "name": "keycard_shell_module",  "version": "~0.2.0" },
  { "name": "signer_manager_module", "version": "~0.2.0" }
]
```

Opening the Keycard app now loads the signer manager (and its own `keystore_module`
dependency) as part of the app's dependency set, before the keycard modules do their work, and
keeps it loaded for the whole Keycard session. The enrol and forget calls reach a live manager,
and the keycard modules' subscription to its events arms immediately.

This mirrors how the sibling wallet apps already declare it: `evm_keystore_ui`
(`keystore_module`, `signer_manager_module`) and `bitcoin_wallet_ui` (`bitcoin_wallet_backend`,
`signer_manager_module`). The Keycard app is likewise a signer that enrols into the manager, so
the dependency is a real one, not a workaround.

## Consequences

Positive:

- **Enrolment reaches the manager** (`#10`): adding accounts in Keycard with the Signer closed now
  enrols the seed; the account shows in the Signer and can send.
- **Forget propagates live**: forgetting a wallet in Keycard with the Signer closed removes it from
  the signer manager immediately, with no restart and no open-Signer-first ordering. This resolves
  the lazy-load limitation noted in ADR-0028's Consequences.
- One-line manifest change, no code, no new failure modes. The manager was already an implicit
  runtime dependency; this makes it explicit.

Costs:

- The signer manager (and `keystore_module`) now load whenever the Keycard app opens, even if the
  person never opens the Signer. This is a small start-up cost and is correct: Keycard genuinely is
  a signer that enrols into the manager.

## Verification

Tested at runtime on 2026-11-23 against a physical Keycard, with the Signer app never opened:

- Opening Keycard loaded `keystore_module` and `signer_manager_module` as app dependencies (log:
  `Loading core dependencies for "keycard_ui" : QList("keycard_module", "keycard_shell_module",
  "signer_manager_module")`), with no "module not loaded" or deferred-subscription warnings.
- **Forget:** forgetting a Keycard wallet removed its seed from the signer manager's store
  (`seeds.json`) with the Signer closed. Previously this failed with
  `forget_seed() failed ... module not loaded`.
- **Enrol:** Add accounts enrolled the Keycard seed into the signer manager (it appeared in
  `seeds.json` with holder `keycard_module`, and in the Signer app on open).

## Related

- ADR-0028 — forgetting a locked or unknown wallet; its Consequences recorded this propagation gap
  as a follow-up, now closed here.
- `logos-co/logos-keycard-module#10` — "send from a Keycard account fails"; same lazy-load root.
