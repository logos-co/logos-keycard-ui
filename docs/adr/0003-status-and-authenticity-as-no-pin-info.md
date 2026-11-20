# ADR-C: Card status and authenticity are read-only info, not actions

- Status: Accepted
- Date: 2026-11-13
- Scope: `keycard_ui` (UI only; no backend or `.rep` change)
- Issue: #2 (amends ADR-A's "Routine" action tier)

## Context

ADR-A grouped the administrative operations into risk tiers and listed them as visible
buttons. Its first tier, "Routine", held two operations: "Card status" and "Check card
authenticity". Both were entries in the same `choices` list as the state-changing
operations and ran through the same select-action-then-submit flow.

Two facts separate these two from the rest:

- Neither needs a PIN (`needsPin` already excludes `status` and `check_identity`).
- Neither changes the card. They read and report; they do not modify keys, PIN, pairings
  or data.

The Administration panel already shows a "Card status" section with the card's static
state (version, whether it holds keys). Running the "Card status" operation only adds the
live counters (PIN/PUK attempts left, pairing slots).

## Problem

Listing status and authenticity as "actions" alongside Change PIN, Erase keys and Factory
reset implies they belong to the same category of card-modifying operations. They do not.
It also splits the card's read-only information across two places: a static status section
and a separate "Card status" action.

## Decision

Treat read-only card information as information, shown with the status it reports, not as
actions in the action list.

1. Remove the "Routine" tier from the action list. The action list now contains only
   operations that change the card ("Set up and keys" and "Destructive").
2. Surface the two read-only operations as buttons in the Card status section:
   "Card details" (the live `status` read) and "Check authenticity". Both run with no PIN
   and show their result in place.
3. Remove `status` and `check_identity` from the `choices` model so they are no longer
   selectable as actions; run them through a dedicated no-PIN path (`runStatusOp`) that
   does not touch the action/confirmation flow.

## Consequences

Positive:

- Clear category boundary: the status section is where you read the card; the action list
  is uniformly "things that change the card".
- The card's read-only state lives in one place.
- No PIN prompt for information that needs none.

Costs:

- Two code paths now talk to `administer` (the action `perform()` and the info
  `runStatusOp`). They are kept small and separate on purpose; the duplication is a few
  lines and avoids coupling read-only reads to the action/confirm machinery.

## Note (bug surfaced here)

Exercising these buttons on real hardware surfaced a pre-existing defect: `message` was
written throughout `CardAdministration.qml` but never declared as a property, so in QML
strict mode each write threw after `busy = true`, which left every admin action locked.
It had never shown because the panel had only been driven by doctests. Fixed by declaring
`property string message: ""`. Recorded here because this ADR's change is what first drove
the admin actions on a live card. The fix is a one-line upstream candidate.

## Alternatives considered

1. Keep both in the action list but label the tier "Read-only". Rejected: it still frames
   reading the card as an action and keeps the information split in two places.
2. Auto-run `status` on card connect so the live counters always show. Rejected for now:
   it talks to the card on every connect without the user asking; a button keeps the card
   access explicit.
