# ADR-0030: On a Shell, five EVM accounts a page, and no Authorise step

- Status: Accepted (one confirmation a page needs logos-keycard-shell-module#14)
- Date: 2026-11-23
- Scope: `keycard_ui` — `src/qml/AddAccountsFlow.qml`. QML only.
- Supersedes: ADR-0012 (one account at a time on a Shell, an interim)

## Context

ADR-0012 cut the Shell's Add accounts page to one account, because every exported public key cost a
confirmation on the Shell, and said to revert once the module exported the account xpub.
logos-keycard-shell-module#14 does that for EVM: the Shell exports the xpub at `m/44'/60'/0'/0` once
a connection and the module derives the addresses. Measured on a real Shell with this change:
five addresses took **one** confirmation (was one per address), Next took none, and indexes 1 and 3
matched the Shell's own Verify address.

The flow's step 2, Authorise, had nothing to enter on a Shell: it only said to press Show accounts
and confirm on the device. On a card it is where the PIN (or pairing) goes.

## Decision

- **Five EVM accounts a page on a Shell**, as on a card. Bitcoin accounts are hardened, so each still
  needs its own export on the Shell: Bitcoin on a Shell stays one at a time, with its old copy
  (`shellPerKey`).
- **No Authorise step on a Shell.** Step 1's button reads "Show accounts" and goes straight to
  "Confirm the public-key requests on the Shell…". The flow counts three steps on a Shell; Back from
  the account list and a failed read return to step 1. Cards keep their PIN step.
- Copy no longer says "each public-key request" for EVM on a Shell.

## Consequences

- Adding an EVM account from a Shell: Add accounts → (Ethereum, Show accounts) → confirm once on the
  Shell → pick from five, Next for more with no further confirmations.
- The one-confirmation page needs keycard_shell_module with #14. With an older module a five-account
  page costs five confirmations, which is what `main` does today, so this is no regression there.
