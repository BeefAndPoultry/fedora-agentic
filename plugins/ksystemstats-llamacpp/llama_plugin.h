#pragma once

#include <QMutex>
#include <QNetworkAccessManager>
#include <QString>
#include <QUrl>
#include <QVariantList>

#include <systemstats/SensorContainer.h>
#include <systemstats/SensorObject.h>
#include <systemstats/SensorPlugin.h>
#include <systemstats/SensorProperty.h>

/*
 * ksystemstats plugin that reports inference state from a router-mode
 * llama-server (127.0.0.1:9931 by default).
 *
 * Router-mode correctness rule (critical):
 *   1. First GET /models to find the entry whose status.value == "loaded".
 *   2. NEVER query /slots or /metrics on any other model id, because in router
 *      mode hitting those endpoints for an unloaded model triggers
 *      --models-autoload and pulls GGUF weights into VRAM.
 *   3. If no model is loaded, expose numeric sensors as 0 and the model-name
 *      sensor as "Idle".
 *
 * Zero idle overhead: update() returns immediately unless at least one sensor
 * property is subscribed (no network I/O while System Monitor is closed).
 */
class LlamaPlugin : public KSysGuard::SensorPlugin
{
    Q_OBJECT

public:
    explicit LlamaPlugin(QObject *parent = nullptr, const QVariantList &args = {});
    ~LlamaPlugin() override;

    QString providerName() const override;
    void update() override;

private:
    // Resolve the server address/key from image config + environment.
    void loadServerConfig();

    // Chained async fetches; metrics only runs after slots resolves.
    void fetchSlots(const QString &modelId);
    void fetchMetrics(const QString &modelId);

    QMutex m_mutex;                 // guards state and the in-flight chain
    bool m_pollInFlight = false;

    QNetworkAccessManager m_nam;

    KSysGuard::SensorContainer *m_container = nullptr;
    KSysGuard::SensorObject *m_routerObj = nullptr;

    KSysGuard::SensorProperty *m_activeModel = nullptr;          // text  ("Idle" / "Offline" / model id)
    KSysGuard::SensorProperty *m_busySlots = nullptr;            // double (== 0 when Idle/Offline)
    KSysGuard::SensorProperty *m_totalSlots = nullptr;           // double
    KSysGuard::SensorProperty *m_kvCachePercent = nullptr;       // double 0..100
    KSysGuard::SensorProperty *m_promptTps = nullptr;            // double tokens/s
    KSysGuard::SensorProperty *m_genTps = nullptr;               // double tokens/s
    KSysGuard::SensorProperty *m_tokensGeneratedTotal = nullptr; // double cumulative
};
