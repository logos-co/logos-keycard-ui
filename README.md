# logos-keycard-ui

One Keycard app manages wallets through smart-card readers (`keycard_module`) and Keycard
Shell over USB (`keycard_shell_module`). The separate `keycard_shell_ui` is superseded;
install this UI and both backend modules, and remove the old Shell **UI plugin** from the
application's plugins directory. Keep its backend and module data: existing USB accounts
are loaded without importing them again. QR-based signing is outside this app.

The home screen lists wallets and their public accounts. **Add accounts** chooses Ethereum
or Bitcoin (native SegWit or, on supported cards, Taproot), an optional account name, and an
index. The next unused index is suggested; advanced controls allow a different index.
Ethereum uses `m/44'/60'/0'/0/i`; Bitcoin uses `m/84'/coin'/i'` or `m/86'/coin'/i'`.
Only public account material is saved. Signing stays with each transport's existing signer.

Wallets are grouped by `seed:<SHA256(SEC1-uncompressed-master-public-key)>`, matching
Keycard's key UID. The same seed on multiple cards, readers or USB Shells appears once.
Physical card IDs remain separate for pairing, trust and PIN operations. The add-account
connection selector chooses a reader or Shell; the backend checks the selected seed before
exporting accounts. Re-exporting an account preserves its saved label.

Reader wallet names are retained as the initial seed wallet names. Shell accounts saved by
older versions have only a four-byte fingerprint: **Identify wallet…** requests the master
public key and checks each saved account's full public key on the Shell before migrating it.
A short fingerprint alone never merges wallets. Existing names become aliases when named
wallets merge; duplicate accounts retain both labels until explicitly renamed. Account IDs
remain stable so existing app references survive. No private keys or chain codes are needed
for the wallet identity. All USB confirmations happen on the Shell.

**Manage…** contains wallet/account naming and removal. Reader connections also offer PIN/PUK
controls. Forgetting a seed wallet removes its local accounts and name, never card contents;
its reader cards must be disconnected first. Pairing and trust remain physical-card metadata.
The signer modules retain their own account offers: merging the display does not silently
export extra accounts or authorize signing. Shell signing verifies the root again and can
use another previously identified Shell connection for the same wallet.

Each wallet's accounts are sealed under a key the Signer app releases once the person unlocks
that wallet there. Until then the wallet shows as **Locked**, with no accounts, and its **Unlock**
raises `wallets.unlock` to open the Signer app.

Unsigned applet 4.0 cards still require explicit review of their identity and the existing
counterfeit warning before they can be trusted. A card used in a reader has no trusted display:
the transaction must be checked in the signer app before its PIN is entered.

Build with `ws build logos-keycard-ui --auto-local`. The runtime dependencies must be built
from matching source when using the wallet grouping APIs added in this change.

Licensed under MIT or Apache-2.0.

Account labels can be changed locally with `rename_account(id, name)` in the backing signer modules. Names are trimmed, limited to 80 characters, and an empty name clears the label. Keys and derivation paths are unchanged; updated labels are announced to account consumers. In Keycard UI, use **Manage → Rename** beside an account.

### Signing across connections

The signer manager shares saved public Keycard account offers between the reader and USB
Shell providers for each request. It does not copy account files: labels, wallet names and
removal continue to belong to the original saved offer. A matching, paired reader takes
priority over a USB Shell. The reader checks the seed before requesting the PIN and checks
the full master public key again after unlocking.

USB presence does not identify the card inside a Shell. On first use of each USB connection,
the user confirms the master public key. The public root is cached only in memory for that
attachment; later signatures and account exports reuse it. Removal, a changed attachment,
a link failure or module restart clears verification. On macOS, the HID path contains the
IORegistry service entry ID, detecting even a reconnect between polls; other backends also
invalidate on an observed removal or path change. Opening uses the enumerated attachment path.
The UI distinguishes an unverified connection, the verified wallet and a different wallet.
A confirmed mismatching root can advance to another connected Shell; refusal or cancellation
ends the request. Every returned signature is still checked by the signer manager against
the selected account and request before release, including if the seed changes while connected.
Active jobs remain pinned to the provider that started them, even after hotplug.

Only `signer_manager_module` may supply the optional `keycardAccount` public routing metadata
to `sign`. Legacy Shell accounts must first use “Identify wallet…” to establish their full
master key identity. No PIN or pairing data is shared between the providers.

Use **Manage → Verify wallet…** to choose a connected Shell and request a fresh master-key
confirmation even when the connection is already verified. The action clears the prior cache
first; refusal leaves it unverified, and a different root is reported as a wallet mismatch.
The module accepts `add_accounts` with `verifyOnly: true`, empty `families`, and an optional
`masterKeyId` constraint. It reuses the asynchronous `add_status` flow without importing,
renaming or regrouping any saved accounts or wallets.

### Card administration

Use **Card administration…** in the toolbar, or from a connected reader wallet's
**Manage…** dialog. Choose the physical card before the operation. This remains
available for cards with no seed or accounts. A Shell-only connection explains that
administration requires moving its card to a direct reader.

The dialog exposes card status/authenticity, initialization, PIN/PUK recovery and changes,
3.x pairing password/slot management, BIP39 generation/import/backup verification,
on-card names, public NFC text and advanced public/Cash data. Phrase generation shows
12/15/18/21/24 numbered words and requires a backup acknowledgement before loading.
Credentials must be repeated when setting them. Erase/reset and non-recoverable key
generation require explicit typed confirmations. Existing keys are never silently
replaced. The module checks the selected card and seed again before acting.

Recovery words are transient dialog state, cleared on close, card/seed change or successful
loading; they are never copied into replicated backend properties. Changing credentials
or resetting a physical card does not rename/delete the seed wallet or accounts saved
on this computer. Operations and transport/version limits are documented in the
[keycard module](https://github.com/logos-co/logos-keycard-module#physical-card-administration).

Card setup uses the standard 3.x pairing password by default. Advanced options allow a custom password with confirmation. Device selectors and wallet connection summaries show only connected readers/Shells; saved wallets and accounts remain available offline.

Account rows show both the derivation path and a copyable address. Bitcoin shows the first receiving address (`0/0`), derived from the saved public account key even when disconnected, rather than implying that the account has only one address.
