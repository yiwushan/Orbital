#include "RemoteServersBackend.h"

#include "SystemHelpers.h"

#include <QDir>
#include <QHash>
#include <QProcess>
#include <QTextStream>
#include <QTimer>

#include <algorithm>
#include <cmath>

namespace {

constexpr int kHostCount = 2;
constexpr int kCpuGroupCount = 8;
constexpr int kHistoryLimit = 240;
constexpr int kFastRefreshIntervalSec = 5;
constexpr int kFastRefreshDurationSec = 60;

QString formatGbFromKb(qint64 valueKb)
{
    return QString::number(valueKb / 1024.0 / 1024.0, 'f', 1) + QStringLiteral(" GB");
}

QString formatMemoryFromKb(qint64 valueKb)
{
    const qint64 safeKb = std::max<qint64>(0, valueKb);
    return Backend::formatSize(safeKb * 1024);
}

} // namespace

RemoteServersBackend::RemoteServersBackend(QObject *parent)
    : QObject(parent)
    , m_timer(new QTimer(this))
{
    m_hosts.resize(kHostCount);
    for (int i = 0; i < m_hosts.size(); ++i) {
        m_hosts[i].cpuGroups = QVariantList(kCpuGroupCount, 0.0);
    }

    loadConfigFromEnv();

    connect(m_timer, &QTimer::timeout, this, [this]() {
        refreshNow();
        applyTimerCadence();
    });
    applyTimerCadence();
    QTimer::singleShot(1200, this, &RemoteServersBackend::refreshNow);
}

void RemoteServersBackend::appendHistory(QVariantList &history, double value) const
{
    history.append(std::clamp(value, 0.0, 100.0));
    while (history.size() > kHistoryLimit) {
        history.removeFirst();
    }
}

void RemoteServersBackend::applyTimerCadence()
{
    int desiredIntervalSec = m_intervalSec;
    const QDateTime now = QDateTime::currentDateTime();
    if (m_fastRefreshUntil.isValid()) {
        if (now < m_fastRefreshUntil) {
            desiredIntervalSec = kFastRefreshIntervalSec;
        } else {
            m_fastRefreshUntil = QDateTime();
        }
    }

    const int intervalMs = std::max(1, desiredIntervalSec) * 1000;
    if (m_timer->interval() != intervalMs) {
        m_timer->setInterval(intervalMs);
    }
    if (!m_timer->isActive()) {
        m_timer->start();
    }
}

QVariantList RemoteServersBackend::servers() const
{
    QVariantList list;
    list.reserve(m_hosts.size());
    for (const HostState &host : m_hosts) {
        list.append(stateToMap(host));
    }
    return list;
}

int RemoteServersBackend::intervalSec() const
{
    return m_intervalSec;
}

void RemoteServersBackend::setIntervalSec(int seconds)
{
    const int bounded = std::clamp(seconds, 30, 1800);
    if (m_intervalSec == bounded) {
        return;
    }

    m_intervalSec = bounded;
    applyTimerCadence();
    emit intervalSecChanged();
}

void RemoteServersBackend::refreshNow()
{
    for (int i = 0; i < m_hosts.size(); ++i) {
        startFetch(i);
    }
    applyTimerCadence();
}

void RemoteServersBackend::refreshInteractiveBurst()
{
    m_fastRefreshUntil = QDateTime::currentDateTime().addSecs(kFastRefreshDurationSec);
    refreshNow();
    applyTimerCadence();
}

QString RemoteServersBackend::envValueAny(const QStringList &keys) const
{
    for (const QString &key : keys) {
        const QString value = Backend::readEnvironmentValue(key.toLocal8Bit().constData());
        if (!value.isEmpty()) {
            return value;
        }
    }

    return {};
}

void RemoteServersBackend::loadConfigFromEnv()
{
    const QString intervalText = envValueAny({
        QStringLiteral("ORBITAL_REMOTE_INTERVAL_SEC"),
        QStringLiteral("ORBITAL_REMOTE_INTERVAL")
    });
    if (!intervalText.isEmpty()) {
        bool ok = false;
        const int interval = intervalText.toInt(&ok);
        if (ok) {
            setIntervalSec(interval);
        }
    }

    for (int i = 0; i < m_hosts.size(); ++i) {
        const int slot = i + 1;
        HostState &host = m_hosts[i];
        const QString defaultName = QStringLiteral("Remote-%1").arg(QChar('A' + i));

        host.config.name = envValueAny({
            QStringLiteral("ORBITAL_REMOTE_NAME_%1").arg(slot),
            QStringLiteral("ORBITAL_REMOTE_NAME%1").arg(slot)
        });
        if (host.config.name.isEmpty()) {
            host.config.name = defaultName;
        }

        host.config.host = envValueAny({
            QStringLiteral("ORBITAL_REMOTE_HOST_%1").arg(slot),
            QStringLiteral("ORBITAL_REMOTE_HOST%1").arg(slot)
        });
        const QString portText = envValueAny({
            QStringLiteral("ORBITAL_REMOTE_PORT_%1").arg(slot),
            QStringLiteral("ORBITAL_REMOTE_PORT%1").arg(slot)
        });
        bool okPort = false;
        const int parsedPort = portText.toInt(&okPort);
        host.config.port = (okPort && parsedPort > 0 && parsedPort <= 65535) ? parsedPort : 22;

        if (host.config.host.isEmpty()) {
            host.status = QStringLiteral("Not Configured");
            host.error = QStringLiteral("Set ORBITAL_REMOTE_HOST_%1").arg(slot);
        } else {
            host.status = QStringLiteral("Pending");
            host.error.clear();
        }
    }

    emit dataChanged();
}

void RemoteServersBackend::startFetch(int index)
{
    if (index < 0 || index >= m_hosts.size()) {
        return;
    }

    HostState &host = m_hosts[index];
    if (host.busy) {
        return;
    }

    if (host.config.host.isEmpty()) {
        host.status = QStringLiteral("Not Configured");
        emit dataChanged();
        return;
    }

    host.busy = true;
    host.status = QStringLiteral("Updating");
    emit dataChanged();

    QProcess *proc = new QProcess(this);
    proc->setProgram(QStringLiteral("ssh"));
    proc->setArguments({
        QStringLiteral("-o"), QStringLiteral("BatchMode=yes"),
        QStringLiteral("-o"), QStringLiteral("ConnectTimeout=4"),
        QStringLiteral("-o"), QStringLiteral("StrictHostKeyChecking=no"),
        QStringLiteral("-o"), QStringLiteral("UserKnownHostsFile=/dev/null"),
        QStringLiteral("-p"), QString::number(host.config.port),
        host.config.host,
        remoteCollectCommand()
    });

    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, index, proc](int exitCode, QProcess::ExitStatus exitStatus) {
        if (index < 0 || index >= m_hosts.size()) {
            proc->deleteLater();
            return;
        }

        HostState &state = m_hosts[index];
        state.busy = false;
        state.lastUpdated = QDateTime::currentDateTime();

        const QString output = QString::fromUtf8(proc->readAllStandardOutput())
                               + QString::fromUtf8(proc->readAllStandardError());

        QString parseError;
        const bool ok = (exitStatus == QProcess::NormalExit && exitCode == 0)
                        && parseSnapshotOutput(state, output, parseError);
        if (ok) {
            state.status = QStringLiteral("Online");
            state.error.clear();
        } else {
            state.status = QStringLiteral("Offline");
            if (parseError.isEmpty()) {
                parseError = output.trimmed();
            }
            state.error = parseError.left(160);
        }

        emit dataChanged();
        proc->deleteLater();
    });

    connect(proc, &QProcess::errorOccurred, this, [this, index](QProcess::ProcessError) {
        if (index < 0 || index >= m_hosts.size()) {
            return;
        }
        m_hosts[index].busy = false;
    });

    QTimer::singleShot(6500, proc, [proc]() {
        if (proc->state() != QProcess::NotRunning) {
            proc->kill();
        }
    });

    proc->start();
}

bool RemoteServersBackend::parseSnapshotOutput(HostState &host, const QString &output, QString &errorMessage)
{
    enum class Section {
        Cpu,
        Mem,
        DiskRoot,
        DiskAll,
        Load
    };

    Section section = Section::Cpu;
    QStringList cpuLines;
    QStringList memLines;
    QStringList diskRootLines;
    QStringList diskAllLines;
    QStringList loadLines;

    const QStringList lines = output.split(QLatin1Char('\n'));
    for (const QString &rawLine : lines) {
        const QString line = rawLine.trimmed();
        if (line.isEmpty()) {
            continue;
        }

        if (line == QLatin1String("__ORBITAL_MEM__")) {
            section = Section::Mem;
            continue;
        }
        if (line == QLatin1String("__ORBITAL_DF_ROOT__")) {
            section = Section::DiskRoot;
            continue;
        }
        if (line == QLatin1String("__ORBITAL_DF_ALL__")) {
            section = Section::DiskAll;
            continue;
        }
        if (line == QLatin1String("__ORBITAL_LOAD__")) {
            section = Section::Load;
            continue;
        }

        switch (section) {
        case Section::Cpu:
            cpuLines.append(line);
            break;
        case Section::Mem:
            memLines.append(line);
            break;
        case Section::DiskRoot:
            diskRootLines.append(line);
            break;
        case Section::DiskAll:
            diskAllLines.append(line);
            break;
        case Section::Load:
            loadLines.append(line);
            break;
        }
    }

    QVector<quint64> cpuTotals;
    QVector<quint64> cpuIdles;
    QVector<double> cpuUsage;

    for (const QString &line : cpuLines) {
        if (!line.startsWith(QStringLiteral("cpu"))) {
            continue;
        }

        const QStringList parts = line.simplified().split(QLatin1Char(' '), Qt::SkipEmptyParts);
        if (parts.size() < 5) {
            continue;
        }

        const QString label = parts.first();
        if (label != QLatin1String("cpu") && !label.startsWith(QStringLiteral("cpu"))) {
            continue;
        }

        bool validLine = true;
        quint64 total = 0;
        for (int i = 1; i < parts.size(); ++i) {
            bool ok = false;
            const quint64 value = parts.at(i).toULongLong(&ok);
            if (!ok) {
                validLine = false;
                break;
            }
            total += value;
        }

        if (!validLine) {
            continue;
        }

        bool okIdle = false;
        bool okIowait = true;
        const quint64 idle = parts.at(4).toULongLong(&okIdle);
        const quint64 iowait = parts.size() > 5 ? parts.at(5).toULongLong(&okIowait) : 0;
        if (!okIdle || !okIowait) {
            continue;
        }

        const quint64 idleAll = idle + iowait;
        cpuTotals.append(total);
        cpuIdles.append(idleAll);

        double usage = 0.0;
        const int idx = cpuTotals.size() - 1;
        if (host.hasPrevCpu
            && idx < host.prevCpuTotals.size()
            && idx < host.prevCpuIdles.size()) {
            const quint64 prevTotal = host.prevCpuTotals.at(idx);
            const quint64 prevIdle = host.prevCpuIdles.at(idx);
            const quint64 diffTotal = total >= prevTotal ? (total - prevTotal) : 0;
            const quint64 diffIdle = idleAll >= prevIdle ? (idleAll - prevIdle) : 0;
            if (diffTotal > 0) {
                usage = static_cast<double>(diffTotal - diffIdle) / diffTotal;
            }
        }
        cpuUsage.append(std::clamp(usage, 0.0, 1.0));
    }

    if (cpuUsage.size() < 2) {
        errorMessage = QStringLiteral("No CPU data from remote host");
        return false;
    }

    host.cpuTotal = cpuUsage.first();
    QVector<double> perCoreUsage;
    perCoreUsage.reserve(cpuUsage.size() - 1);
    for (int i = 1; i < cpuUsage.size(); ++i) {
        perCoreUsage.append(cpuUsage.at(i));
    }
    host.coreCount = perCoreUsage.size();

    QVariantList groups;
    groups.reserve(kCpuGroupCount);
    const int n = perCoreUsage.size();
    for (int g = 0; g < kCpuGroupCount; ++g) {
        const int start = g * n / kCpuGroupCount;
        const int end = (g + 1) * n / kCpuGroupCount;
        if (end <= start) {
            groups.append(0.0);
            continue;
        }

        double sum = 0.0;
        for (int i = start; i < end; ++i) {
            sum += perCoreUsage.at(i);
        }
        groups.append(sum / (end - start));
    }
    host.cpuGroups = groups;

    host.prevCpuTotals = cpuTotals;
    host.prevCpuIdles = cpuIdles;
    host.hasPrevCpu = true;

    QHash<QString, qint64> memValues;
    for (const QString &line : memLines) {
        const QString simplified = line.simplified();
        const int colonPos = simplified.indexOf(QLatin1Char(':'));
        if (colonPos <= 0) {
            continue;
        }

        const QString key = simplified.left(colonPos);
        const QString valueText = simplified.mid(colonPos + 1).trimmed().section(QLatin1Char(' '), 0, 0);
        bool ok = false;
        const qint64 valueKb = valueText.toLongLong(&ok);
        if (ok) {
            memValues.insert(key, valueKb);
        }
    }

    const qint64 memTotalKb = memValues.value(QStringLiteral("MemTotal"), 0);
    const qint64 memAvailKb = memValues.value(QStringLiteral("MemAvailable"), 0);
    const qint64 memFreeKb = memValues.value(QStringLiteral("MemFree"), 0);
    const qint64 buffersKb = memValues.value(QStringLiteral("Buffers"), 0);
    const qint64 cachedKb = memValues.value(QStringLiteral("Cached"), 0);
    const qint64 swapTotalKb = memValues.value(QStringLiteral("SwapTotal"), 0);
    const qint64 swapFreeKb = memValues.value(QStringLiteral("SwapFree"), 0);
    const qint64 swapUsedKb = std::max<qint64>(0, swapTotalKb - swapFreeKb);

    if (memTotalKb > 0) {
        const qint64 memUsedKb = std::max<qint64>(0, memTotalKb - memAvailKb);
        host.memPercent = static_cast<double>(memUsedKb) / memTotalKb;
        host.memDetail = formatGbFromKb(memUsedKb) + QStringLiteral(" / ") + formatGbFromKb(memTotalKb);
        host.memInfo = {
            { QStringLiteral("Used"), formatMemoryFromKb(memUsedKb) },
            { QStringLiteral("Total"), formatMemoryFromKb(memTotalKb) },
            { QStringLiteral("Available"), formatMemoryFromKb(memAvailKb) },
            { QStringLiteral("Free"), formatMemoryFromKb(memFreeKb) },
            { QStringLiteral("Cached"), formatMemoryFromKb(cachedKb) },
            { QStringLiteral("Buffers"), formatMemoryFromKb(buffersKb) },
            { QStringLiteral("Swap Used"), formatMemoryFromKb(swapUsedKb) },
            { QStringLiteral("Swap Free"), formatMemoryFromKb(swapFreeKb) },
            { QStringLiteral("Swap Total"), formatMemoryFromKb(swapTotalKb) }
        };
    } else {
        host.memPercent = 0.0;
        host.memDetail = QStringLiteral("--");
        host.memInfo.clear();
    }

    qint64 diskUsedBytes = 0;
    qint64 diskTotalBytes = 0;
    QVariantList partitions;
    for (const QString &line : diskAllLines) {
        const QStringList parts = line.simplified().split(QLatin1Char(' '), Qt::SkipEmptyParts);
        if (parts.size() < 7 || parts.first() == QLatin1String("Filesystem")) {
            continue;
        }

        bool okTotal = false;
        bool okUsed = false;
        bool okAvail = false;
        const qint64 totalBytes = parts.at(2).toLongLong(&okTotal);
        const qint64 usedBytes = parts.at(3).toLongLong(&okUsed);
        const qint64 availBytes = parts.at(4).toLongLong(&okAvail);
        if (!okTotal || !okUsed || !okAvail || totalBytes <= 0) {
            continue;
        }

        const QString mountPoint = parts.mid(6).join(QStringLiteral(" "));
        const double percent = static_cast<double>(usedBytes) / totalBytes;
        QVariantMap partition;
        partition[QStringLiteral("filesystem")] = parts.at(0);
        partition[QStringLiteral("type")] = parts.at(1);
        partition[QStringLiteral("size")] = Backend::formatSize(totalBytes);
        partition[QStringLiteral("used")] = Backend::formatSize(usedBytes);
        partition[QStringLiteral("available")] = Backend::formatSize(availBytes);
        partition[QStringLiteral("percent")] = percent;
        partition[QStringLiteral("mount")] = mountPoint;
        partitions.append(partition);

        if (mountPoint == QLatin1String("/") && diskTotalBytes <= 0) {
            diskTotalBytes = totalBytes;
            diskUsedBytes = usedBytes;
        }
    }
    host.diskPartitions = partitions;

    for (const QString &line : diskRootLines) {
        const QStringList parts = line.simplified().split(QLatin1Char(' '), Qt::SkipEmptyParts);
        if (parts.size() < 6 || parts.last() != QLatin1String("/")) {
            continue;
        }

        bool okTotal = false;
        bool okUsed = false;
        diskTotalBytes = parts.at(1).toLongLong(&okTotal);
        diskUsedBytes = parts.at(2).toLongLong(&okUsed);
        if (okTotal && okUsed && diskTotalBytes > 0) {
            break;
        }
    }

    if (diskTotalBytes > 0) {
        host.diskPercent = static_cast<double>(diskUsedBytes) / diskTotalBytes;
        host.diskDetail = Backend::formatSize(diskUsedBytes) + QStringLiteral(" / ") + Backend::formatSize(diskTotalBytes);
    } else {
        host.diskPercent = 0.0;
        host.diskDetail = QStringLiteral("--");
    }

    if (!loadLines.isEmpty()) {
        const QStringList parts = loadLines.first().split(QLatin1Char(' '), Qt::SkipEmptyParts);
        if (parts.size() >= 3) {
            host.loadAvg = QStringLiteral("%1 / %2 / %3").arg(parts.at(0), parts.at(1), parts.at(2));
        } else {
            host.loadAvg = QStringLiteral("--");
        }
    } else {
        host.loadAvg = QStringLiteral("--");
    }

    appendHistory(host.cpuHistory, host.cpuTotal * 100.0);
    appendHistory(host.memHistory, host.memPercent * 100.0);
    appendHistory(host.diskHistory, host.diskPercent * 100.0);

    return true;
}

QVariantMap RemoteServersBackend::stateToMap(const HostState &host) const
{
    QVariantMap map;
    map[QStringLiteral("name")] = host.config.name;
    map[QStringLiteral("host")] = host.config.host;
    map[QStringLiteral("port")] = host.config.port;
    map[QStringLiteral("status")] = host.status;
    map[QStringLiteral("error")] = host.error;
    map[QStringLiteral("busy")] = host.busy;
    map[QStringLiteral("coreCount")] = host.coreCount;
    map[QStringLiteral("cpuTotal")] = host.cpuTotal;
    map[QStringLiteral("cpuGroups")] = host.cpuGroups;
    map[QStringLiteral("cpuHistory")] = host.cpuHistory;
    map[QStringLiteral("memPercent")] = host.memPercent;
    map[QStringLiteral("memDetail")] = host.memDetail;
    map[QStringLiteral("memHistory")] = host.memHistory;
    map[QStringLiteral("memInfo")] = host.memInfo;
    map[QStringLiteral("diskPercent")] = host.diskPercent;
    map[QStringLiteral("diskDetail")] = host.diskDetail;
    map[QStringLiteral("diskHistory")] = host.diskHistory;
    map[QStringLiteral("diskPartitions")] = host.diskPartitions;
    map[QStringLiteral("loadAvg")] = host.loadAvg;
    map[QStringLiteral("lastUpdate")] = host.lastUpdated.isValid()
        ? host.lastUpdated.toString(QStringLiteral("HH:mm:ss"))
        : QStringLiteral("--");
    return map;
}

QString RemoteServersBackend::remoteCollectCommand() const
{
    return QStringLiteral(
        "LC_ALL=C sh -c '"
        "cat /proc/stat; "
        "echo __ORBITAL_MEM__; "
        "cat /proc/meminfo; "
        "echo __ORBITAL_DF_ROOT__; "
        "df -B1 /; "
        "echo __ORBITAL_DF_ALL__; "
        "df -B1 -T; "
        "echo __ORBITAL_LOAD__; "
        "cat /proc/loadavg'");
}
