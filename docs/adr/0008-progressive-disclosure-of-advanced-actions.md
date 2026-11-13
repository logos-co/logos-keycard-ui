# ADR-H: Progressive disclosure of advanced actions

- Status: Proposed
- Date: 2026-11-13
- Scope: `keycard_ui` (UI only; no backend or `.rep` change)
- Issue: #2 (refines ADR-A and ADR-E)

## Context

ADR-A replaced the operation dropdown with a visible, risk-grouped action list, and ADR-E
gated that list to the actions a card's state allows. For an operational card the list is
still long, and some of its actions are expert or rarely used: pairing-slot management
(change pairing password, remove a slot), NFC text, raw public-data read/write, and
generating keys with no backup. Shown flat with the everyday actions, they add length and
noise to the common path, and several carried an "(advanced)" suffix in their own label to
signal this, which is redundant with grouping.

## Decision

Group the actions into three tiers and collapse the expert one.

1. Three tiers, in this order:
   - **Set up and keys** (visible): initialize, pair, create/import/check recovery phrase,
     change PIN, change PUK, unblock PIN, name on card.
   - **Destructive** (visible): erase keys, factory reset. These stay visible, with their
     existing typed-confirmation gates.
   - **Advanced** (collapsed behind a chevron, placed **last**): change pairing password,
     remove a pairing slot, NFC text, read/write card data, generate keys without backup.
2. The Advanced group is hidden by default and unfolds on a tap of its "▸ Advanced" header.
3. Drop the "(advanced)" suffix from the labels; the group conveys it.

This amends ADR-A's "all available actions visible at a glance" for the expert subset: the
re-balance is that *common* actions stay instantly visible and uncluttered, while expert
actions remain one tap away, in a labeled place, rather than removed.

Destructive is deliberately **not** collapsed: erasing keys and factory reset are legitimate,
not-rare operator needs (a lost PIN, repurposing a card), and must stay discoverable. Their
safety comes from the typed-confirmation gates, not from being hidden.

## Consequences

Positive:

- The common path is short and uncluttered; the first screen of a card's actions is the
  everyday set plus the clearly-marked destructive two.
- Expert actions keep a stable, discoverable home, one tap away.
- Labels are cleaner without the redundant suffix.

Costs:

- One more interaction to reach an advanced action. Acceptable: these are expert and rare by
  definition, and the group name tells you what is inside before you open it.

## Alternatives considered

1. Keep everything flat (ADR-A as-is). Rejected: the list is long enough on an operational
   card that the rare actions crowd the common ones.
2. Collapse Destructive too. Rejected: erase/reset are not rare enough to hide, and hiding a
   destructive action is worse for discoverability than showing it with a confirmation gate.
3. Move advanced actions to a separate screen. Rejected: heavier than the problem; a
   collapsible group keeps them in context with the rest of the card's actions.
