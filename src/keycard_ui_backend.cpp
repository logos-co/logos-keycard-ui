#include "keycard_ui_backend.h"

#include <QJsonArray>
#include <QJsonDocument>

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
    m_poll.setInterval(500);
    QObject::connect(&m_poll, &QTimer::timeout, this, [this] { poll(); });
    refresh();
}

void KeycardUiBackend::refresh()
{
    const QJsonObject cards = parseObject(modules().keycard_module.cards());
    const QJsonArray present = cards.value(QStringLiteral("cards")).toArray();
    setCardsJson(ok(cards, QStringLiteral("cards")) ? compact(present) : QStringLiteral("[]"));
    const QJsonObject accounts = parseObject(modules().keycard_module.signer_accounts());
    setAccountsJson(ok(accounts, QStringLiteral("accounts"))
                        ? compact(accounts.value(QStringLiteral("accounts")))
                        : QStringLiteral("[]"));
    setStatusText(present.isEmpty() ? QStringLiteral("No Keycard in a reader")
                                    : QStringLiteral("Ready"));
}

bool KeycardUiBackend::offer(QString reader, QString familiesJson, QString chain, int account,
                             QString label, QString pin)
{
    setLastError(QString());
    QJsonObject p;
    p.insert(QStringLiteral("families"), QJsonDocument::fromJson(familiesJson.toUtf8()).array());
    p.insert(QStringLiteral("chain"), chain);
    p.insert(QStringLiteral("account"), account);
    if (!label.trimmed().isEmpty())
        p.insert(QStringLiteral("label"), label.trimmed());
    if (!reader.isEmpty())
        p.insert(QStringLiteral("reader"), reader);
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
    QJsonObject reply = parseObject(modules().keycard_module.add_status(m_job));
    if (!ok(reply, QStringLiteral("offer"))) {
        m_poll.stop();
        return;
    }
    const QString state = reply.value(QStringLiteral("state")).toString();
    reply.remove(QStringLiteral("ok"));
    reply.remove(QStringLiteral("job"));
    setExportJson(compact(reply));
    if (state == QLatin1String("done") || state == QLatin1String("failed")) {
        m_poll.stop();
        m_job.clear();
        refresh();
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
