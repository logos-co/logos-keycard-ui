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
    void refresh() override;
    bool offer(QString reader, QString familiesJson, QString chain, int account, QString label,
               QString pin) override;
    bool removeAccount(QString id) override;
    bool pair(QString reader, QString pairingPassword) override;
    bool changePin(QString reader, QString pin, QString newPin) override;
    bool unblockPin(QString reader, QString puk, QString newPin) override;

protected:
    void onContextReady() override;

private:
    /// Surface the module's refusal and report whether the call succeeded.
    bool ok(const QJsonObject &reply, const QString &context);
    void poll();

    QString m_job;
    QTimer m_poll;
};
