# ADR-N: Known vs unknown wallet states; Wallet ID is the master fingerprint; forget works while connected

- Status: Accepted
- Date: 2026-11-14
- Scope: `keycard_ui`. Mostly UI (QML), **plus one C++ backend change** (see "What needs the
  backend change" below); no `.rep` change.
- Issue: #2 (refines ADR-K)

## Context

Dogfooding the Wallets tab surfaced a presentation bug around a wallet's identity:

1. **The title changed when accounts were added.** A connected Keycard with no accounts read
   `Keycard wallet 52265c01…81ce6383`; after adding accounts the same wallet read `Keycard wallet
   1f994499`. Two different identifiers for one wallet, so it looked like the wallet renamed itself.
   The cause: the title was `fingerprintOf(g) || shortId(g.id)` — the BIP32 **master fingerprint**
   when accounts exist, else a truncated **keyUid**. These are different fingerprints of the same
   master key (SHA-256 keyUid vs 4-byte BIP32 fingerprint) and cannot be converted to each other.

2. **The master fingerprint is only readable once an account is loaded** (it is carried on account
   rows). So it can never be the pre-accounts identifier.

3. **The keyUid adds no user value pre-accounts.** The keyUid is the key a saved wallet is
   *recognized by*: a connected card's live keyUid is matched against the saved store, and a saved
   wallet (with its accounts and master fingerprint) is shown immediately — including for a *second*
   card restored from the same seed, with no re-adding. So either the keyUid matches a saved wallet
   (and we are already showing the real master-fingerprint id), or it matches nothing (and the hex
   is opaque, unrecognised, and not the form other apps show). It is internal plumbing, not identity.

4. **Forget was blocked while the card was connected.** "Forget wallet…" opened a dialog that
   required removing the Keycard from the reader first (the confirm button greyed out, and the
   backend rejected the call), even though forgetting only drops this computer's saved accounts and
   name and erases nothing on the card. The dialog also said **"Forget Keycard"** while the wallet
   action said "Forget wallet…", and the body itself said nothing on the card is erased — so
   "Keycard" over-claimed.

## Decision

1. **The Wallet ID is the BIP32 master fingerprint**, shown only once the wallet is known (has
   accounts). The keyUid is never surfaced as the headline id; it sits in the Wallet ID row's
   tooltip for anyone cross-checking. The master fingerprint is also what the Signer and Keys apps
   show, so it is the cross-checkable form.

2. **Two explicit wallet states, switched on "does this keyUid have saved accounts":**
   - **Unknown wallet** (connected Keycard, no accounts): title `Keycard · unknown wallet`, no
     Wallet ID row, and only **Add accounts** + **Card administration…** (the latter rides on the
     connection strip). No Rename/Forget: nothing has been created to rename or forget.
   - **Known wallet** (accounts saved): title `Keycard wallet <master fingerprint>`, a `Wallet ID`
     row (master fingerprint, keyUid in the tooltip), and Add accounts, Rename…, Forget… (+ Verify
     when a Shell is present), Card administration…

3. **Forget works with the card connected.** The confirm button no longer greys out and the backend
   no longer rejects the call. Forgetting drops the saved accounts and name; because the Keycard is
   still in the reader, the wallet **returns as an unknown wallet, ready to set up again** (it does
   not vanish). The dialog says so.

4. **Consistent wording: "Forget wallet"** (dialog title, confirm button, and the card action all
   agree), and the "Remove this Keycard from its reader before forgetting it." line is gone.

5. **Minor, folded in:** the always-on "master fingerprint" caption under the Wallet ID is dropped
   (it never varied, so it carried no information) and moved to the Wallet ID tooltip; the "Wallet
   ID" label and its value are baseline-aligned so they sit on one line.

## What needs the backend change (C++)

Everything above is QML **except** letting Forget run while connected: the connected-gate lived in
`keycard_ui_backend.cpp` (`forgetSavedCard` returned an error when the wallet's card was present),
so removing it is a C++ change and requires rebuilding the plugin, not just shipping QML. The gate
was redundant with the module's own behaviour (forgetting the saved record while the card is present
cleanly re-surfaces it as an unknown wallet), so dropping it needs no `.rep` or module change. Flagged
here because the rest of this ADR upstreams as pure QML; this one line does not.

## Consequences

Positive:

- A wallet's identity no longer changes when accounts are added; the headline is stable.
- The id shown (master fingerprint) is the one other apps show, and is only shown when it is real.
- "Unknown wallet" state stops presenting management affordances (Rename/Forget) for something the
  user has not created, and names the situation truthfully in the Wallets tab.
- Forget is reachable in the common case (card in reader) and its outcome is predictable: back to an
  unknown wallet, nothing lost on the card.

Costs:

- One C++ backend line now diverges from upstream (the removed gate), so this ADR is not a pure-QML
  change like the others; it needs a plugin rebuild to ship and review to upstream.
- "Unknown wallet" is a new user-facing term; it must stay distinct from the separate "not
  identified yet" section (a device whose keyUid is not matched at all, e.g. a Shell pre-identify).

## Alternatives considered

1. **keyUid as the Wallet ID everywhere** (tried first). It is stable and is the architecture's
   canonical wallet id, available with no tap. Rejected: it is long (`52265c01…81ce6383`),
   Keycard-internal, and not the form the Signer/Keys or hardware wallets show, so it reads as
   noise to the user. The real fix was separating the states, not changing which hash we show.
2. **Hide the id until accounts load, keep one "Keycard wallet" title.** Rejected: a connected
   keys-loaded card would show no id and still carry Rename/Forget, i.e. the same "manage a
   non-wallet" problem, just without the rename flip.
3. **Keep requiring card removal before Forget.** Rejected: forgetting erases nothing on the card,
   so the removal requirement was ceremony; dropping to the unknown-wallet state is clearer and
   fewer steps.
