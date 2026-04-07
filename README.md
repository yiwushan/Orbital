![](https://imagehost.athbe.cn/wp-content/uploads/2026/01/1768156951-Orbital-logo.png)

# Orbital

**Orbital** 是一个专为 Linux 移动设备设计的现代化、轻量级桌面环境（Dashboard）。

它基于 **Qt 6** 和 **QML** 构建，旨在以极低的资源占用提供流畅的动画效果和直观的交互体验。

## 截图

![](https://imagehost.athbe.cn/wp-content/uploads/2026/01/1768156959-pintu-fulicat.com-1768156829261.jpg)

## 主要功能

### 主仪表盘
- **CPU、内存、存储、电池**：环形进度卡，点击可查看详细信息
- **网络**：实时上传/下载速率，点击查看各网卡接口详情
- **历史折线图**：CPU、内存、网络 I/O 历史曲线
- **防烧屏机制**：主界面每 `45s` 进行 `±3px` 水平微位移，并叠加低幅度亮度呼吸（约 `1.8%~5.5%`）
- **空闲节能防烧屏**：`3` 分钟无操作降亮，`10` 分钟无操作黑屏；黑屏后每 `1` 小时短亮 `20s` 便于状态巡检，触摸/按键可立即唤醒
- **摄像头在场唤醒（可选）**：启用后使用前置摄像头做人脸检测，检测到人时自动唤醒屏幕
- **截图**：同时按下音量+ 和音量- 触发，保存到 `--screenshot-dir` 指定目录，未指定时默认保存到 `~/Pictures/Orbital/Screenshots`

### 设置
- 屏幕亮度调节
- WiFi 管理
- LED 控制
- 系统详情
- 关于

### WiFi 管理
- 开关 WiFi，自动扫描周边热点
- 连接新网络（内置软键盘输入密码）
- 已保存网络的自动连接开关、忘记网络
- 已连接网络的 IP、MAC、信号强度详情

### LED 控制
- 统一切换所有 LED 的 trigger 模式（manual、default-on、heartbeat 等）
- 全局亮度调节
- 闪光灯亮度与时长控制
- 每个 LED 独立调节

### 系统详情
- 主机名、运行时间、IP 地址、系统与内核版本、系统负载、根分区使用量
- 各 CPU 核心当前频率
- Top 进程列表（按 CPU 占用排序，可选显示 3 / 5 / 8 / 10 条）
- 温度传感器列表

### 终端
- 持久化 PTY Shell，自动适配终端尺寸
- 工具栏快捷键：Ctrl+C/D/L、Home/End、PgUp/PgDn、粘贴、清屏、重置、字号调节
- 文本选择与复制
- 内置软键盘，终端模式下附加 Esc、Tab、方向键、Ctrl、Alt 功能键

---

## 编译

### 编译依赖

#### Debian / Ubuntu
```bash
sudo apt install cmake g++ git qt6-base-dev qt6-declarative-dev libgl-dev libegl-dev
```

#### Arch Linux
```bash
sudo pacman -S cmake gcc git qt6-base qt6-declarative
```

### 编译步骤

```bash
git clone https://github.com/AthBe1337/Orbital.git
cd Orbital
cmake -B build
cmake --build build -j$(nproc)
```

---

## 运行时依赖

| 功能 | 依赖 |
|------|------|
| WiFi 管理 | NetworkManager（`nmcli`） |
| 显示输出 | Qt eglfs / kms 后端 |
| 触摸输入 | Linux evdev 驱动，Qt evdev 插件 |
| 亮度调节 | `/sys/class/backlight/` 节点可写 |
| LED 控制 | `/sys/class/leds/` 节点可写 |
| 人在场唤醒（可选） | `python3-opencv`（摄像头检测） |
| 内网页面服务（可选） | `python3`（标准库即可） |

#### Debian / Ubuntu 运行时包
```bash
sudo apt install libqt6quick6 libqt6qml6 qml6-module-qtquick \
    qml6-module-qtquick-controls qml6-module-qtquick-layouts network-manager \
    python3-opencv
```

---

## 运行

```bash
cd build
./run.sh [选项]
```

### 选项

| 选项 | 说明 | 默认值 |
|------|------|--------|
| `--scale <值>` | Qt 缩放因子 | `2.14` |
| `--touch-input-path <路径>` | 触摸屏 evdev 设备路径 | `/dev/input/event5` |
| `--touch-inhibit-path <路径>` | 触摸抑制 sysfs 路径 | `/sys/devices/...input5/inhibited` |
| `--power-key-path <路径>` | 电源键 evdev 设备路径 | `/dev/input/event0` |
| `--volume-key-path <路径>` | 音量键 evdev 设备路径 | `/dev/input/event3` |
| `--screenshot-dir <路径>` | 截图保存目录 | 空（默认 `~/Pictures/Orbital/Screenshots`） |
| `--remote-host-1 <user@host>` | 远端服务器1（SSH） | 空 |
| `--remote-host-2 <user@host>` | 远端服务器2（SSH） | 空 |
| `--remote-port-1 <port>` | 远端服务器1 SSH 端口 | `22` |
| `--remote-port-2 <port>` | 远端服务器2 SSH 端口 | `22` |
| `--remote-name-1 <名称>` | 远端服务器1显示名 | 空（默认 `Remote-A`） |
| `--remote-name-2 <名称>` | 远端服务器2显示名 | 空（默认 `Remote-B`） |
| `--remote-interval-sec <秒>` | 远端轮询周期 | `60` |
| `--person-wake-enabled <0|1>` | 人在场检测唤醒开关 | `1` |
| `--person-wake-device <路径>` | 人在场检测摄像头设备 | `/dev/video0` |
| `--person-wake-cooldown-sec <秒>` | 两次自动唤醒最小间隔 | `20` |
| `--person-wake-libcamera-index <数字>` | fallback 模式的 libcamera 相机索引 | `1` |
| `--person-wake-motion-threshold <值>` | fallback 模式的运动检测阈值 | `12.0` |
| `--web-enabled <0|1>` | 启用内网页面服务 | `1` |
| `--web-bind <地址>` | 内网页面监听地址 | `0.0.0.0` |
| `--web-port <端口>` | 内网页面监听端口 | `18911` |
| `--web-auth-enabled <0|1>` | 启用内网页登录认证 | `0` |
| `--web-user <用户名>` | 内网页登录用户名（仅在认证开启时生效） | `admin` |
| `--web-password <密码>` | 内网页登录密码（仅在认证开启时生效） | `orbital123` |
| `--web-show-remote-addr <0|1>` | 页面/API中显示远端地址 | `0` |
| `--web-base-interval-sec <秒>` | 页面常规刷新采样周期 | `60` |
| `--web-burst-interval-sec <秒>` | 页面密集刷新采样周期 | `5` |
| `--web-burst-duration-sec <秒>` | 登录后密集刷新持续时长 | `180` |
| `--web-session-hours <小时>` | 页面登录会话过期时间 | `8` |
| `--web-remote-timeout-sec <秒>` | 页面远端 SSH 采集超时 | `7` |
| `--web-log-path <路径>` | 页面服务日志路径 | `./orbital_web.log` |

`run.sh` 使用 `QT_QPA_PLATFORM=eglfs`，直接在 framebuffer 上运行，无需 X11 或 Wayland。

### 远端服务器监控（可选）

可通过环境变量接入 2 台内网服务器（SSH 免密），在 Dashboard 下方显示远端 CPU/MEM/DISK/Load 概览，并把远端 CPU 核心按 8 组均值展示：

| 环境变量 | 说明 | 默认值 |
|------|------|--------|
| `ORBITAL_REMOTE_HOST_1` | 远端1（例如 `user@10.0.0.11`） | 空 |
| `ORBITAL_REMOTE_HOST_2` | 远端2（例如 `user@10.0.0.12`） | 空 |
| `ORBITAL_REMOTE_PORT_1` | 远端1 SSH 端口 | `22` |
| `ORBITAL_REMOTE_PORT_2` | 远端2 SSH 端口 | `22` |
| `ORBITAL_REMOTE_NAME_1` | 远端1显示名称 | `Remote-A` |
| `ORBITAL_REMOTE_NAME_2` | 远端2显示名称 | `Remote-B` |
| `ORBITAL_REMOTE_INTERVAL_SEC` | 远端轮询周期（秒） | `60` |
| `ORBITAL_PERSON_WAKE_ENABLED` | 人在场检测唤醒开关 | `1` |
| `ORBITAL_PERSON_WAKE_DEVICE` | 人在场检测摄像头设备 | `/dev/video0` |
| `ORBITAL_PERSON_WAKE_COOLDOWN_SEC` | 自动唤醒冷却时间（秒） | `20` |
| `ORBITAL_PERSON_WAKE_LIBCAMERA_INDEX` | fallback 模式的 libcamera 相机索引 | `1` |
| `ORBITAL_PERSON_WAKE_MOTION_THRESHOLD` | fallback 模式的运动检测阈值 | `12.0` |
| `ORBITAL_WEB_ENABLED` | 启用内网页面服务 | `1` |
| `ORBITAL_WEB_BIND` | 页面监听地址 | `0.0.0.0` |
| `ORBITAL_WEB_PORT` | 页面监听端口 | `18911` |
| `ORBITAL_WEB_AUTH_ENABLED` | 页面登录认证开关 | `0` |
| `ORBITAL_WEB_USER` | 页面登录用户名（仅在认证开启时生效） | `admin` |
| `ORBITAL_WEB_PASSWORD` | 页面登录密码（仅在认证开启时生效） | `orbital123` |
| `ORBITAL_WEB_SHOW_REMOTE_ADDR` | 页面/API中显示远端地址 | `0` |
| `ORBITAL_WEB_BASE_INTERVAL_SEC` | 页面常规采样周期（秒） | `60` |
| `ORBITAL_WEB_BURST_INTERVAL_SEC` | 页面密集采样周期（秒） | `5` |
| `ORBITAL_WEB_BURST_DURATION_SEC` | 登录触发密集刷新时长（秒） | `180` |
| `ORBITAL_WEB_SESSION_HOURS` | 登录会话过期（小时） | `8` |
| `ORBITAL_WEB_REMOTE_TIMEOUT_SEC` | 页面远端 SSH 超时（秒） | `7` |
| `ORBITAL_WEB_LOG_PATH` | 页面服务日志路径 | `./orbital_web.log` |

说明：
- 建议使用 SSH key 免密登录（`BatchMode=yes`），避免交互阻塞。
- 默认远端轮询周期是 `60` 秒（可通过 `ORBITAL_REMOTE_INTERVAL_SEC` 或 `--remote-interval-sec` 调整）。
- 用户点击远端卡片后会进入临时加速刷新：`5` 秒/次，持续 `60` 秒，然后自动恢复到基础周期。
- 访问内网页面（或登录成功）会触发页面端密集采样：`5` 秒/次，持续 `180` 秒（可通过 web 环境变量调整）。
- 内网页面访问地址：`http://<设备IP>:18911/`；默认免密，如需认证可开启 `ORBITAL_WEB_AUTH_ENABLED=1` 并修改账号密码。
- 历史图按真实时间戳绘制（`5s` 与 `60s` 采样在同一时间轴上间距不同）。
- 远端历史窗口为最近 `1` 小时。
- 在场唤醒优先使用 OpenCV 人脸检测；若 `/dev/video*` 无法直接读取，会自动切换到 `cam` 原始帧运动检测 fallback。

---

## 移植说明

目前仅在**一加 6T**（Snapdragon 845）上测试通过。移植到其他设备时需根据实际情况调整以下参数：

- **触摸输入路径**：`--touch-input-path`（用 `evtest` 确认正确设备）
- **触摸抑制路径**：`--touch-inhibit-path`（不支持的设备可指向不存在的路径）
- **电源键/音量键路径**：`--power-key-path`、`--volume-key-path`
- **缩放因子**：`--scale`（根据屏幕分辨率和 DPI 调整）

## 更新与部署作业规范

为保证每次更新可追踪、可回滚、可复现，后续所有更新与推送请严格遵循：

- [`docs/UPDATE_DEPLOY_SOP.md`](docs/UPDATE_DEPLOY_SOP.md)

## 版本发布

- [`docs/RELEASE_V1.md`](docs/RELEASE_V1.md)

## 贡献

欢迎提交 Issue 或 Pull Request！如果你有关于性能优化或新功能的建议，请随时联系。
