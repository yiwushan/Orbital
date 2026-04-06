#pragma once

#include <QDateTime>
#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QVector>

class QTimer;

class RemoteServersBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList servers READ servers NOTIFY dataChanged)
    Q_PROPERTY(int intervalSec READ intervalSec WRITE setIntervalSec NOTIFY intervalSecChanged)

public:
    explicit RemoteServersBackend(QObject *parent = nullptr);

    QVariantList servers() const;
    int intervalSec() const;
    void setIntervalSec(int seconds);

    Q_INVOKABLE void refreshNow();
    void refreshInteractiveBurst();

signals:
    void dataChanged();
    void intervalSecChanged();

private:
    struct HostConfig {
        QString name;
        QString host;
        int port = 22;
    };

    struct HostState {
        HostConfig config;
        QString status = QStringLiteral("Not Configured");
        QString error;
        bool busy = false;
        bool hasPrevCpu = false;
        QDateTime lastUpdated;
        QVector<quint64> prevCpuTotals;
        QVector<quint64> prevCpuIdles;

        int coreCount = 0;
        double cpuTotal = 0.0;
        QVariantList cpuGroups;
        QVariantList cpuHistory;
        QVariantList cpuHistoryTs;
        QVariantList memHistory;
        QVariantList memHistoryTs;
        QVariantList diskHistory;
        QVariantList diskHistoryTs;
        double memPercent = 0.0;
        QString memDetail = QStringLiteral("--");
        QVariantMap memInfo;
        double diskPercent = 0.0;
        QString diskDetail = QStringLiteral("--");
        QVariantList diskPartitions;
        QString loadAvg = QStringLiteral("--");
    };

    void appendHistory(QVariantList &history, QVariantList &historyTs, double value, const QDateTime &at) const;
    void applyTimerCadence();
    QString envValueAny(const QStringList &keys) const;
    void loadConfigFromEnv();
    void startFetch(int index);
    bool parseSnapshotOutput(HostState &host, const QString &output, QString &errorMessage);
    QVariantMap stateToMap(const HostState &host) const;
    QString remoteCollectCommand() const;

    QVector<HostState> m_hosts;
    QTimer *m_timer = nullptr;
    int m_intervalSec = 60;
    QDateTime m_fastRefreshUntil;
};
