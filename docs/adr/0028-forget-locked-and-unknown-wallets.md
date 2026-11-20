# ADR-0028: Forgetting a locked or unknown wallet that was reset or lost

- Status: Accepted
- Date: 2026-11-20
- Scope: `keycard_ui` — view (`KeycardView.qml`, `accountkit/WalletCard.qml`) and **backend**
  (`keycard_ui_backend.cpp` `forgetSavedCard`); C++ change needs a module rebuild. Companion
  change in `logos-keycard-shell-module` (`store.rs` `forget_wallet`).

## Context

After testing with real cards (cards reset, rewritten, or physically gone), wallets stayed in the
Wallets list that the person no longer has any access to — shown as **"Locked wallet"** or
**"Unknown wallet"** — with **no way to remove them**. Three separate gates each blocked the forget:

1. **The action was never offered.** `walletActions(g)` returned early for an unknown wallet or a
   card with no seed (`if (unknown || cardNoSeed(g)) return add`), so the overflow menu had no
   "Forget wallet…". But a wallet *committed on this computer* — locked, named, or with saved
   accounts — has local data to remove even when its card is gone.
2. **The trash icon was hidden on locked cards.** `WalletCard.qml` gated the Forget icon on
   `!card.locked`, so even where the action existed it could not be reached on a locked card.
3. **The backend failed the forget.** `forgetSavedCard` required *every* store that listed the
   wallet to report success, and `&`-chained them. A wallet lives in one store (a reader card or the
   Shell); the other store legitimately answers **"Unknown wallet"**. A connected Shell that lists
   but does not own a wallet made the whole forget fail on that benign reply.

A fourth gate lived in the Shell module and is fixed there (see Companion change): its
`forget_wallet` recognised a wallet only by a saved **name**, and `save()` only drops *readable*
documents — so a locked wallet known only by its **sealed** document could never be removed and
re-appeared from `closed()`.

## Decision

- **Offer Forget for any committed wallet** (`KeycardView.qml`). Add
  `committed(g) = hasAccounts(g) || g.locked === true || !!g.name`. For an unknown wallet or a
  seedless card, still suppress Rename (nothing to rename), but offer **Forget** when the wallet is
  committed:

  ```qml
  if (unknown || cardNoSeed(g))
      return root.committed(g)
           ? add.concat([{ id: "forget", label: "Forget wallet…" }])
           : add
  ```

- **Show the trash icon whenever a Forget action is offered** (`WalletCard.qml`), locked wallets
  included — `visible: !!card.trashAction` (dropping `&& !card.locked`). The action itself is still
  only offered for committed wallets, so this only surfaces a real control.

- **Make the backend tolerant** (`keycard_ui_backend.cpp`). Forget from each store that lists the
  wallet; treat a *not-owned-here* reply (`"Unknown wallet"` / `"unknown card"`) as benign, and fail
  only on a real error:

  ```cpp
  auto notOwnedHere = [](const QString &e) {
      return e.contains("Unknown wallet", Qt::CaseInsensitive)
          || e.contains("unknown card", Qt::CaseInsensitive);
  };
  auto tryForget = [&](const QJsonObject &reply) {
      if (reply.value("ok").toBool()) return;
      const QString e = reply.value("error").toString();
      if (!notOwnedHere(e)) { setLastError("Forget wallet: " + e); hardError = true; }
  };
  if (containsGroup(cardGroupsJson(), id))  tryForget(... keycard_module.forget_saved_card(id));
  if (containsGroup(shellGroupsJson(), id)) tryForget(... keycard_shell_module.forget_wallet(id));
  return !hardError;
  ```

## Consequences

Positive:

- A locked/unknown wallet whose card was reset or lost can be removed from the Wallets list.
- A connected Shell that lists but does not own a wallet no longer blocks forgetting it on the card.
- Nothing on any card is touched; forget still only drops local records.

Costs / follow-ups:

- The backend change ships via a module rebuild, not the QML hot-reload path.
- **Forget propagates to the Signer (`signer_manager`) only if that module is loaded when the
  Keycard modules start.** `signer_manager` is lazy-loaded (it comes up when the Signer app opens),
  and the Keycard modules subscribe to it **once**, at their own startup; if it is not up then, the
  subscription — and the catch-up reconcile sweep — never starts for that session. A wallet forgotten
  while the Signer app is closed therefore lingers in the Signer until a run where the Keycard
  modules start with `signer_manager` already up (open Signer first, then Keycard), when the sweep
  forgets it. The durable fix is to **re-subscribe to `signer_manager` when it loads late** (same
  lazy-load root as the enroll-on-reconnect gap, keycard-module#10); filed as a follow-up rather than
  shipped untested here.

## Companion change (logos-keycard-shell-module)

`store.rs` `forget_wallet` now recognises a wallet by *any* of a saved name, a connection, an alias,
an offered account, or a **sealed (locked) document**, and removes that sealed document explicitly
(so it does not re-appear from `closed()`). Without it, the originally-stuck "Locked wallet" (a
sealed Shell document from a reset card) could not be removed. Shipped as its own PR to
`logos-co/logos-keycard-shell-module`.
