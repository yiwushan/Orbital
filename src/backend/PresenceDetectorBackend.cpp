#include "PresenceDetectorBackend.h"

#include "SystemHelpers.h"

#include <QCoreApplication>
#include <QFileInfo>
#include <QProcess>
#include <QTimer>

#include <algorithm>

namespace {

constexpr int kDefaultSampleMs = 900;
constexpr int kDefaultRequiredHits = 2;
constexpr int kMinCooldownSec = 5;
constexpr int kMaxCooldownSec = 600;
constexpr int kRestartDelayMs = 3000;
constexpr int kMinLibcameraIndex = 1;
constexpr int kMaxLibcameraIndex = 8;
constexpr double kMinMotionThreshold = 1.0;
constexpr double kMaxMotionThreshold = 80.0;

int parseIntBounded(const QString &text, int fallback, int minValue, int maxValue)
{
    bool ok = false;
    const int value = text.toInt(&ok);
    if (!ok) {
        return fallback;
    }

    return std::clamp(value, minValue, maxValue);
}

double parseDoubleBounded(const QString &text, double fallback, double minValue, double maxValue)
{
    bool ok = false;
    const double value = text.toDouble(&ok);
    if (!ok) {
        return fallback;
    }

    if (value < minValue) {
        return minValue;
    }
    if (value > maxValue) {
        return maxValue;
    }
    return value;
}

} // namespace

PresenceDetectorBackend::PresenceDetectorBackend(QObject *parent)
    : QObject(parent)
    , m_restartTimer(new QTimer(this))
{
    m_enabled = parseBoolEnv(Backend::readEnvironmentValue("ORBITAL_PERSON_WAKE_ENABLED"), true);

    const QString configuredDevice = Backend::readEnvironmentValue("ORBITAL_PERSON_WAKE_DEVICE");
    if (!configuredDevice.isEmpty()) {
        m_device = configuredDevice;
    }

    m_cooldownSec = parseIntBounded(Backend::readEnvironmentValue("ORBITAL_PERSON_WAKE_COOLDOWN_SEC"),
                                    m_cooldownSec, kMinCooldownSec, kMaxCooldownSec);
    m_libcameraIndex = parseIntBounded(Backend::readEnvironmentValue("ORBITAL_PERSON_WAKE_LIBCAMERA_INDEX"),
                                       m_libcameraIndex, kMinLibcameraIndex, kMaxLibcameraIndex);
    m_motionThreshold = parseDoubleBounded(Backend::readEnvironmentValue("ORBITAL_PERSON_WAKE_MOTION_THRESHOLD"),
                                           m_motionThreshold, kMinMotionThreshold, kMaxMotionThreshold);

    m_restartTimer->setSingleShot(true);
    connect(m_restartTimer, &QTimer::timeout, this, [this]() {
        if (m_enabled) {
            startProcess();
        }
    });

    if (m_enabled) {
        startProcess();
    } else {
        setStatus(QStringLiteral("Disabled"));
    }
}

PresenceDetectorBackend::~PresenceDetectorBackend()
{
    stopProcess();
}

bool PresenceDetectorBackend::enabled() const
{
    return m_enabled;
}

void PresenceDetectorBackend::setEnabled(bool enabled)
{
    if (m_enabled == enabled) {
        return;
    }

    m_enabled = enabled;
    emit enabledChanged();

    if (!m_enabled) {
        stopProcess();
        m_restartTimer->stop();
        setStatus(QStringLiteral("Disabled"));
        return;
    }

    setStatus(QStringLiteral("Starting"));
    startProcess();
}

bool PresenceDetectorBackend::running() const
{
    return m_running;
}

QString PresenceDetectorBackend::status() const
{
    return m_status;
}

QString PresenceDetectorBackend::device() const
{
    return m_device;
}

void PresenceDetectorBackend::setDevice(const QString &devicePath)
{
    const QString normalized = devicePath.trimmed();
    if (normalized.isEmpty() || normalized == m_device) {
        return;
    }

    m_device = normalized;
    emit deviceChanged();

    if (!m_enabled) {
        return;
    }

    stopProcess();
    startProcess();
}

int PresenceDetectorBackend::cooldownSec() const
{
    return m_cooldownSec;
}

void PresenceDetectorBackend::setCooldownSec(int seconds)
{
    const int bounded = std::clamp(seconds, kMinCooldownSec, kMaxCooldownSec);
    if (m_cooldownSec == bounded) {
        return;
    }

    m_cooldownSec = bounded;
    emit cooldownSecChanged();
}

QString PresenceDetectorBackend::detectorScriptPath() const
{
    const QString local = QCoreApplication::applicationDirPath() + QStringLiteral("/presence_detector.py");
    if (QFileInfo::exists(local)) {
        return local;
    }

    const QString parent = QCoreApplication::applicationDirPath() + QStringLiteral("/../presence_detector.py");
    if (QFileInfo::exists(parent)) {
        return QFileInfo(parent).canonicalFilePath();
    }

    return {};
}

void PresenceDetectorBackend::startProcess()
{
    if (!m_enabled || m_process) {
        return;
    }

    const QString scriptPath = detectorScriptPath();
    if (scriptPath.isEmpty()) {
        setStatus(QStringLiteral("Detector script missing"));
        scheduleRestart(10000);
        return;
    }

    QProcess *proc = new QProcess(this);
    proc->setProgram(QStringLiteral("python3"));
    proc->setArguments({
        QStringLiteral("-u"),
        scriptPath,
        QStringLiteral("--device"), m_device,
        QStringLiteral("--sample-ms"), QString::number(kDefaultSampleMs),
        QStringLiteral("--required-hits"), QString::number(kDefaultRequiredHits),
        QStringLiteral("--libcamera-index"), QString::number(m_libcameraIndex),
        QStringLiteral("--motion-threshold"), QString::number(m_motionThreshold, 'f', 1)
    });
    proc->setProcessChannelMode(QProcess::SeparateChannels);

    connect(proc, &QProcess::readyReadStandardOutput, this, &PresenceDetectorBackend::parseStdoutLines);

    connect(proc, &QProcess::readyReadStandardError, this, [this, proc]() {
        const QString raw = QString::fromUtf8(proc->readAllStandardError()).trimmed();
        if (!raw.isEmpty()) {
            setStatus(QStringLiteral("Detector stderr: %1").arg(raw.left(120)));
        }
    });

    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this](int exitCode, QProcess::ExitStatus status) {
        m_process = nullptr;
        setRunning(false);

        if (!m_enabled) {
            return;
        }

        const QString reason = (status == QProcess::NormalExit)
                                   ? QStringLiteral("Detector exited(%1)").arg(exitCode)
                                   : QStringLiteral("Detector crashed");
        setStatus(reason);
        scheduleRestart(kRestartDelayMs);
    });

    connect(proc, &QProcess::errorOccurred, this, [this](QProcess::ProcessError) {
        setStatus(QStringLiteral("Detector start failed"));
    });

    m_process = proc;
    setStatus(QStringLiteral("Starting"));
    proc->start();

    if (!proc->waitForStarted(1200)) {
        setStatus(QStringLiteral("Python3 unavailable"));
        stopProcess();
        scheduleRestart(10000);
        return;
    }

    setRunning(true);
}

void PresenceDetectorBackend::stopProcess()
{
    if (!m_process) {
        setRunning(false);
        return;
    }

    QProcess *proc = m_process;
    m_process = nullptr;

    if (proc->state() != QProcess::NotRunning) {
        proc->terminate();
        if (!proc->waitForFinished(300)) {
            proc->kill();
            proc->waitForFinished(500);
        }
    }

    proc->deleteLater();
    setRunning(false);
}

void PresenceDetectorBackend::scheduleRestart(int delayMs)
{
    if (!m_enabled) {
        return;
    }
    m_restartTimer->start(std::max(500, delayMs));
}

void PresenceDetectorBackend::setRunning(bool running)
{
    if (m_running == running) {
        return;
    }

    m_running = running;
    emit runningChanged();
}

void PresenceDetectorBackend::setStatus(const QString &status)
{
    if (m_status == status) {
        return;
    }

    m_status = status;
    emit statusChanged();
}

void PresenceDetectorBackend::parseStdoutLines()
{
    if (!m_process) {
        return;
    }

    while (m_process->canReadLine()) {
        const QString line = QString::fromUtf8(m_process->readLine()).trimmed();
        if (line.isEmpty()) {
            continue;
        }

        if (line.startsWith(QStringLiteral("STATUS "))) {
            setStatus(line.mid(7));
            continue;
        }

        if (line.startsWith(QStringLiteral("ERROR "))) {
            setStatus(line);
            continue;
        }

        if (line.startsWith(QStringLiteral("EVENT PERSON "))) {
            const QString value = line.section(QLatin1Char(' '), 2, 2).trimmed();
            if (value == QLatin1String("1")) {
                handleDetectionEvent();
            }
            continue;
        }
    }
}

void PresenceDetectorBackend::handleDetectionEvent()
{
    const QDateTime now = QDateTime::currentDateTime();
    if (m_lastDetectionAt.isValid()
        && m_lastDetectionAt.secsTo(now) < std::max(kMinCooldownSec, m_cooldownSec)) {
        return;
    }

    m_lastDetectionAt = now;
    setStatus(QStringLiteral("Person detected @ %1").arg(now.toString(QStringLiteral("HH:mm:ss"))));
    emit personDetected();
}

bool PresenceDetectorBackend::parseBoolEnv(const QString &value, bool fallback) const
{
    const QString lower = value.trimmed().toLower();
    if (lower.isEmpty()) {
        return fallback;
    }

    if (lower == QLatin1String("1") || lower == QLatin1String("true")
        || lower == QLatin1String("yes") || lower == QLatin1String("on")) {
        return true;
    }

    if (lower == QLatin1String("0") || lower == QLatin1String("false")
        || lower == QLatin1String("no") || lower == QLatin1String("off")) {
        return false;
    }

    return fallback;
}
