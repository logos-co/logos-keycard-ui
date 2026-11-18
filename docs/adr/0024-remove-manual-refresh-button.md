# ADR-0024: Remove the manual Refresh button — the view is event-driven

- Status: Accepted
- Date: 2026-11-18
- Scope: `keycard_ui` (UI only; KeycardView + one asset; no backend or `.rep` change)
- Issue: #2

## Context

The header carried a Refresh button (top-right, circular-arrow icon) whose `onClicked` called
`backend.refresh()`. In extended dogfooding it was never needed, which prompted the question of
whether it earns its place.

Reading the backend (`keycard_ui_backend.cpp`) settles it. The view is **event-driven**: on
`onContextReady` the backend subscribes to `keycard_module` and `keycard_shell_module`
**`onSigner_changed`** (a card inserted or removed) and **`onSigner_accounts_changed`**, and each
fires `refresh()` on its own. The 500 ms `m_poll` timer is **not** card monitoring, it polls an
in-flight operation's status (`m_job`) and stops when the op finishes. So `cardsJson` and the wallet
list already update automatically on every card and account change; the button only re-ran the same
`refresh()` those events call.

Its one residual value was a manual fallback if the backend ever missed an event. Two things make
that weak: the natural recovery for a stuck view is to **re-seat the card**, which re-fires
`onSigner_changed` → refresh anyway; and the button would not fix a stale blocked-state read, since
`refresh()` repopulates `cardsJson` but the per-card status cache (`ensureCardName`, ADR-0023) is
guarded to read once per card, so an already-known card is not re-read on refresh.

## Decision

- **Remove the Refresh button** from the header (the `refreshButton` `LogosIconButton`), along with
  its `iconRefresh` property and the `assets/refresh.svg` asset.
- **Keep the backend `refresh()` slot unchanged.** It is still called automatically by the module
  events; only the manual UI control is gone.

## Consequences

Positive:

- Less header chrome for a control the person never uses; card insert/remove/account updates are
  unchanged, driven by the module events.

Costs / follow-ups:

- No one-tap "force a re-scan" if the backend ever drops an event. The recovery gesture is to
  re-seat the card (which re-fires the event). If a genuine stuck-state is ever observed, the honest
  place for a manual re-scan is the empty / "No card detected" state, not a permanent header button.

## Alternatives considered

1. **Keep the button as a belt-and-suspenders fallback.** Rejected: it is permanent chrome for a
   path already covered automatically, and its fallback case has a natural gesture (re-seat).
2. **Move it into the empty / "No card detected" state only.** Not done now (no stuck-state has been
   observed), but noted as the place to add a manual re-scan if one is ever needed.
