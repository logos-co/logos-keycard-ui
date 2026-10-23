#include "keycard_ui_backend.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QMap>

// The generated umbrella carrying `struct LogosModules`.
#include "logos_sdk.h"

namespace {

QJsonObject parseObject(const QString &reply)
{
    return QJsonDocument::fromJson(reply.toUtf8()).object();
}

QString compact(const QJsonValue &v)
{
    if (v.isArray())
        return QString::fromUtf8(QJsonDocument(v.toArray()).toJson(QJsonDocument::Compact));
    if (v.isObject())
        return QString::fromUtf8(QJsonDocument(v.toObject()).toJson(QJsonDocument::Compact));
    return {};
}

QString text(const QJsonObject &o)
{
    return QString::fromUtf8(QJsonDocument(o).toJson(QJsonDocument::Compact));
}

QJsonArray array(const QString &json) { return QJsonDocument::fromJson(json.toUtf8()).array(); }
bool containsGroup(const QString &json, const QString &id) {
    for (const auto &v : array(json)) if (v.toObject().value("id").toString() == id) return true;
    return false;
}
QJsonObject findGroup(const QString &json, const QString &id) {
    for (const auto &v : array(json)) if (v.toObject().value("id").toString() == id) return v.toObject();
    return {};
}

// The root identifies a wallet; providers and physical connections only select its transport.
QJsonArray mergeWallets(const QJsonArray &reader, const QJsonArray &shell) {
    QMap<QString, QJsonObject> groups;
    const auto ingest = [&](const QJsonArray &input, const QString &provider) {
        for (const auto &value : input) {
            auto source = value.toObject(); const auto id = source.value("id").toString();
            auto g = groups.value(id, source);
            auto names = g.value("aliases").toArray();
            auto addName = [&](const QJsonValue &name) { if (!name.toString().isEmpty() && !names.contains(name)) names.append(name); };
            addName(g.value("name")); addName(source.value("name"));
            for (const auto &name : source.value("aliases").toArray()) addName(name);
            if (g.value("name").toString().isEmpty()) g["name"] = source.value("name");
            g["aliases"] = names;
            auto connections = groups.contains(id) ? g.value("connections").toArray() : QJsonArray{};
            for (auto c : source.value("connections").toArray()) {
                auto connection = c.toObject(); connection["provider"] = provider;
                connections.append(connection);
            }
            g["connections"] = connections;
            g["connected"] = g.value("connected").toBool() || source.value("connected").toBool();
            // Its accounts are sealed until the person unlocks the wallet in the Signer app.
            g["locked"] = g.value("locked").toBool() || source.value("locked").toBool();
            auto accounts = groups.contains(id) ? g.value("accounts").toArray() : QJsonArray{};
            for (const auto &v : source.value("accounts").toArray()) {
                auto a = v.toObject();
                const auto identity = !a.value("address").toString().isEmpty() ? a.value("address").toString().toLower()
                    : a.value("family").toString() + ":" + a.value("chain").toString() + ":" + a.value("xpub").toString();
                int index = -1;
                for (int i = 0; i < accounts.size(); ++i) if (accounts[i].toObject().value("identity").toString() == identity) { index = i; break; }
                auto row = index < 0 ? a : accounts[index].toObject();
                auto origins = row.value("sources").toArray();
                origins.append(QJsonObject{{"provider", provider}, {"id", a.value("id")}});
                row["sources"] = origins; row["identity"] = identity;
                row["available"] = row.value("available").toBool() || a.value("available").toBool();
                auto labels = row.value("aliases").toArray();
                for (auto label : {row.value("label"), a.value("label")}) if (!label.toString().isEmpty() && !labels.contains(label)) labels.append(label);
                row["aliases"] = labels;
                if (index < 0) accounts.append(row); else accounts[index] = row;
            }
            g["accounts"] = accounts; groups[id] = g;
        }
    };
    ingest(reader, "reader"); ingest(shell, "shell");
    QJsonArray result; for (const auto &g : groups) result.append(g); return result;
}

// Overwrite a secret's copy once it has been sent; Qt keeps no promise beyond that.
void wipe(QString &s)
{
    s.fill(QChar(u'\0'));
    s.clear();
}

} // namespace

bool KeycardUiBackend::ok(const QJsonObject &reply, const QString &context)
{
    if (reply.value(QStringLiteral("ok")).toBool())
        return true;
    QString e = reply.value(QStringLiteral("error")).toString();
    if (e.isEmpty())
        e = QStringLiteral("the Keycard module didn't answer");
    setLastError(QStringLiteral("%1: %2").arg(context, e));
    return false;
}

void KeycardUiBackend::onContextReady()
{
    // A card inserted or removed, or the accounts changed: read them again, off the IPC stack.
    modules().keycard_module.onSigner_accounts_changed([this](auto) {
        QTimer::singleShot(0, this, [this] { refresh(); });
    });
    modules().keycard_module.onSigner_changed([this](auto) {
        QTimer::singleShot(0, this, [this] { refresh(); });
    });
    modules().keycard_shell_module.onSigner_accounts_changed([this](auto) {
        QTimer::singleShot(0, this, [this] { refresh(); });
    });
    modules().keycard_shell_module.onSigner_changed([this](auto) {
        QTimer::singleShot(0, this, [this] { refresh(); });
    });
    m_poll.setInterval(500);
    QObject::connect(&m_poll, &QTimer::timeout, this, [this] { poll(); });
    refresh();
}

bool KeycardUiBackend::refresh()
{
    const QJsonObject cards = parseObject(modules().keycard_module.cards());
    const QJsonArray present = cards.value(QStringLiteral("cards")).toArray();
    setCardsJson(ok(cards, QStringLiteral("cards")) ? compact(present) : QStringLiteral("[]"));
    const QJsonObject accounts = parseObject(modules().keycard_module.signer_accounts());
    setAccountsJson(ok(accounts, QStringLiteral("accounts"))
                        ? compact(accounts.value(QStringLiteral("accounts")))
                        : QStringLiteral("[]"));
    const QJsonObject groups = parseObject(modules().keycard_module.card_groups());
    setCardGroupsJson(ok(groups, QStringLiteral("card groups"))
                         ? compact(groups.value(QStringLiteral("groups"))) : QStringLiteral("[]"));
    const auto devices = parseObject(modules().keycard_shell_module.devices());
    setShellDevicesJson(ok(devices, QStringLiteral("USB devices")) ? compact(devices.value("devices")) : QStringLiteral("[]"));
    const auto shellGroups = parseObject(modules().keycard_shell_module.wallet_groups());
    setShellGroupsJson(ok(shellGroups, QStringLiteral("USB wallets")) ? compact(shellGroups.value("groups")) : QStringLiteral("[]"));
    auto wallets = mergeWallets(array(cardGroupsJson()), array(shellGroupsJson()));
    // Session verification is temporary: never turn USB presence into a saved seed association.
    for (int i = 0; i < wallets.size(); ++i) {
        auto wallet = wallets[i].toObject();
        if (!wallet.value("id").toString().startsWith("seed:")) continue;
        auto connections = wallet.value("connections").toArray();
        for (auto v : array(shellDevicesJson())) {
            auto serial = v.toObject().value("serial").toString();
            const auto verified = v.toObject().value("verifiedMasterKeyId").toString();
            int known = -1;
            for (int j = 0; j < connections.size(); ++j)
                if (connections[j].toObject().value("serial").toString() == serial) known = j;
            auto connection = known < 0 ? QJsonObject{{"transport", "shell"}, {"provider", "shell"}, {"serial", serial}}
                                        : connections[known].toObject();
            connection["connected"] = true;
            connection["verification"] = verified.isEmpty() ? "pending"
                : wallet.value("id").toString() == "seed:" + verified ? "verified" : "different";
            if (known < 0) connections.append(connection); else connections[known] = connection;
            wallet["connected"] = true;
        }
        wallet["connections"] = connections; wallets[i] = wallet;
    }
    // Derive display-only receiving addresses from saved public keys for both transports.
    // Keep Bitcoin's signer account identity/xpub intact; a preview is not a new account.
    QJsonArray publicAccounts;
    for (const auto &w : wallets)
        for (const auto &a : w.toObject().value("accounts").toArray()) publicAccounts.append(a);
    const auto previewReply = parseObject(modules().keycard_module.account_previews(compact(publicAccounts)));
    const auto previews = previewReply.value("previews").toArray();
    int previewIndex = 0;
    for (int i = 0; i < wallets.size(); ++i) {
        auto wallet = wallets[i].toObject();
        auto rows = wallet.value("accounts").toArray();
        for (int j = 0; j < rows.size(); ++j) {
            auto row = rows[j].toObject();
            row["preview"] = previewIndex < previews.size() ? previews[previewIndex].toObject()
                : QJsonObject{{"error", "Address preview unavailable"}};
            ++previewIndex; rows[j] = row;
        }
        wallet["accounts"] = rows; wallets[i] = wallet;
    }
    setWalletsJson(compact(wallets));
    setStatusText(present.isEmpty() ? QStringLiteral("No Keycard in a reader")
                                    : QStringLiteral("Ready"));
    return cards.value("ok").toBool();
}

bool KeycardUiBackend::offer(QString reader, QString familiesJson, QString chain, int account,
                             QString label, QString pin)
{
    const bool result = offerChecked(reader, familiesJson, chain, account, label, pin, QString());
    wipe(pin);
    return result;
}

bool KeycardUiBackend::offerChecked(QString reader, QString familiesJson, QString chain, int account,
                                    QString label, QString pin, QString expectedCard)
{
    setLastError(QString());
    if (!m_job.isEmpty()) { wipe(pin); setLastError("An account is already being added."); return false; }
    m_shellJob = false;
    QJsonObject p;
    p.insert(QStringLiteral("families"), QJsonDocument::fromJson(familiesJson.toUtf8()).array());
    p.insert(QStringLiteral("chain"), chain);
    p.insert(QStringLiteral("account"), account);
    if (!label.trimmed().isEmpty())
        p.insert(QStringLiteral("label"), label.trimmed());
    if (!reader.isEmpty())
        p.insert(QStringLiteral("reader"), reader);
    if (!expectedCard.isEmpty()) p.insert(QStringLiteral("cardId"), expectedCard);
    p.insert(QStringLiteral("pin"), pin);
    QString params = text(p);
    wipe(pin);
    p = QJsonObject();
    const QJsonObject reply = parseObject(modules().keycard_module.add_accounts(params));
    wipe(params);
    if (!ok(reply, QStringLiteral("offer")))
        return false;
    m_job = reply.value(QStringLiteral("job")).toString();
    setExportJson(QStringLiteral("{\"state\":\"working\"}"));
    m_poll.start();
    return true;
}

void KeycardUiBackend::poll()
{
    if (m_job.isEmpty()) {
        m_poll.stop();
        return;
    }
    QJsonObject reply = parseObject(m_shellJob ? modules().keycard_shell_module.add_status(m_job)
                                              : modules().keycard_module.add_status(m_job));
    if (!ok(reply, QStringLiteral("offer"))) {
        m_poll.stop();
        m_job.clear();
        setExportJson(text(QJsonObject{{"state", "failed"}, {"error", lastError()}}));
        return;
    }
    const QString state = reply.value(QStringLiteral("state")).toString();
    reply.remove(QStringLiteral("ok"));
    reply.remove(QStringLiteral("job"));
    // A preview's accounts are shown by address, Bitcoin's by its first receiving one.
    if (m_preview && state == QLatin1String("done")) {
        QJsonArray accounts = reply.value(QStringLiteral("accounts")).toArray();
        const auto previews = parseObject(modules().keycard_module.account_previews(compact(accounts)))
                                  .value(QStringLiteral("previews")).toArray();
        for (int i = 0; i < accounts.size(); ++i) {
            auto a = accounts[i].toObject();
            a["preview"] = i < previews.size() ? previews[i].toObject()
                                               : QJsonObject{{"error", "Address preview unavailable"}};
            accounts[i] = a;
        }
        reply["accounts"] = accounts;
    }
    setExportJson(compact(reply));
    if (state == QLatin1String("done") || state == QLatin1String("failed")) {
        m_poll.stop();
        m_job.clear();
        // Not after a shown preview: re-reading the cards would clear the PIN the next page needs.
        if (!m_preview || state == QLatin1String("failed")) refresh();
    }
}

bool KeycardUiBackend::removeAccount(QString id)
{
    setLastError(QString());
    const bool removed = ok(parseObject(modules().keycard_module.remove_account(id)),
                            QStringLiteral("remove"));
    refresh();
    return removed;
}

bool KeycardUiBackend::pair(QString reader, QString pairingPassword)
{
    setLastError(QString());
    QJsonObject p;
    if (!reader.isEmpty())
        p.insert(QStringLiteral("reader"), reader);
    p.insert(QStringLiteral("pairingPassword"), pairingPassword);
    QString params = text(p);
    wipe(pairingPassword);
    p = QJsonObject();
    const bool paired = ok(parseObject(modules().keycard_module.pair(params)), QStringLiteral("pair"));
    wipe(params);
    if (paired)
        setNoticeText(QStringLiteral("Paired: the module keeps this card's pairing."));
    refresh();
    return paired;
}

bool KeycardUiBackend::changePin(QString reader, QString pin, QString newPin)
{
    setLastError(QString());
    QJsonObject p;
    if (!reader.isEmpty())
        p.insert(QStringLiteral("reader"), reader);
    p.insert(QStringLiteral("pin"), pin);
    p.insert(QStringLiteral("newPin"), newPin);
    QString params = text(p);
    wipe(pin);
    wipe(newPin);
    p = QJsonObject();
    const bool changed =
        ok(parseObject(modules().keycard_module.change_pin(params)), QStringLiteral("change PIN"));
    wipe(params);
    if (changed)
        setNoticeText(QStringLiteral("PIN changed."));
    refresh();
    return changed;
}

bool KeycardUiBackend::unblockPin(QString reader, QString puk, QString newPin)
{
    setLastError(QString());
    QJsonObject p;
    if (!reader.isEmpty())
        p.insert(QStringLiteral("reader"), reader);
    p.insert(QStringLiteral("puk"), puk);
    p.insert(QStringLiteral("newPin"), newPin);
    QString params = text(p);
    wipe(puk);
    wipe(newPin);
    p = QJsonObject();
    const bool unblocked =
        ok(parseObject(modules().keycard_module.unblock_pin(params)), QStringLiteral("unblock PIN"));
    wipe(params);
    if (unblocked)
        setNoticeText(QStringLiteral("PIN unblocked, and set to the new one."));
    refresh();
    return unblocked;
}

bool KeycardUiBackend::trustCard(QString reader, QString identity)
{
    setLastError(QString());
    QJsonObject p;
    if (!reader.isEmpty())
        p.insert(QStringLiteral("reader"), reader);
    p.insert(QStringLiteral("identity"), identity);
    const bool trusted =
        ok(parseObject(modules().keycard_module.trust_card(text(p))), QStringLiteral("trust"));
    if (trusted)
        setNoticeText(QStringLiteral("Trusted: this card is used though Keycard didn't sign it."));
    refresh();
    return trusted;
}

bool KeycardUiBackend::forgetCard(QString identity)
{
    setLastError(QString());
    const bool forgot =
        ok(parseObject(modules().keycard_module.forget_card(identity)), QStringLiteral("forget"));
    if (forgot)
        setNoticeText(QStringLiteral("No longer trusted: this card is refused again."));
    refresh();
    return forgot;
}

bool KeycardUiBackend::renameCard(QString id, QString name)
{
    setLastError(QString()); bool result = true;
    if (containsGroup(cardGroupsJson(), id)) result &= ok(parseObject(modules().keycard_module.rename_card(id, name)), "Rename wallet");
    if (containsGroup(shellGroupsJson(), id)) result &= ok(parseObject(modules().keycard_shell_module.rename_wallet(id, name)), "Rename wallet");
    refresh(); return result;
}

bool KeycardUiBackend::forgetSavedCard(QString id)
{
    setLastError(QString()); refresh();
    if (findGroup(cardGroupsJson(), id).value("connected").toBool()) {
        setLastError("Remove this wallet's Keycards from their readers before forgetting it."); return false;
    }
    bool result = true;
    if (containsGroup(cardGroupsJson(), id)) result &= ok(parseObject(modules().keycard_module.forget_saved_card(id)), "Forget wallet");
    if (result && containsGroup(shellGroupsJson(), id)) result &= ok(parseObject(modules().keycard_shell_module.forget_wallet(id)), "Forget wallet");
    refresh(); return result;
}

bool KeycardUiBackend::identifyWallet(QString serial)
{
    setLastError(QString());
    if (!m_job.isEmpty()) { setLastError("A wallet operation is already in progress."); return false; }
    const auto reply = parseObject(modules().keycard_shell_module.add_accounts(text(QJsonObject{
        {"families", QJsonArray{}}, {"serial", serial}, {"identify", true}})));
    if (!ok(reply, "Identify wallet")) return false;
    m_shellJob = true; m_job = reply.value("job").toString();
    setExportJson(QStringLiteral("{\"state\":\"confirm_on_device\"}")); m_poll.start(); return true;
}

bool KeycardUiBackend::verifyWallet(QString walletId, QString serial)
{
    setLastError(QString());
    if (!m_job.isEmpty()) { setLastError("A wallet operation is already in progress."); return false; }
    if (!walletId.startsWith("seed:") || serial.isEmpty()) { setLastError("Choose an identified wallet and a connected Shell."); return false; }
    const auto reply = parseObject(modules().keycard_shell_module.add_accounts(text(QJsonObject{
        {"families", QJsonArray{}}, {"serial", serial}, {"verifyOnly", true}, {"masterKeyId", walletId.mid(5)}})));
    if (!ok(reply, "Verify wallet")) return false;
    m_shellJob = true; m_job = reply.value("job").toString();
    setExportJson(QStringLiteral("{\"state\":\"confirm_on_device\"}")); m_poll.start(); return true;
}

// The UI supplies an explicit wallet, never whichever device happens to be first.
bool KeycardUiBackend::addAccounts(QString walletId, QString connectionId, QString requestJson, QString pin)
{
    setLastError(QString());
    if (!m_job.isEmpty()) { wipe(pin); setLastError("An account is already being added."); return false; }
    QJsonObject params = parseObject(requestJson);
    const bool preview = params.value("preview").toBool();
    const bool kept = params.value("fromPreview").toBool();
    QJsonObject reply;
    if (!connectionId.startsWith("shell:")) {
        refresh();
        QString reader;
        for (const auto &value : QJsonDocument::fromJson(cardsJson().toUtf8()).array()) {
            const auto c = value.toObject();
            const auto id = c.value("secureChannel").toInt() == 2
                ? "identity:" + c.value("identity").toString() : "instance:" + c.value("instanceUid").toString();
            if (id != connectionId) continue;
            if (walletId.startsWith("seed:") && "seed:" + c.value("keyUid").toString() != walletId) {
                wipe(pin); setLastError("The reader contains a different wallet."); return false;
            }
            reader = c.value("reader").toString();
        }
        if (reader.isEmpty()) { wipe(pin); setLastError("Insert the selected Keycard to add accounts."); return false; }
        params.insert("reader", reader);
        params.insert("cardId", connectionId);
        // Kept from a preview, an account needs no PIN: the card isn't asked again.
        if (!kept) params.insert("pin", pin);
        wipe(pin);
        QString text_ = text(params);
        params = QJsonObject();
        reply = parseObject(modules().keycard_module.add_accounts(text_));
        wipe(text_);
        m_shellJob = false;
    } else {
        wipe(pin); // USB Shell collects authorization on the device, never on this computer.
        const auto parts = connectionId.split(':');
        if (parts.size() != 3 || parts[1].isEmpty()) { setLastError("Invalid USB wallet."); return false; }
        params.insert("serial", parts[1]);
        if (walletId.startsWith("seed:")) params.insert("masterKeyId", walletId.mid(5));
        else {
            const auto legacy = walletId.split(':');
            if (legacy.size() == 3 && !legacy[2].isEmpty() && legacy[2] != "unknown") params.insert("fingerprint", legacy[2]);
        }
        reply = parseObject(modules().keycard_shell_module.add_accounts(text(params)));
        m_shellJob = true;
    }
    if (!ok(reply, "Add accounts")) return false;
    m_preview = preview;
    m_job = reply.value("job").toString();
    setExportJson(m_shellJob && !kept ? QStringLiteral("{\"state\":\"confirm_on_device\"}")
                                      : QStringLiteral("{\"state\":\"working\"}"));
    m_poll.start();
    return true;
}

bool KeycardUiBackend::removeWalletAccount(QString walletId, QString accountId)
{
    setLastError(QString()); bool result = true;
    const auto group = findGroup(walletsJson(), walletId);
    for (auto v : group.value("accounts").toArray()) {
        const auto a = v.toObject(); if (a.value("id").toString() != accountId) continue;
        for (auto origin : a.value("sources").toArray()) {
            const auto o = origin.toObject(); const auto id = o.value("id").toString();
            result &= ok(parseObject(o.value("provider").toString() == "shell"
                ? modules().keycard_shell_module.remove_account(id) : modules().keycard_module.remove_account(id)), "Remove account");
        }
    }
    refresh(); return result;
}

bool KeycardUiBackend::renameAccount(QString walletId, QString accountId, QString name)
{
    setLastError(QString()); bool result = true;
    const auto group = findGroup(walletsJson(), walletId);
    for (auto v : group.value("accounts").toArray()) {
        const auto a = v.toObject(); if (a.value("id").toString() != accountId) continue;
        for (auto origin : a.value("sources").toArray()) {
            const auto o = origin.toObject(); const auto id = o.value("id").toString();
            result &= ok(parseObject(o.value("provider").toString() == "shell"
                ? modules().keycard_shell_module.rename_account(id, name) : modules().keycard_module.rename_account(id, name)), "Rename account");
        }
    }
    refresh(); return result;
}

QString KeycardUiBackend::administer(QString paramsJson)
{
    if (!m_job.isEmpty()) {
        wipe(paramsJson);
        return QStringLiteral("{\"ok\":false,\"error\":\"A wallet operation is already in progress.\"}");
    }
    QString reply = modules().keycard_module.administer(paramsJson);
    wipe(paramsJson);
    refresh();
    // A generated recovery phrase is returned only to the requesting dialog, never a property.
    return reply;
}
