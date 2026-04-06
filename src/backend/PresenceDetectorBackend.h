#pragma once

#include <QDateTime>
#include <QObject>
#include <QString>

class QProcess;
class QTimer;

class PresenceDetectorBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString device READ device WRITE setDevice NOTIFY deviceChanged)
    Q_PROPERTY(int cooldownSec READ cooldownSec WRITE setCooldownSec NOTIFY cooldownSecChanged)

public:
    explicit PresenceDetectorBackend(QObject *parent = nullptr);
    ~PresenceDetectorBackend() override;

    bool enabled() const;
    void setEnabled(bool enabled);

    bool running() const;
    QString status() const;

    QString device() const;
    void setDevice(const QString &devicePath);

    int cooldownSec() const;
    void setCooldownSec(int seconds);

signals:
    void enabledChanged();
    void runningChanged();
    void statusChanged();
    void deviceChanged();
    void cooldownSecChanged();
    void personDetected();

private:
    QString detectorScriptPath() const;
    void startProcess();
    void stopProcess();
    void scheduleRestart(int delayMs);
    void setRunning(bool running);
    void setStatus(const QString &status);
    void parseStdoutLines();
    void handleDetectionEvent();
    bool parseBoolEnv(const QString &value, bool fallback) const;

    QProcess *m_process = nullptr;
    QTimer *m_restartTimer = nullptr;
    bool m_enabled = true;
    bool m_running = false;
    QString m_status = QStringLiteral("Initializing");
    QString m_device = QStringLiteral("/dev/video0");
    int m_cooldownSec = 20;
    int m_libcameraIndex = 1;
    double m_motionThreshold = 12.0;
    QDateTime m_lastDetectionAt;
};
