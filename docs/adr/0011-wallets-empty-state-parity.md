# ADR-K: Wallets empty state matches administration

- Status: Accepted
- Date: 2026-11-14
- Scope: `keycard_ui` (UI only; no backend or `.rep` change)
- Issue: #2 (extends ADR-G)

## Context

ADR-G made "no administrable card" a first-class, centered empty state on the Administration tab,
with a hardware-acquisition link ("Get a reader"). The Wallets tab, reached first, still rendered
its no-card case as two left-aligned sentences flush under the tab bar ("Connect a Keycard reader
or a Keycard Shell over USB. Your keys stay on the card." / "Connect a Keycard to add your first
wallet."). The two tabs of one view treated the same "nothing is connected" condition in two
different visual languages, and the Wallets one, the landing surface, gave no path to acquiring a
Keycard at all.

## Decision

Give the Wallets tab the same empty-state treatment as Administration.

1. Show the centered empty state when **there are no saved Keycard wallets**
   (`root.wallets.length === 0`), not when no device is connected. The Wallets tab lists saved
   wallet groups, which persist across sessions and across unplugging the card: a saved wallet with
   its card currently absent must still render as a (device-disconnected) wallet card, not be
   hidden behind the empty copy. Gating on "no device" wrongly showed the empty state over an
   existing saved wallet; gating on "no wallets" is the correct condition.
2. The empty state is a centered column: a bold title (**"No Keycard wallets added"** — the
   accurate description of the state, since a Keycard may be connected and simply hold no added
   wallet), one line of guidance ("Connect a Keycard reader or a Keycard Shell over USB to add your
   first wallet. Your keys stay on the card."), and an acquisition row.
3. The acquisition row carries a **"Get a Keycard"** link to `https://keycard.tech/` with a copy
   button, mirroring ADR-G's "Get a reader" affordance (link opens the browser and also copies the
   URL, since the plugin sandbox may refuse `Qt.openUrlExternally`; the copy is the reliable
   fallback). Administration links the reader product page because that is its missing piece; the
   Wallets landing links the Keycard site itself, the first thing a new person needs.
4. The separate card-present-but-no-wallets line is removed: the single "no wallets" empty state
   now covers that case too.

## Consequences

Positive:

- Both tabs speak one visual language for the same empty condition; the view feels like one app.
- The Wallets landing, where a newcomer arrives, now hands them the next step (get a Keycard)
  instead of only describing what is missing.

Costs:

- A second external store URL is baked into the UI (`keycard.tech`), alongside ADR-G's reader URL;
  if either page moves, the link and its copied value must be updated together.

## Alternatives considered

1. Leave the Wallets text as-is. Rejected: two empty-state styles in one view, and the landing tab
   offered no path to acquiring the hardware it requires.
2. Link the reader page here too (same URL as Administration). Rejected: a person with no Keycard
   at all needs the Keycard site first; the reader page is the right target on the Administration
   tab, where the card exists but a direct reader may not.
3. Gate the empty state on "no device connected". Rejected: saved wallets persist with the card
   unplugged, so this hid real wallet cards behind the empty copy; the correct gate is "no saved
   wallets".
