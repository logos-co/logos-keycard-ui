# Upstream gaps found dogfooding keycard_ui (for the module owner)

Draft notes for the owners of `keycard_module` / `keycard_ui` (Dario), found running the
app on a real Keycard (ACS ACR39U reader, a 3.1 card holding keys). Nothing here has been
sent upstream yet. Each item says what, why it matters, the evidence, and a proposed fix.

## 1. `cards()` does not report bare readers (connection status)

- **What:** `keycard_module.cards()` returns "the readers holding a card" only. A connected
  reader with no card, and no reader at all, are indistinguishable from the UI.
- **Why:** the header connection chip (ADR-B) wants three states: card present (green),
  reader connected but empty (yellow), no reader (red). Only "card present" is derivable
  today; the empty case collapses to one honest "No card detected".
- **Evidence:** `keycard_module.lidl`, `cards()` description; `KeycardView.qml` connection
  chip derivation.
- **Proposed fix:** a `readers()` method, or include empty-reader entries in `cards()`
  (a reader with no `adminId`/`keyUid`), so the UI can tell empty-reader from no-reader.

## 2. `pukRetries` is not on the `cards()` list object (only in `status`)

- **What:** `pukRetries` is returned by the `status` action (confirmed live: Card details
  shows "PUK attempts left: 5"), but it is not a field on each `cards()` entry. Note the
  correction: `freePairingSlots` **is** available, both in `cards()` (the `CardInfo`
  struct's `free_pairing_slots`) and in `status`, so it is not a gap.
- **Why:** this is a minor convenience, not a missing capability. Status gates a PUK-frozen
  card (`isBlockedPUK`) to factory-reset only at the list level. We can only reach that
  state after a `status` read, so a frozen card still lists actions that will fail until the
  user reads its details (ADR-E, limit). Everything stays safe (the module rejects the
  impossible call and factory reset, the correct exit, is always offered).
- **Evidence:** `rust-lib/src/card.rs` `CardInfo` (has `pin_retries`, `free_pairing_slots`;
  no `puk_retries`); `rust-lib/src/admin.rs` `status` result (has `pukRetries`,
  `freePairingSlots`).
- **Proposed fix:** add `pukRetries` to each `cards()` entry, alongside `pinRetries`, so the
  action list can match Status without a prior `status` read. Low priority.

## 3. `message` is written but never declared in `CardAdministration.qml` (bug, fixed here)

- **What:** `CardAdministration.qml` assigned `message` in `perform()`, `selectCard`,
  `onChangedChanged`, `onActionChanged` and more, but never declared it as a property. In
  QML strict mode a write to an undeclared property throws, aborting the function right
  after `busy = true`, which left **every** administrative action locked on a real card.
- **Why it was invisible:** the admin panel had only been exercised by doctests, never
  driven on real hardware, so the throw never fired in CI.
- **Evidence:** host log `CardAdministration.qml:<n>: Error: Invalid write to global
  property "message"`, repeated; the panel locks (all buttons disabled, `busy` stuck true).
- **Fix (applied in our fork):** declare `property string message: ""` on the root. One
  line. Worth upstreaming regardless of the rest of our UI changes.

## 4. The `.#install` target tags the variant `linux-amd64-dev`, which the host rejects

- **What / owner:** this is build-tooling (`logos-module-builder` / the host loader), not
  `keycard_module` proper, but it was found here and is worth routing. `nix build .#install`
  produces a plugin whose `manifest.json` has `main: { "linux-amd64-dev": ... }` and a
  `variant` file of `linux-amd64-dev`. The host accepts only `linux-amd64` /
  `linux-x86_64`, so it logs "installed for variant 'linux-amd64-dev' ... will not be
  loadable", binds no native backend for the supported platform, never registers the
  view-module socket (`qmlbridge: no socket registered for view module "keycard_ui"`), and
  the app hangs on "Starting". The QML view still loads via the launcher, which masks it.
- **Why it matters:** `.#install` is the obvious dev-install target, and its output looks
  correct (the UI renders) while being silently unloadable at the backend. The working path
  is `.#lgx-portable`, whose variant is `linux-amd64`.
- **Proposed fix:** either have the host accept the `-dev` variant suffix for a local dev
  install, or have `.#install` tag the host's platform name, or document that only the
  `.lgx` build is host-loadable.
