#pragma once

#include <QObject>
#include <QString>

class QSocketNotifier;
class QTimer;

class DisplayBackend : public QObject
{
    Q_OBJECT

public:
    explicit DisplayBackend(QObject *parent = nullptr);
    ~DisplayBackend() override;

    int brightness() const;
    bool isScreenOn() const;

public slots:
    void setBrightness(int percent);

signals:
    void brightnessChanged();
    void screenStateChanged();
    void volumeKeyEvent(QString key, int value);
    void screenshotRequested();

private slots:
    void onPowerInputEvent();
    void onVolumeInputEvent();

private:
    void initPowerKeyMonitor();
    void initVolumeKeyMonitor();
    void toggleScreen();
    void findBacklightPath();
    void readBrightness();

    QString m_backlightPath;
    QString m_touchInhibitPath;
    QString m_powerKeyPath;
    QString m_volumeKeyPath;
    int m_maxBrightness = 0;
    int m_brightnessPercent = 50;

    int m_powerInputFd = -1;
    int m_volumeInputFd = -1;
    QSocketNotifier *m_powerNotifier = nullptr;
    QSocketNotifier *m_volumeNotifier = nullptr;
    bool m_isScreenOn = true;
    QTimer *m_longPressTimer = nullptr;
    bool m_volumeUpPressed = false;
    bool m_volumeDownPressed = false;
    bool m_screenshotComboTriggered = false;
};
