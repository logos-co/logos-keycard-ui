# ADR-O: Administration and Wallets presentation pass (card name, icons, account cards, primary CTA)

- Status: Accepted
- Date: 2026-11-14
- Scope: `keycard_ui` (UI only; QML + two icon assets; no backend or `.rep` change)
- Issue: #2 (refines ADR-K and ADR-N)

## Context

A dogfding pass over both tabs surfaced presentation issues, not capability gaps:

- **Administration showed the wrong "Card name".** The header read the app's *saved wallet* name
  (usually empty → "No name"), while the card's actual stored name (e.g. "Realify") was only visible
  by opening the Card details modal. The on-card name is readable with a `status` call, which needs
  **no PIN**, so it can be shown directly.
- **The Card details modal was noisy.** It led with the op's success string ("Card status read."),
  repeated the name now shown in the header, and carried "Private keys: present", which belongs on
  the always-visible card, not behind a button.
- **Key id and the detail rows were visually off.** The full keyUid (64 hex) was shown untrimmed,
  and the copy buttons (24 px) made the rows they sat on taller than the plain-text rows, breaking
  the vertical rhythm.
- **The Wallets cards under-used the connection/account structure.** A connected card with no
  accounts was titled as a wallet; "Add accounts" was a top-right secondary button; rename/forget
  were text buttons; accounts were divider-separated rows; and the primary action did not read as
  primary.

## Decision

**Administration**

1. The header **"Card name"** shows the name stored on the card, read with a no-PIN `status` call on
   card select (and re-read after "Update card name"). It shows **"Checking…"** while reading and
   **"empty"** only once the read returns no name, so it never flashes "empty".
2. The card's management button is **"Update card name"** (was "Name stored on card").
3. Detail rows: **"Card fingerprint"** (the card's instanceUid, was "Fingerprint"), a new **"Key id"**
   row (the keyUid, shortened `1234abcd…9876fedc` with the full value on the copy button), and a
   **"Private keys: present / not loaded"** line (derived from whether a keypair/keyUid is present).
   Copy buttons shrunk to 18 px and vertically centred so every detail row has the same height.
4. The **Card details modal** is reduced to what it alone provides: `PIN attempts left · PUK attempts
   left` and, on 3.x, `Free pairing slots · This app's slot`. The success string, the name, and the
   private-keys line are gone (the first is noise, the other two moved to the card).

**Wallets**

5. Content column is capped to **560 px and centred**, matching Administration.
6. A connected card with no accounts is titled **"Unknown wallet"** (context is the Keycard app, so
   "Keycard" is dropped) and its transport line omits the redundant **"· Connected"**.
7. **Add accounts** is a **full-width primary (orange) button under the connection line**, above the
   accounts when there are any; it is the one clear call to action.
8. **Rename → an edit (pencil) icon beside the wallet name; Forget → a trash icon at the far right**
   of the header. Any other wallet action (e.g. Verify) stays as a top-row button.
9. **Accounts render as filled cards** (`backgroundSecondary`, rounded), like the connection strip,
   instead of divider-separated rows. Each account carries an **edit icon by its name and a Remove
   trash icon at the far right** (replacing the "Rename…"/"Remove" text buttons).
10. The **card name is shown on the reader transport line** when readable pre-PIN
    ("Card reader · Realify · card 1234abcd…"), read with the same no-PIN `status` call and **cached
    per card** in the view. The cache uses a pending guard so the read (which triggers a refresh)
    cannot loop: it fires once per card, then serves from cache.
11. Hover affordances: a **subtle fill change on an account card** on hover, and the **edit/trash
    icons tint to white** on hover (resting muted).

## Consequences

Positive:

- The name the user set on the card is visible where they look first, in both tabs, with no tap.
- The Card details modal carries only what is not already on the card.
- The Wallets card reads as wallet → connection → accounts, with one obvious primary action and
  consistent, discoverable per-item controls.

Costs:

- The transport-line card name is cached per session, so renaming a card in Administration does not
  refresh that line until the card reconnects. Acceptable; a cache invalidation can be added if it
  bites.
- Two no-PIN `status` reads now happen on card events (header + transport line); bounded by the
  pending guard and card-change frequency, and each is the same read "Card details" already made.

## Alternatives considered

1. **Expose the card name through the backend `cards()` object.** Cleaner long-term (one source for
   both tabs), but it is a C++/module change; the name is not in `cards()` today (it comes from a
   separate GET DATA that `status` performs). The UI-side cached read keeps this ADR pure QML; the
   backend route is the eventual home if more views need the name.
2. **Keep "Add accounts" secondary.** Rejected: it is the primary thing to do on a connected card,
   so it should read as the primary action.
3. **Keep accounts as divider rows.** Rejected: filled cards match the connection strip, give each
   account its own hover and action targets, and read as discrete items.
