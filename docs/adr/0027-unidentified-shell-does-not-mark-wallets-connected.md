# ADR-0027: An unidentified Shell must not mark every wallet connected (backend fix)

- Status: Accepted
- Date: 2026-11-18
- Scope: `keycard_ui` **backend** (`keycard_ui_backend.cpp` `refresh()`); C++, needs a module rebuild
- Issue: #2 · upstream report: logos-co/logos-keycard-ui#11

## Context

Plugging in a USB Shell turned a clean Wallets view (three "Locked wallet" cards) into a chaotic
mix: several **"Unknown wallet"** cards with an enabled **"Add accounts"** that could not work. Live
per-wallet logging pinned the cause in `refresh()`:

```cpp
for (each seed: wallet)
  for (auto v : shellDevices) {
    ...
    connection["verification"] = verified.isEmpty() ? "pending"
        : wallet.id == "seed:" + verified ? "verified" : "different";
    ...
    wallet["connected"] = true;   // unconditional, for every wallet and every Shell
  }
```

It computed a correct per-wallet `verification` ("pending" / "verified" / "different") and then marked
the wallet `connected` **regardless of it**. `connected` feeds the view's visibility rule: a seed
wallet with no accounts, not locked, not named is residue and is hidden unless connected. A connected
but **unidentified** Shell (verification "pending", its seed unknown until Identify) flipped **all**
seed wallets to `connected: true`, un-hiding every residue wallet. This also contradicted the comment
on the line above: *"Session verification is temporary: never turn USB presence into a saved seed
association."*

Evidence: before the Shell, every seed `connected:false, conns:1` → 3 visible (the locked ones);
after an unidentified Shell, every seed `connected:true, conns:2` (the Shell appended to all).

## Decision

In `refresh()`, **skip a Shell that is not verified for the current wallet** before touching its
connections or `connected`:

```cpp
if (verified.isEmpty() || wallet.value("id").toString() != "seed:" + verified) continue;
```

A pending (unidentified) or different-seed Shell therefore never becomes a connection on a wallet it
may not belong to, and never marks it connected. Only a Shell verified for **this** wallet adds its
connection and sets `connected`.

## Consequences

Positive:

- An unidentified Shell surfaces only as the "Shell connected / Identify" notification (as its own
  copy always intended); the saved wallet list is untouched until the person identifies the Shell.
- After Identify, the one matching wallet shows connected; the rest stay as they were.
- No more residue "Unknown wallet" cards or dead "Add accounts" on Shell plug-in.

Costs / follow-ups:

- This is a C++ backend change, so it ships via a module rebuild, not the QML hot-reload path.
- The fix lives on the fork; the same bug is in upstream (`logos-co/logos-keycard-ui`, commit
  `c4f186d`, PR #3) and is reported as issue #11 there, with a PR offered.

## Alternatives considered

1. **Work around it in the view** (a stricter "really connected" that ignores a pending-Shell
   connection). Rejected: it papers over wrong backend data that other consumers would also trip on;
   the data should be correct at the source.
2. **Keep per-wallet "pending"/"different" Shell connections for strip display.** Rejected: showing a
   pending Shell on every wallet is exactly the noise being removed; the Shell's own notification is
   the right surface before Identify.
