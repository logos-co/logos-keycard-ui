# ADR-F: The Details panel, card facts at a glance with auto-verified authenticity

- Status: Accepted
- Date: 2026-11-13
- Scope: `keycard_ui` (UI only; no backend or `.rep` change)
- Issue: #2 (refines ADR-C)

## Context

ADR-C established that reading the card is information, not an action: `status` and
`check_identity` were moved out of the action list and offered as read-only buttons in a
"Card status" section. In use, the thing an operator wants first, on any connected card, is
a small set of stable facts about it: which card this is, whether it is genuine, what it
runs. Authenticity in particular is a trust signal that should not be hidden behind a
button the user has to know to press.

## Decision

Present the card's identity as a labeled Details panel, and verify authenticity
automatically.

1. Rename the section to "Details" and render it as a styled block (a filled, bordered
   surface) holding labeled facts:
   - **Card name** (the saved local name, or "No name"), resolved from the card's group.
   - **Fingerprint** (the card's `adminId`), with a copy button beside the value.
   - **Version** (the applet version, e.g. "Keycard 3.1").
   - **Authenticity** (the identity-proof result).
2. **Check authenticity automatically on card load.** When a card is selected, run
   `check_identity` (no PIN) and show the result in the Authenticity row
   ("Verified by Keycard" / "Not certified by Keycard" / "Could not verify"). Remove the
   manual "Check authenticity" action; the fact is shown, not requested.
3. Keep the deeper read on demand: a **"More details"** button (renamed from "Card
   details") runs `status` for the live counters (PIN/PUK attempts left, free pairing
   slots, on-card name) in the op modal.
4. The fingerprint is copyable (`LogosCopyButton`), since operators compare and paste it.

## Consequences

Positive:

- The card's identity and trust are visible at a glance, without knowing to press anything.
- Authenticity, the most security-relevant fact, is verified every time a card is selected.
- The fingerprint is one tap to copy; the deep, card-touching read stays explicit.

Costs:

- The auto authenticity check touches the card (opens a secure channel / requests an
  identity proof) on every card selection. This is the deliberate tradeoff for having the
  fact always present. A card whose applet cannot prove identity shows "Could not verify".

## Corrections folded in

- Authenticity is **not** 4.0-only. The module attempts an identity proof on 3.x applets
  too; a 3.2 card verified against a trusted Keycard certificate in live testing. An
  earlier guard that skipped 3.x cards was removed.
- `freePairingSlots` is available on the `cards()` object and in `status`; only `pukRetries`
  is status-only (see `docs/upstream-keycard-module-gaps.md`).

## Alternatives considered

1. Keep authenticity behind a button (ADR-C's form). Rejected: a trust signal the user must
   remember to check is a trust signal most users never see.
2. Put all of `status` inline on load. Rejected: `status` reads counters that change and is
   a heavier card interaction; it stays behind "More details", while the stable facts
   (name, fingerprint, version, authenticity) are shown directly.
