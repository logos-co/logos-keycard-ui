# Keycard seed is enrolled with signer_manager only on keep(), fire-and-forget, with no re-enroll when the (lazy-loaded) manager appears

**For:** `logos-co/logos-keycard-module` (rev `e36717ff`), found dogfooding Basecamp 0.3.2 on Linux
with a real Keycard (ACS reader, a 3.1 card holding a seed).

**TL;DR:** A Keycard wallet can end up permanently absent from `signer_manager_module`, so
`eth_wallet` / `tx_sender` refuse to sign for its accounts ("this account's wallet isn't known yet").
The enrollment into the signer manager happens once, on `keep()` (Add accounts), as a fire-and-forget
call; `signer_manager_module` is lazy-loaded; if it is not running at that instant the enrollment is
lost, and nothing re-enrolls when it later appears. The reconnect path only opens and names seeds the
manager already knows.

## What happens

1. Registration is `enroll_seed`, fired from `Events::seed_added` as a fire-and-forget async call that
   ignores its result:
   `rust-lib/src/glue.rs:107` -> `wallets::WalletsClient::bind(WALLETS).enroll_seed_async(&body, |_| {})`.
2. `seed_added` fires only from `Shared::keep()` ("Keep exported accounts, and register their seed with
   its unlock key"): `rust-lib/src/signer.rs:484` and `:498`. The `unlockKey` is captured there, while
   the card is unlocked during the add.
3. `signer_manager_module` is loaded lazily, only when a UI that depends on it opens (`evm_signer_ui` /
   `evm_keystore_ui`). In our run it loaded 281 s into the session, exactly when the Keystore app was
   opened (host log: `Module loaded: signer_manager_module`, preceded by ~4.7 min of
   `keycard_module: signer_manager_module ... not reachable (deferred)`).
4. The wallet had been enrolled earlier, while the manager was not running, so the fire-and-forget
   `enroll_seed` was dropped. On the later `wallets_changed` re-arm, `watch_wallets` runs `open_wallets`
   and `sync_names` (`rust-lib/src/glue.rs:132` onward): `open_wallets` acts on `closed_seeds()` (seeds
   the manager has unlocked), and `sync_names` reads the manager's `wallets()`. Neither re-`enroll`s a
   seed the manager never received. `seed_added` does not fire again on restart or card re-seat, because
   the seed is already in the store, so the wallet stays unregistered.

## Impact

A Keycard account shows in `eth_wallet` (its account list comes from elsewhere) but Send fails with
"This account's history isn't open yet (this account's wallet isn't known yet). If its wallet is
locked, unlock it in the Signer app, then try again." Opening the Signer app does not help: it is what
loads the manager, but the card was enrolled minutes earlier. Re-seating the card and restarting the
Signer/Keystore apps do not help either, since neither re-fires `keep()`.

## Reproduce

1. Fresh Basecamp launch with a Keycard already in the reader, keys loaded, accounts previously added.
2. Do not open the Signer or Keystore app yet.
3. Open the ETH wallet, select the Keycard account, try to Send: "wallet isn't known yet".
4. Open the Keystore app (loads `signer_manager_module`); the wallet still does not appear, and Send
   still fails.

## Workaround (verified)

With `signer_manager_module` loaded (Keystore or Signer app open), Add accounts again on the wallet in
the Keycard app. That re-runs `keep()` -> `seed_added` -> `enroll_seed` into the now-running manager,
with the unlock key captured during the add. The wallet then appears in the Signer app and Send works.

## Proposed fix (any one)

1. Re-enroll known seeds when the `signer_manager_module` subscription (re)arms: in `watch_wallets`,
   on the first `wallets_changed` (or on connect), re-`enroll_seed` the seeds the module holds, not only
   `open_wallets` them. This needs the unlock key, so it may apply to seeds whose card is present and
   unlockable; persist or re-derive enough to re-enroll, or enroll without the key and let the manager
   request unlock.
2. Make `enroll_seed` resilient to a missing manager: queue and retry it when the manager appears,
   rather than dropping the fire-and-forget call.
3. Do not lazy-load `signer_manager_module` while a Keycard (or any signer-providing module) is present:
   boot it, or have `keycard_module` force it loaded, so the enrollment at `keep()` time always lands.

## Evidence pointers

- `rust-lib/src/glue.rs:107` (fire-and-forget enroll), `:132` (watch_wallets / reconnect path), `:159`
  (open_wallets over closed_seeds).
- `rust-lib/src/signer.rs:484`, `:498` (keep -> seed_added, unlock key captured here).
- Host log: `Module loaded: signer_manager_module` at T+281 s, right after `evm_keystore_ui` opened;
  preceding `keycard_module: signer_manager_module ... not reachable` warnings.
