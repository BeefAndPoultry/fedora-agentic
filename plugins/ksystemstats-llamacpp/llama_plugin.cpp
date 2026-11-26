#include "llama_plugin.h"

#include <KLocalizedString>
#include <KPluginFactory>

#include <QCoreApplication>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLibraryInfo>
#include <QMutex>
#include <QMutexLocker>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QObject>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QString>
#include <QStringList>
#include <QTextStream>
#include <QUrlQuery>

namespace KSysGuard
{
    using SensorObjectImpl = SensorObject;
}

LlamaPlugin::LlamaPlugin(QObject *parent, const QVariantList &args)
    : KSysGuard::SensorPlugin(parent, args)
{
    // Resolve the server address/key once so the plugin factory can build itself
    // without a live server running (e.g. on a bare builder in CI).
    loadServerConfig();

    m_container = new KSysGuard::SensorContainer(QStringLiteral("llamacpp"),
        i18n("llama.cpp Server"), this);

    m_routerObj = new KSysGuard::SensorObject(QStringLiteral("router"),
        i18n("Inference Router"), m_container);

    // Model name as text: 0 == Invalid, so System Monitor shows "Idle" /
    // "Offline" / the loaded model id instead of a bogus number.
    m_activeModel = new KSysGuard::SensorProperty(QStringLiteral("active_model"),
        i18n("Loaded Model"), m_routerObj);
    m_activeModel->setShortName(i18n("Model"));
    m_activeModel->setVariantType(QVariant::String);

    // Numeric sensors carried as double; units stay consistent for readers.
    m_busySlots = new KSysGuard::SensorProperty(QStringLiteral("busy_slots"),
        i18n("Active Slots"), m_routerObj);
    m_busySlots->setShortName(i18n("Busy Slots"));
    m_busySlots->setVariantType(QVariant::Double);

    m_totalSlots = new KSysGuard::SensorProperty(QStringLiteral("total_slots"),
        i18n("Total Slots"), m_routerObj);
    m_totalSlots->setShortName(i18n("Slots"));
    m_totalSlots->setVariantType(QVariant::Double);

    m_kvCachePercent = new KSysGuard::SensorProperty(QStringLiteral("kv_cache_usage"),
        i18n("KV Cache Usage"), m_routerObj);
    m_kvCachePercent->setShortName(i18n("KV Cache"));
    m_kvCachePercent->setVariantType(QVariant::Double);
    m_kvCachePercent->setMin(0.0);
    m_kvCachePercent->setMax(100.0);

    m_promptTps = new KSysGuard::SensorProperty(QStringLiteral("prompt_tps"),
        i18n("Prompt Processing Speed"), m_routerObj);
    m_promptTps->setShortName(i18n("Prompt t/s"));
    m_promptTps->setVariantType(QVariant::Double);

    m_genTps = new KSysGuard::SensorProperty(QStringLiteral("gen_tps"),
        i18n("Token Generation Speed"), m_routerObj);
    m_genTps->setShortName(i18n("Gen t/s"));
    m_genTps->setVariantType(QVariant::Double);

    m_tokensGeneratedTotal = new KSysGuard::SensorProperty(QStringLiteral("tokens_generated_total"),
        i18n("Total Tokens Generated"), m_routerObj);
    m_tokensGeneratedTotal->setShortName(i18n("Tokens"));
    m_tokensGeneratedTotal->setVariantType(QVariant::Double);
}

QString LlamaPlugin::providerName() const
{
    return QStringLiteral("llamacpp");
}

// Resolve host/port from the repo's sysconfig keys and the API key from the
// file generated at first boot. Environment overrides always win so a test or
// per-host deployment can redirect without rebuilding this plugin.
void LlamaPlugin::loadServerConfig()
{
    const QString defaultHost = QStringLiteral("127.0.0.1");
    const QString defaultPort = QStringLiteral("9931"); // matches root/etc/sysconfig/llama-server

    QString host = defaultHost;
    QString port = defaultPort;

    QFile sysconfig(QStringLiteral("/etc/sysconfig/llama-server"));
    if (sysconfig.open(QIODevice::ReadOnly)) {
        QTextStream in(&sysconfig);
        while (!in.atEnd()) {
            const QString line = in.readLine();
            const int eq = line.indexOf(QLatin1Char('='));
            if (eq < 0) continue;

            const QString key = line.left(eq).trimmed();
            QString val = line.mid(eq + 1).trimmed();
            if ((val.size() >= 2) && val.startsWith('"') && val.endsWith('"')) {
                val = val.mid(1, val.length() - 2);
            }
            if (key == QLatin1String("LLAMA_HOST") && val != QLatin1String("0.0.0.0")) {
                host = val;
            } else if (key == QLatin1String("LLAMA_PORT")) {
                port = val;
            }
        }
    }

    if (const QString envUrl = qEnvironmentVariable("LLAMA_SERVER_URL"); !envUrl.isEmpty()) {
        m_baseUrl = QUrl(envUrl);
    } else if (const QString envHost = qEnvironmentVariable("LLAMA_HOST"); !envHost.isEmpty()) {
        const QString envPort = qEnvironmentVariable("LLAMA_PORT");
        m_baseUrl = QUrl(QStringLiteral("http://%1:%2")
            .arg(envHost)
            .arg(envPort.isEmpty() ? defaultPort : envPort));
    } else {
        m_baseUrl = QUrl(QStringLiteral("http://%1:%2").arg(host, port));
    }

    if (const QString envKey = qEnvironmentVariable("LLAMA_API_KEY"); !envKey.isEmpty()) {
        m_apiKey = envKey;
    } else {
        QFile keyFile(QStringLiteral("/etc/llama-cpp/apikey"));
        if (keyFile.open(QIODevice::ReadOnly)) {
            m_apiKey = QString::fromUtf8(keyFile.readAll()).trimmed();
        }
    }
}

QNetworkRequest LlamaPlugin::makeRequest(const QString &path, const QString &modelId) const
{
    QUrl url = m_baseUrl;
    url.setPath(path);
    if (!modelId.isEmpty()) {
        QUrlQuery query;
        query.addQueryItem(QStringLiteral("model"), modelId);
        url.setQuery(query);
    }

    QNetworkRequest req(url);
    req.setTransferTimeout(800); // ms: fail fast if llama-server is restarting
    if (!m_apiKey.isEmpty()) {
        req.setRawHeader("Authorization", QByteArray("Bearer ") + m_apiKey.toUtf8());
    }
    return req;
}

void LlamaPlugin::resetIdleValues()
{
    m_activeModel->setValue(QStringLiteral("Idle"));
    m_busySlots->setValue(0);
    m_totalSlots->setValue(0);
    m_kvCachePercent->setValue(0.0);
    m_promptTps->setValue(0.0);
    m_genTps->setValue(0.0);
    m_tokensGeneratedTotal->setValue(0.0);
}

void LlamaPlugin::update()
{
    // Zero-idle rule: return immediately unless System Monitor or a panel widget
    // subscribes at least one property, so the plugin never talks to
    // llama-server while no sensor is shown.
    if (!m_activeModel->isSubscribed()
        && !m_busySlots->isSubscribed()
        && !m_totalSlots->isSubscribed()
        && !m_kvCachePercent->isSubscribed()
        && !m_promptTps->isSubscribed()
        && !m_genTps->isSubscribed()
        && !m_tokensGeneratedTotal->isSubscribed()) {
        return;
    }

    QMutexLocker locker(&m_mutex);
    if (m_pollInFlight) {
        return;
    }
    m_pollInFlight = true;

    QNetworkAccessManager nam;
    QNetworkReply *reply = nam.get(makeRequest(QStringLiteral("/models")));

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();

        QMutexLocker locker(&m_mutex);
        if (!m_pollInFlight) {  // stale: a newer update() superseded this poll
            return;
        }
        m_pollInFlight = false;

        if (reply->error() != QNetworkReply::NoError) {
            m_activeModel->setValue(QStringLiteral("Offline"));
            m_busySlots->setValue(0);
            m_totalSlots->setValue(0);
            m_kvCachePercent->setValue(0.0);
            m_promptTps->setValue(0.0);
            m_genTps->setValue(0.0);
            m_tokensGeneratedTotal->setValue(0.0);
            return;
        }

        // Router mode: find only the model that is currently loaded, then query
        // /slots and /metrics exclusively for it, so we never trigger
        // --models-autoload on another GGUF sitting in models.preset.
        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        const QJsonObject root = doc.object();
        QJsonArray models = root.value(QLatin1String("data")).toArray();
        if (models.isEmpty()) {
            models = root.value(QLatin1String("models")).toArray();
        }

        QString loadedModelId;
        for (const QJsonValue &entryVal : models) {
            const QJsonObject entry = entryVal.toObject();
            const QJsonObject status = entry.value(QLatin1String("status")).toObject();
            if (status.value(QLatin1String("value")).toString() == QLatin1String("loaded")) {
                loadedModelId = entry.value(QLatin1String("id")).toString();
                break;
            }
        }

        if (loadedModelId.isEmpty()) {
            resetIdleValues();
            return;
        }

        m_activeModel->setValue(loadedModelId);
        fetchSlots(loadedModelId);
    });
}

void LlamaPlugin::fetchSlots(const QString &modelId)
{
    if (!(m_busySlots->isSubscribed() || m_totalSlots->isSubscribed() || m_kvCachePercent->isSubscribed())) {
        fetchMetrics(modelId);
        return;
    }

    QNetworkAccessManager nam;
    QNetworkReply *reply = nam.get(makeRequest(QStringLiteral("/slots"), modelId));
    connect(reply, &QNetworkReply::finished, this, [this, reply, modelId]() {
        reply->deleteLater();

        int total = 0;
        int busy = 0;
        qint64 totalCtx = 0;
        qint64 totalPast = 0;

        if (reply->error() == QNetworkReply::NoError) {
            const QJsonArray slotsArr = QJsonDocument::fromJson(reply->readAll()).array();
            for (const QJsonValue &slotVal : slotsArr) {
                const QJsonObject slot = slotVal.toObject();
                total++;
                if (slot.value(QLatin1String("is_processing")).toBool()) {
                    busy++;
                }
                const qint64 nCtx = slot.value(QLatin1String("n_ctx")).toInteger();
                const qint64 nPast = slot.value(QLatin1String("n_past")).toInteger();
                if (nCtx > 0) {
                    totalCtx += nCtx;
                    totalPast += qBound<qint64>(0, nPast, nCtx);
                }
            }
        }

        QMutexLocker locker(&m_mutex);
        m_totalSlots->setValue(static_cast<double>(total));
        m_busySlots->setValue(static_cast<double>(busy));
        m_kvCachePercent->setValue(totalCtx > 0
            ? (static_cast<double>(totalPast) * 100.0 / static_cast<double>(totalCtx))
            : 0.0);

        fetchMetrics(modelId);
    });
}

void LlamaPlugin::fetchMetrics(const QString &modelId)
{
    if (!(m_promptTps->isSubscribed() || m_genTps->isSubscribed() || m_tokensGeneratedTotal->isSubscribed())) {
        return;
    }

    QNetworkAccessManager nam;
    QNetworkReply *reply = nam.get(makeRequest(QStringLiteral("/metrics"), modelId));
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();

        QMutexLocker locker(&m_mutex);
        if (reply->error() != QNetworkReply::NoError) {
            return;
        }

        // Prometheus text format:  llamacpp:metric_name{labels} value
        static const QRegularExpression metricRe(
            QStringLiteral(R"(^llamacpp:([a-zA-Z0-9_:]+)(?:\{[^}]*\})?\s+(prom_value))"));

        const QString body = QString::fromUtf8(reply->readAll());
        const QStringList lines = body.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
        for (const QString &line : lines) {
            if (line.startsWith(QLatin1Char('#'))) {
                continue;
            }
            const QRegularExpressionMatch m = metricRe.match(line);
            if (!m.hasMatch()) {
                continue;
            }

            const QString name = m.captured(1);
            const double value = m.captured(2).toDouble();
            if (name == QLatin1String("prompt_tokens_seconds")) {
                if (m_promptTps->isSubscribed()) {
                    m_promptTps->setValue(value);
                }
            } else if (name == QLatin1String("predicted_tokens_seconds")) {
                if (m_genTps->isSubscribed()) {
                    m_genTps->setValue(value);
                }
            } else if (name == QLatin1String("tokens_predicted_total")) {
                if (m_tokensGeneratedTotal->isSubscribed()) {
                    m_tokensGeneratedTotal->setValue(value);
                }
            }
        }
    });
}

K_PLUGIN_CLASS_WITH_JSON(LlamaPlugin, "metadata.json")

#include "llama_plugin.moc"
