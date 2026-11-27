# Keycard app: how it behaves

One section per behaviour. Each says what the app does and why, in the words the code follows.

## Two areas: Wallets and Card administration

The app has two tabs. **Wallets** lists the Keycard wallets saved on this computer and their accounts.
**Card administration** manages the card in a reader: set it up, its PIN and PUK, its recovery keys,
its name, pairing, factory reset. Administration is a tab, not a modal, so a card's state and its
actions are in view together.

## Connection status in the header

The header says only what the app can observe:

| State | Chip |
|---|---|
| Before the view module is ready | "Starting", then "Not responding" (warning) after 15 s |
| A card in a reader | "Card connected" (success) |
| A Shell over USB, no card | "Shell connected" (success) |
| A reader with no card in it | "Reader: no card" (warning) |
| No reader | "No reader" (warning) |

`keycard_module.readers()` lists empty readers too, which is what tells "Reader: no card" from "No
reader". The view is event-driven: there is no manual Refresh button.

## Wallets

A wallet is a keypair, identified by its master key (`seed:<keyUid>`). Cards holding the same seed
share one wallet, across readers and Shells; a different recovery passphrase makes a different
wallet.

- **Known wallet** (accounts saved): titled with its name, or `Keycard wallet <master fingerprint>`.
  The **Wallet ID** is the BIP32 master fingerprint, the same one the Signer and Keys apps show; the
  keyUid is only in its tooltip. Actions: Add accounts, Rename…, Forget wallet…
- **Unknown wallet** (a connected Keycard with no accounts saved): "Unknown wallet", Add accounts
  only.
- **No wallet yet** (a reader card holding no seed): "Keycard · no wallet yet", no Add accounts, and
  a note to create or import a recovery phrase in Card administration.
- **Locked wallet** (sealed until unlocked in the Signer): "Locked wallet", with Unlock as the
  primary action.
- A seed record with no accounts, no name, not locked and no device connected is residue from a past
  card and is not listed. A keyless card's "not identified yet" entry shows only while it is
  connected.

Each wallet lists its connected devices as strips: "Card reader" with the card's on-card name and id
and a **Card administration** action, or "Shell USB" with its serial. A card the person trusted
without Keycard's certificate gets a warning strip with **Stop trusting**.

Accounts are named by family and index ("Ethereum 0") unless the person names them.

The empty state, when no wallet is saved, says "No Keycard wallets added" with one line on how to
connect a reader or a Shell.

## Shells

The backend connects a Shell only to the wallet it verified, or, until it is verified, to a wallet
that used it before; a strip says "verified" or "verify on first use". (A Shell never marks every
wallet connected.)

A connected Shell that hasn't confirmed its seed in this session (`verifiedMasterKeyId`, which the
Shell module drops when it disconnects) also shows as one dismissible notification with **Identify**,
styled apart from wallet cards, plus a yellow header chip. Identify is one request: the Shell
confirms its master public key on its screen, then folds into its wallet (names kept) or opens as a
new unknown wallet. A dismissed notification comes back when that Shell is plugged in again. There
is no "Verify wallet…" button on each wallet.

## Forgetting a wallet

Forget removes the wallet's saved accounts and name from this computer; nothing on the card or
Shell is erased. It is offered for any wallet the person committed to: one with accounts, a name, or
locked (so a locked wallet whose card was reset or lost can still be removed).

- A seed wallet (`seed:` id) forgets with its card in the reader; afterwards the card shows as one not
  added yet.
- Any other card id needs the card out first, because an inserted card would be remembered again at
  once. The dialog says so and Forget stays disabled.
- The backend forgets from each store that lists the wallet and stops at the first refusal, so a
  wallet is never left half-forgotten.

## Adding accounts (guided flow)

`AddAccountsFlow` is a one-step-per-screen dialog with a title line that keeps the wallet and
connection in view:

1. **Choose**: Ethereum or Bitcoin (Native SegWit or Taproot; Bitcoin or test networks) and the first
   index, with the derivation path shown live.
2. **Authorise**: the card's PIN as circles (a 3.x card that needs pairing pairs here). A Shell has
   no step here: it asks on its own screen, so its flow has three steps.
3. **Select**: a page read from the device, five accounts a page (Bitcoin on a Shell one at a time,
   since each hardened account is its own export); accounts already added are marked.
4. **Name**: optional, per account.

A wrong PIN on the read returns to Authorise with the attempts left. The outcome arrives on the
backend's `exporting` state.

## Card administration

With one card in a reader it is selected at once; a picker appears only with two or more. With none,
an empty state says "No Keycard to administer" with a link to get a reader (a Shell signs, but its
card has to move into a reader to be administered).

**Details** shows the on-card name as the title ("Keycard" when it has none), then the card
fingerprint, key id, applet version, whether private keys are present, and authenticity, checked
automatically with no PIN ("Verified by Keycard", "Not certified by Keycard", "Could not verify").
**More details** (initialized, paired cards) shows PIN and PUK attempts left and, on 3.x, pairing
slots. Card details and authenticity are information, not actions: they need no PIN and answer in a
small read-only dialog.

### Which actions a card offers

Mirrors the Status desktop Keycard management UI, reduced to what `keycard_module` exposes:

| Card state | Actions |
|---|---|
| Not set up (no PIN) | Set up card |
| 3.x, not paired | Pair this app; Factory reset |
| PUK used up | Factory reset only |
| PIN blocked | Unblock PIN; Factory reset |
| No seed | Create recovery phrase; Import recovery phrase; Generate keys without backup |
| Seed present | Check recovery phrase; Erase keys |
| Any usable card | Change PIN; Change PUK; Update name; and, under **Advanced** (collapsed): change pairing password, remove a pairing slot (3.x), NFC text, read and write card data |

Destructive actions (Erase keys, Factory reset) are red and need a typed confirmation. The list waits
behind "Reading card…" until the card's state is known, so the wrong set never shows first.

### Blocked state and re-reading the card

Whether a card is blocked comes from the no-PIN `status` read (`pinRetries`, `pukRetries`), not from
`cards()`, whose `pinRetries` can be stale and which has no `pukRetries`. The read runs when a card is
inserted and is kept per card; a card taken out leaves nothing behind, so a card put back in is read
again. After **every** card operation, done or refused, the card is read again, so a successful
Unblock PIN clears the blocked state and a PIN blocked by wrong entries shows at once.

### Guided operations (`CardFlow`)

Every operation runs as a guided flow: a title line (the operation, and the card's name and Wallet
ID), "Step N of M", one input per screen, then working, success or error. PINs and PUKs are entered
as circles (`PinDots`): digits only, fixed length, masked and not selectable, so they can't be
copied. Recovery phrases use a word grid; a generated phrase is shown for backup, confirmed with
three of its words, then loaded with the PIN already entered.

- The flow branches on the reply's `code`, never its wording. `WrongSecret` is a wrong PIN, PUK or
  pairing password: the flow returns to that step and shows the attempts left, read from the card.
  A blocked PIN or PUK has no code of its own yet (it comes back as `Unavailable`), so the flow reads
  the card's attempts and 0 means blocked; any other `Unavailable` is shown as the error it is.
- On Create, a wrong PIN while loading the phrase already shown retries loading that phrase.
- On a Keycard 4.0, the PUK's first six digits become a second (alternate) PIN, so setting up a card
  refuses a PUK that starts with the chosen PIN, at the PUK step.
- Changing the PIN refuses a new PIN equal to the current one; weak PINs (000000, 123456, …) get a
  warning.

## App icon

The real Keycard logo, full-bleed on a black 256×256 square; Basecamp rounds the tile.
