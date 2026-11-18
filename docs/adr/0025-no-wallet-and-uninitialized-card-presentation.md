# ADR-0025: Cards with no wallet — honest presentation; "state known" means the read returned

- Status: Accepted
- Date: 2026-11-18
- Scope: `keycard_ui` (UI only; KeycardView + CardAdministration + CardFlow copy; no backend/`.rep`)
- Issue: #2 (refines ADR-0023)

## Context

Live testing surfaced three states a card can be in with **no usable wallet**, each of which the UI
presented as if there were one:

- **Just factory-reset (uninitialized).** ADR-0023 gated the Administration action list on
  `stateKnown`, defined as "the PIN/PUK retry counts are present". An uninitialized card has no PIN,
  so those counts never arrive, and the panel was stuck on **"Reading card…"** forever instead of
  offering "Set up card".
- **PIN set, no keys loaded (`onlyPinSet`).** On the Wallets tab this card showed as a normal
  wallet: **"Add accounts"** (nothing to derive from — no seed), plus **Rename** and **Forget
  wallet** (nothing to name or forget), under a **"not identified yet"** title (misleading — there is
  nothing to identify; the card simply has no wallet).
- The Wallets tab also carried a **"Not identified yet"** section header whose copy duplicated what
  each card now says for itself.

A separate copy issue: the factory-reset and erase dialogs said "You need a **backup** to restore
access to funds", when the canonical Keycard/Status term, and the one the rest of this app's copy
uses, is the **recovery phrase**.

## Decision

- **`stateKnown` means the status read has returned, or the card needs no read to classify** — not
  "has retry counts". Only an initialized, paired card can be blocked, so only it waits on the read;
  an uninitialized or unpaired card is classified from `cards()` alone and shows its action (e.g.
  "Set up card") immediately. A `localRead` flag records that this panel's read returned.
- **A card with no seed is presented as having no wallet.** `cardNoSeed(g)` (no connected reader card
  carries a `keyUid`) drives, on the Wallets tab:
  - **no "Add accounts"** (nothing to derive),
  - **no Rename and no Forget** (nothing to name or forget),
  - title **"Keycard · no wallet yet"** instead of "not identified yet",
  - a note: *"This card has no wallet yet. Create or import a recovery phrase in Card
    administration."*
  - **Card administration stays** (on the connection strip), the one place a seed is created or
    imported. These gates sit outside the `isUnknownWallet` branch, because a keyless reader card is
    not a `seed:` group and was otherwise treated as a named wallet.
- **Withhold "Add accounts" until the card's state is known** for any account-less card
  (`!hasAccounts(g) && !cardStateKnown(g)`), so it never flashes before a blocked/no-seed verdict; a
  wallet that already has accounts is unaffected.
- **Remove the "Not identified yet" section header** on the Wallets tab; each card now states its own
  condition.
- **Copy: "backup" → "recovery phrase"** in the restore-access text (factory reset, erase keys, in
  both `CardFlow` and `CardAdministration`), and the generate-keys warning title to "No recovery
  phrase".

## Consequences

Positive:

- A just-reset card lands on "Set up card" with no stuck placeholder; a keyless card reads honestly
  (no wallet yet, one route: Card administration) with no actions that cannot do anything.
- One consistent term ("recovery phrase") for the restore credential.

Costs / follow-ups:

- The typed factory-reset-adjacent confirmation keyword for generating keys without a phrase is still
  `NO BACKUP`; left as-is for now (it is a deliberate typed token), flagged for a possible rename to
  `NO PHRASE`.
- A keyless card still offers Card administration, which internally can name the card; naming is now
  only reachable there, not as a wallet rename, which is the intended home for it.

## Alternatives considered

1. **Keep `stateKnown` on retry counts and special-case uninitialized.** Rejected: "the read
   returned" is the real condition; keying on retries mis-modeled every card without a PIN.
2. **Grey out Add accounts / Rename / Forget on a keyless card instead of removing them.** Rejected:
   a disabled control still says the action exists; removing them states plainly that there is no
   wallet, and Card administration is the next step.
3. **Keep the section header.** Rejected: redundant now that each card titles and explains itself.
