#pragma once

#include <QObject>
#include <QHash>
#include <QVariantList>
#include <QVector>

class QTimer;

class SystemDetailsBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(QString hostname READ hostname NOTIFY dataChanged)
    Q_PROPERTY(QString uptime READ uptime NOTIFY dataChanged)
    Q_PROPERTY(QString primaryIp READ primaryIp NOTIFY dataChanged)
    Q_PROPERTY(QVariantList ipAddresses READ ipAddresses NOTIFY dataChanged)
    Q_PROPERTY(QVariantList cpuFrequencies READ cpuFrequencies NOTIFY dataChanged)
    Q_PROPERTY(QVariantList topProcesses READ topProcesses NOTIFY dataChanged)
    Q_PROPERTY(QVariantList thermalSensors READ thermalSensors NOTIFY dataChanged)
    Q_PROPERTY(QVariantList networkSpeeds READ networkSpeeds NOTIFY dataChanged)
    Q_PROPERTY(int topProcessLimit READ topProcessLimit CONSTANT)

public:
    explicit SystemDetailsBackend(QObject *parent = nullptr);

    bool active() const;
    void setActive(bool active);

    QString hostname() const;
    QString uptime() const;
    QString primaryIp() const;
    QVariantList ipAddresses() const;
    QVariantList cpuFrequencies() const;
    QVariantList topProcesses() const;
    QVariantList thermalSensors() const;
    QVariantList networkSpeeds() const;
    int topProcessLimit() const;

    Q_INVOKABLE void refreshNow();

signals:
    void activeChanged();
    void dataChanged();

private slots:
    void refresh();

private:
    struct ProcessSample {
        int pid = 0;
        QString name;
        quint64 totalCpuTime = 0;
        qint64 rssBytes = 0;
    };

    void resetSamplingState();
    void readOverview();
    void readCpuFrequencies();
    void readTopProcesses();
    void readThermalSensors();
    void readNetworkSpeeds();

    qint64 readTotalMemoryKb() const;
    quint64 readTotalCpuTime() const;
    bool readProcessSample(const QString &pidText, ProcessSample &sample) const;

    QTimer *m_timer = nullptr;
    bool m_active = false;
    QString m_hostname;
    QString m_uptime;
    QString m_primaryIp;
    QVariantList m_ipAddresses;
    QVariantList m_cpuFrequencies;
    QVariantList m_topProcesses;
    QVariantList m_thermalSensors;
    QVariantList m_networkSpeeds;
    struct NetCounter { quint64 rx = 0; quint64 tx = 0; };
    QHash<QString, NetCounter> m_prevNetCounters;
    QHash<int, quint64> m_prevProcessCpuTimes;
    quint64 m_prevTotalCpuTime = 0;
    qint64 m_totalMemoryKb = 0;
    qint64 m_pageSizeBytes = 4096;
};
