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

## 5. No Keycard Shell udev rule ships, so the Shell is root-only on Linux (every user hits this)

- **What / owner:** packaging/docs (Keycard Shell support in `keycard_shell_module` + the
  Basecamp installer), not `keycard_ui`. On Linux the Keycard Shell (USB HID, VID:PID
  `1209:21f7`, "Status Research & Development / Keycard Shell") enumerates as a `/dev/hidraw*`
  node owned `crw------- root root`. A normal desktop user cannot open it, so "Add accounts via
  Shell" → "Show accounts" fails every time with `hidapi error: failed to open device with path
  /dev/hidrawN: Permission denied (os error 13)`. Nothing ships a udev rule to grant access.
- **Why it matters:** this is not an edge case; it is the default state of a freshly plugged
  Shell on any Linux box. The Shell is connected, unlocked, latest firmware, and the feature is
  simply unreachable until the user knows to write a udev rule by hand. Hardware wallets
  (Trezor, Ledger) all ship such a rule precisely because of this.
- **Evidence (live):** `/dev/hidraw14` = `crw------- root root`; `lsusb` → `1209:21f7 Generic
  Keycard Shell`; `udevadm` attrs `idVendor==1209 idProduct==21f7`, product "Keycard Shell".
  Fixed locally with `/etc/udev/rules.d/51-keycard-shell.rules`:
  `KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1209", ATTRS{idProduct}=="21f7",
  MODE="0660", GROUP="plugdev", TAG+="uaccess"` (+ the matching `SUBSYSTEM=="usb"` line), then
  reload + re-plug.
- **Proposed fix:** ship `51-keycard-shell.rules` with the Linux package (or the AppImage's
  first-run / docs), and detect EACCES at runtime to point the user at it (see #6).

## 6. EACCES on the Shell HID node is misreported as "disconnected / turns itself off" (misdiagnosis)

- **What / owner:** `keycard_shell_module` error mapping (the message is backend text the UI
  only displays; it is not in `keycard_ui`). When opening the Shell's HID node returns
  `Permission denied (os error 13)`, the surfaced message is: "the Keycard Shell disconnected;
  it turns itself off after a few minutes without a press: turn it on, unlock it and try again
  (hidapi error: failed to open device ... Permission denied (os error 13))".
- **Why it matters:** the message sends the user down the wrong path entirely, power-cycling and
  re-unlocking a Shell that is connected, on, and unlocked, when the actual fix is a one-time
  host permission change (#5). The real cause (`os error 13`) is even quoted in the same string,
  then contradicted by the prose.
- **Evidence (live):** the screenshot message above, with a confirmed-connected Shell
  (`/dev/hidraw14` present, `lsusb` shows it) whose only problem was the root-only permission.
- **Proposed fix:** special-case EACCES / `os error 13` (distinct from a genuine open-after-gone
  / timeout) with an actionable message, e.g. "Can't access the Keycard Shell: this Linux user
  lacks permission for its USB device. Install the Keycard Shell udev rule (see docs) and
  re-plug the Shell." Keep the "turns itself off" copy only for an actual disconnect/timeout.

## 7. Keycard Shell re-prompts the "Connect wallet" consent per exported key (device/firmware)

- **What / owner:** Keycard Shell firmware (and/or `keycard_shell_module` host session handling),
  not `keycard_ui`. Exporting several public keys in one batched request makes the Shell show its
  "Connect wallet / asking to export public keys" consent screen **once per key**, each awaiting a
  separate OK, instead of consenting once for the connection. Listing a page of accounts needed
  ~4 OKs.
- **Why it matters:** the consent wording ("export public **keys**", "a wallet you want to use
  your Shell with") reads as a per-connection authorization, and the app's own model (its info
  panel) says the master public key is confirmed once per USB connection and reused until the
  Shell disconnects or the app restarts. The per-key re-prompt contradicts both, and makes the
  first-run "add accounts" flow feel stuck.
- **Evidence:** video (phone recording of the Shell showing the identical "Connect wallet" prompt
  on consecutive confirmations); `KeycardView.qml` sends **one** batched `addAccounts` call with
  all derivation paths (`show()` → `run("preview", { entries })`), so the loop is below the app.
- **Our app-side mitigation (not the fix):** the preview page size is now 1 for Shell connections
  (`addSheet.pageSize = root.shell ? 1 : 5`), so the common "add one account" flow is a single OK;
  adding several still costs one consent per key. Filed upstream:
  https://github.com/keycard-tech/keycard-shell/issues/237 (draft in
  `docs/drafts/keycard-shell-issue-export-reconsent.md`; video attached by Alisher via the web UI).
- **Maintainer verdict (bitgamma, Shell firmware author, on #237):** not a firmware bug. Per-export
  confirmation is intentional. The fix is **host-side**: *"you should not export the keys
  one-by-one, but rather only export the xpub of `m/44'/60'/0'` and derive the leaves host-side.
  This way you only need to export a single public key and can derive as many addresses as you want
  in milliseconds, without round trips."*
- **Where the fix lands:** `keycard_shell_module` (Dario's), not `keycard_ui`. The per-leaf device
  export is inside that module — `keycard_ui_backend.cpp` calls
  `keycard_shell_module.add_accounts()` / `add_status()` with leaf entries; the UI only passes paths
  and shows results, so it cannot collapse the round-trips. The module should export the
  account-level extended public key (xpub + chain code at `m/44'/60'/0'`) once, then derive the
  requested leaf public keys / addresses host-side (BIP32 non-hardened), as the UI backend already
  does for Bitcoin display addresses (`keycard_ui_backend.cpp:171`). Same applies to `keycard_module`
  for inserted cards. Measured cost today: ~2 taps first-use overhead per connection + 1 tap per
  address (5 addresses = 5 taps; 1 address on a fresh connection = 3 taps). With the xpub approach:
  **1 tap, any number of addresses.**
- **Interim mitigation in `keycard_ui` (shipped):** preview page size of 1 for Shell
  (`addSheet.pageSize = root.shell ? 1 : 5`), so the common add-one-account flow is the minimum the
  module allows. Remove once the module exports the account xpub and derives leaves.
- Filed for the module owner: https://github.com/logos-co/logos-keycard-shell-module/issues/9
  (draft: `docs/drafts/keycard-shell-module-xpub-derive.md`).
