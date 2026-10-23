#pragma once

#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QTimer>

#include "rep_keycard_ui_source.h"
#include "logos_ui_plugin_context.h"

// The Keycard's app backend: every call to keycard_module is made here, over the generated typed
// client. An export runs once the PIN is checked, so it is polled.
class KeycardUiBackend : public KeycardUiSimpleSource,
                         public LogosUiPluginContext
{
public:
    bool refresh() override;
    QString administer(QString paramsJson) override;
    bool identifyWallet(QString serial) override;
    bool verifyWallet(QString walletId, QString serial) override;
    bool addAccounts(QString walletId, QString connectionId, QString requestJson, QString pin) override;
    bool renameAccount(QString walletId, QString accountId, QString name) override;
    bool removeWalletAccount(QString walletId, QString accountId) override;
    bool offer(QString reader, QString familiesJson, QString chain, int account, QString label,
               QString pin) override;
    bool removeAccount(QString id) override;
    bool renameCard(QString id, QString name) override;
    bool forgetSavedCard(QString id) override;
    bool pair(QString reader, QString pairingPassword) override;
    bool changePin(QString reader, QString pin, QString newPin) override;
    bool unblockPin(QString reader, QString puk, QString newPin) override;
    bool trustCard(QString reader, QString identity) override;
    bool forgetCard(QString identity) override;

protected:
    void onContextReady() override;

private:
    bool offerChecked(QString reader, QString families, QString chain, int account, QString label, QString pin, QString expectedCard);
    /// Surface the module's refusal and report whether the call succeeded.
    bool ok(const QJsonObject &reply, const QString &context);
    void poll();

    QString m_job;
    bool m_shellJob = false;
    bool m_preview = false;
    QTimer m_poll;
};
