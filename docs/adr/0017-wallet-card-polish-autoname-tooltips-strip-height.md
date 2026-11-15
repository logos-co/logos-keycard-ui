# ADR-Q: Wallet-card polish — strip height, Unlock primary, account auto-naming, dark tooltips

- Status: Accepted
- Date: 2026-11-15
- Scope: `keycard_ui` (UI only; QML + roster.js; no backend or `.rep` change)
- Issue: #2 (follows ADR-O and ADR-P)

## Context

A dogfooding pass over the wallet cards surfaced four presentation issues, none a capability gap:

- **Transport strips had two different heights.** A strip with an action button ("Card
  administration") was visibly taller than one without ("Shell USB"), because `LogosButton` has a
  44 px minimum height (`LogosButton.qml:130`) that inflated only the button rows.
- **"Unlock" read as a secondary action** on a locked wallet, though it is the one thing to do there.
- **Every account auto-named "Ethereum".** Accounts of one wallet were indistinguishable by name, and
  carried a separate "account N" id line that, for EVM, merely repeated the last step of the
  derivation path shown right below it.
- **Tooltips were white in dark theme.** The code used the attached `ToolTip.text` form, which renders
  Qt's default (light) tooltip rather than the design system's `LogosToolTip`.

## Decision

1. **One strip height.** Single-line device strips share a fixed 40 px height, and a strip's action
   button is pinned to 30 px (with its vertical padding cut to match, or the label drops to the
   bottom of the shortened button) and vertically centred, so a strip with a button is no taller than
   one without. A wrapping strip (a multi-line warning) keeps its natural height.
2. **"Card administration" loses its trailing ellipsis** (it opens an inline tab, not a dialog that
   needs the "…" affordance).
3. **Unlock is a primary (orange) button** on a locked wallet.
4. **Accounts auto-name as family + index** — "Ethereum 0", "Ethereum 1" — instead of a bare
   "Ethereum", so accounts of one wallet are distinct. The **"account N" id line is dropped**: the
   index now sits in the name, and for EVM it only repeated the derivation path's last step. Naming is
   entirely UI: `rowTitle = label || <family + index>`; the add flow stores no label when the field is
   left blank, so a user rename still wins and nothing changes in core.
5. **Tooltips use `LogosToolTip`.** Every attached `ToolTip.text` usage across the account/wallet
   components is replaced with a `LogosToolTip` child (dark `backgroundSecondary`, themed text, with a
   directional arrow), so tooltips read correctly in dark theme.

The wallet id is deliberately **not** repeated in each account's auto-name (e.g. "1f994499: 0"): it is
already the card's title and Wallet ID row, so a per-account prefix is redundant inside the card, and
family + index keeps the chain context. The wallet-id form belongs to views that show accounts outside
their wallet (the Signer / Send lists), which compute their own labels.

## Consequences

Positive:

- Transport strips line up regardless of whether they carry a button.
- The locked state has one obvious action; accounts are distinguishable at a glance without a
  redundant id line; tooltips match the theme.

Costs:

- The strip height (40) and strip-button height (30) are layout constants; a future DS token would be
  tidier.
- Auto-naming is per-view: the same unnamed account may read differently here than in another app,
  which is expected (each view labels for its own context).
- Tooltips are now per-site `LogosToolTip` children rather than one attached call; the trade is more
  declarations for correct theming (the attached form cannot be pointed at a themed component).

## Alternatives considered

1. **Grow every strip to the button's natural 44 px height.** Rejected: the shorter text-only strip
   is the better look; the button should fit the strip, not the reverse.
2. **Auto-name as wallet id + index ("1f994499: 0").** Rejected inside the card for the redundancy /
   lost-chain-context reasons above; it is the right form only outside the wallet context.
3. **Theme the shared attached tooltip once at the view root.** Rejected: it mutates a window-shared
   instance and would leak into other views' tooltips; per-site `LogosToolTip` keeps it contained.
