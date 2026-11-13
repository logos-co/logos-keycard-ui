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

## 2. `cards()` does not return `pukRetries` (BlockedPUK gating)

- **What:** each card entry carries `pinRetries` but not `pukRetries`. `pukRetries` is only
  available from the `status` action result.
- **Why:** Status gates a PUK-frozen card (`isBlockedPUK`) down to factory-reset only. We
  cannot gate the action list to that state without first running `status`, so a frozen
  card still lists actions that will fail (ADR-E, limit 1).
- **Evidence:** `keycard_module.lidl` `cards()` field list (has `pinRetries`, no
  `pukRetries`); `docs/keycard-state-action-map.md`.
- **Proposed fix:** add `pukRetries` to each `cards()` entry, alongside `pinRetries`.

## 3. `cards()` does not return the free-pairing-slot count (no-slots gating)

- **What:** the free pairing-slot count is only in the `status` result
  (`freePairingSlots`), not in `cards()`.
- **Why:** Status hides content operations when a 3.x card has no free slots and no known
  pairing (`noKnownAndNoAvailablePairingSlots`), because no secure channel can be
  established. We cannot reproduce that gate at the action-list level (ADR-E, limit 2).
- **Evidence:** `status` result carries `freePairingSlots`; `cards()` does not.
- **Proposed fix:** include the free-slot count (and/or a `pairable` flag) in `cards()`.

## 4. `message` is written but never declared in `CardAdministration.qml` (bug, fixed here)

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

## 5. The `.#install` target tags the variant `linux-amd64-dev`, which the host rejects

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
