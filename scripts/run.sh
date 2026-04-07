#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# OnePlus 6 (1080x2280) tuned default.
DEFAULT_QT_SCALE_FACTOR="2.14"
DEFAULT_TOUCH_INPUT_PATH="/dev/input/event5"
DEFAULT_TOUCH_INHIBIT_PATH="/sys/devices/platform/soc@0/ac0000.geniqup/a90000.i2c/i2c-12/12-0020/rmi4-00/input/input5/inhibited"
DEFAULT_POWER_KEY_PATH="/dev/input/event0"
DEFAULT_VOLUME_KEY_PATH="/dev/input/event3"

SCALE_VALUE="${QT_SCALE_FACTOR:-$DEFAULT_QT_SCALE_FACTOR}"
TOUCH_INPUT_PATH="${ORBITAL_TOUCH_INPUT_PATH:-$DEFAULT_TOUCH_INPUT_PATH}"
TOUCH_INHIBIT_PATH="${ORBITAL_TOUCH_INHIBIT_PATH:-$DEFAULT_TOUCH_INHIBIT_PATH}"
POWER_KEY_PATH="${ORBITAL_POWER_KEY_PATH:-$DEFAULT_POWER_KEY_PATH}"
VOLUME_KEY_PATH="${ORBITAL_VOLUME_KEY_PATH:-$DEFAULT_VOLUME_KEY_PATH}"
SCREENSHOT_DIR="${ORBITAL_SCREENSHOT_DIR:-}"
REMOTE_HOST_1="${ORBITAL_REMOTE_HOST_1:-}"
REMOTE_HOST_2="${ORBITAL_REMOTE_HOST_2:-}"
REMOTE_PORT_1="${ORBITAL_REMOTE_PORT_1:-22}"
REMOTE_PORT_2="${ORBITAL_REMOTE_PORT_2:-22}"
REMOTE_NAME_1="${ORBITAL_REMOTE_NAME_1:-}"
REMOTE_NAME_2="${ORBITAL_REMOTE_NAME_2:-}"
REMOTE_INTERVAL_SEC="${ORBITAL_REMOTE_INTERVAL_SEC:-60}"
PERSON_WAKE_ENABLED="${ORBITAL_PERSON_WAKE_ENABLED:-1}"
PERSON_WAKE_DEVICE="${ORBITAL_PERSON_WAKE_DEVICE:-/dev/video0}"
PERSON_WAKE_COOLDOWN_SEC="${ORBITAL_PERSON_WAKE_COOLDOWN_SEC:-20}"
PERSON_WAKE_LIBCAMERA_INDEX="${ORBITAL_PERSON_WAKE_LIBCAMERA_INDEX:-1}"
PERSON_WAKE_MOTION_THRESHOLD="${ORBITAL_PERSON_WAKE_MOTION_THRESHOLD:-12.0}"
WEB_ENABLED="${ORBITAL_WEB_ENABLED:-1}"
WEB_BIND="${ORBITAL_WEB_BIND:-0.0.0.0}"
WEB_PORT="${ORBITAL_WEB_PORT:-18911}"
WEB_AUTH_ENABLED="${ORBITAL_WEB_AUTH_ENABLED:-0}"
WEB_USER="${ORBITAL_WEB_USER:-admin}"
WEB_PASSWORD="${ORBITAL_WEB_PASSWORD:-orbital123}"
WEB_SHOW_REMOTE_ADDR="${ORBITAL_WEB_SHOW_REMOTE_ADDR:-0}"
WEB_BASE_INTERVAL_SEC="${ORBITAL_WEB_BASE_INTERVAL_SEC:-60}"
WEB_BURST_INTERVAL_SEC="${ORBITAL_WEB_BURST_INTERVAL_SEC:-5}"
WEB_BURST_DURATION_SEC="${ORBITAL_WEB_BURST_DURATION_SEC:-180}"
WEB_SESSION_HOURS="${ORBITAL_WEB_SESSION_HOURS:-8}"
WEB_REMOTE_TIMEOUT_SEC="${ORBITAL_WEB_REMOTE_TIMEOUT_SEC:-7}"
WEB_LOG_PATH="${ORBITAL_WEB_LOG_PATH:-${SCRIPT_DIR}/orbital_web.log}"
VOLUME_KEY_PATH_EXPLICIT=0

if [[ -n "${ORBITAL_VOLUME_KEY_PATH:-}" ]]; then
    VOLUME_KEY_PATH_EXPLICIT=1
fi

print_usage() {
    cat <<'EOF'
Usage: ./run.sh [options]

Options:
  --scale <value>                Set QT scale factor.
  --touch-input-path <path>      Set the evdev touch input path.
  --touch-inhibit-path <path>    Set the touch inhibit sysfs path.
  --power-key-path <path>        Set the power key input path.
  --volume-key-path <path>       Set the volume key input path.
  --screenshot-dir <path>        Set the screenshot output directory.
  --remote-host-1 <user@host>    Set first remote server SSH target.
  --remote-host-2 <user@host>    Set second remote server SSH target.
  --remote-port-1 <port>         Set first remote server SSH port.
  --remote-port-2 <port>         Set second remote server SSH port.
  --remote-name-1 <name>         Set first remote server display name.
  --remote-name-2 <name>         Set second remote server display name.
  --remote-interval-sec <sec>    Set remote polling interval in seconds.
  --person-wake-enabled <0|1>    Enable person detection wake-up.
  --person-wake-device <path>    Set camera device path for wake-up detector.
  --person-wake-cooldown-sec <s> Set minimum wake event interval in seconds.
  --person-wake-libcamera-index <n>  Camera index for libcamera fallback mode.
  --person-wake-motion-threshold <v> Motion score threshold in fallback mode.
  --web-enabled <0|1>           Enable LAN web dashboard service.
  --web-bind <addr>             Web service bind address. e.g. 0.0.0.0
  --web-port <port>             Web service port.
  --web-auth-enabled <0|1>      Enable web login auth.
  --web-user <user>             Web service login username.
  --web-password <pass>         Web service login password.
  --web-show-remote-addr <0|1>  Show remote host/port in web API/UI.
  --web-base-interval-sec <s>   Web polling interval in normal mode.
  --web-burst-interval-sec <s>  Web polling interval during burst mode.
  --web-burst-duration-sec <s>  Burst duration after login.
  --web-session-hours <h>       Login session expiration time.
  --web-remote-timeout-sec <s>  SSH timeout used by web remote collector.
  --web-log-path <path>         Log file path for web service.
  -h, --help                     Show this help message.
EOF
}

require_value() {
    local option_name="$1"
    local option_value="$2"

    if [[ -z "$option_value" ]]; then
        echo "Missing value for ${option_name}" >&2
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scale)
            require_value "$1" "$2"
            SCALE_VALUE="$2"
            shift 2
            ;;
        --scale=*)
            SCALE_VALUE="${1#*=}"
            require_value "--scale" "$SCALE_VALUE"
            shift
            ;;
        --touch-input-path)
            require_value "$1" "$2"
            TOUCH_INPUT_PATH="$2"
            shift 2
            ;;
        --touch-input-path=*)
            TOUCH_INPUT_PATH="${1#*=}"
            require_value "--touch-input-path" "$TOUCH_INPUT_PATH"
            shift
            ;;
        --touch-inhibit-path)
            require_value "$1" "$2"
            TOUCH_INHIBIT_PATH="$2"
            shift 2
            ;;
        --touch-inhibit-path=*)
            TOUCH_INHIBIT_PATH="${1#*=}"
            require_value "--touch-inhibit-path" "$TOUCH_INHIBIT_PATH"
            shift
            ;;
        --power-key-path)
            require_value "$1" "$2"
            POWER_KEY_PATH="$2"
            if [[ $VOLUME_KEY_PATH_EXPLICIT -eq 0 ]]; then
                VOLUME_KEY_PATH="$POWER_KEY_PATH"
            fi
            shift 2
            ;;
        --power-key-path=*)
            POWER_KEY_PATH="${1#*=}"
            require_value "--power-key-path" "$POWER_KEY_PATH"
            if [[ $VOLUME_KEY_PATH_EXPLICIT -eq 0 ]]; then
                VOLUME_KEY_PATH="$POWER_KEY_PATH"
            fi
            shift
            ;;
        --volume-key-path)
            require_value "$1" "$2"
            VOLUME_KEY_PATH="$2"
            VOLUME_KEY_PATH_EXPLICIT=1
            shift 2
            ;;
        --volume-key-path=*)
            VOLUME_KEY_PATH="${1#*=}"
            require_value "--volume-key-path" "$VOLUME_KEY_PATH"
            VOLUME_KEY_PATH_EXPLICIT=1
            shift
            ;;
        --screenshot-dir)
            require_value "$1" "$2"
            SCREENSHOT_DIR="$2"
            shift 2
            ;;
        --screenshot-dir=*)
            SCREENSHOT_DIR="${1#*=}"
            require_value "--screenshot-dir" "$SCREENSHOT_DIR"
            shift
            ;;
        --remote-host-1)
            require_value "$1" "$2"
            REMOTE_HOST_1="$2"
            shift 2
            ;;
        --remote-host-1=*)
            REMOTE_HOST_1="${1#*=}"
            require_value "--remote-host-1" "$REMOTE_HOST_1"
            shift
            ;;
        --remote-host-2)
            require_value "$1" "$2"
            REMOTE_HOST_2="$2"
            shift 2
            ;;
        --remote-host-2=*)
            REMOTE_HOST_2="${1#*=}"
            require_value "--remote-host-2" "$REMOTE_HOST_2"
            shift
            ;;
        --remote-port-1)
            require_value "$1" "$2"
            REMOTE_PORT_1="$2"
            shift 2
            ;;
        --remote-port-1=*)
            REMOTE_PORT_1="${1#*=}"
            require_value "--remote-port-1" "$REMOTE_PORT_1"
            shift
            ;;
        --remote-port-2)
            require_value "$1" "$2"
            REMOTE_PORT_2="$2"
            shift 2
            ;;
        --remote-port-2=*)
            REMOTE_PORT_2="${1#*=}"
            require_value "--remote-port-2" "$REMOTE_PORT_2"
            shift
            ;;
        --remote-name-1)
            require_value "$1" "$2"
            REMOTE_NAME_1="$2"
            shift 2
            ;;
        --remote-name-1=*)
            REMOTE_NAME_1="${1#*=}"
            require_value "--remote-name-1" "$REMOTE_NAME_1"
            shift
            ;;
        --remote-name-2)
            require_value "$1" "$2"
            REMOTE_NAME_2="$2"
            shift 2
            ;;
        --remote-name-2=*)
            REMOTE_NAME_2="${1#*=}"
            require_value "--remote-name-2" "$REMOTE_NAME_2"
            shift
            ;;
        --remote-interval-sec)
            require_value "$1" "$2"
            REMOTE_INTERVAL_SEC="$2"
            shift 2
            ;;
        --remote-interval-sec=*)
            REMOTE_INTERVAL_SEC="${1#*=}"
            require_value "--remote-interval-sec" "$REMOTE_INTERVAL_SEC"
            shift
            ;;
        --person-wake-enabled)
            require_value "$1" "$2"
            PERSON_WAKE_ENABLED="$2"
            shift 2
            ;;
        --person-wake-enabled=*)
            PERSON_WAKE_ENABLED="${1#*=}"
            require_value "--person-wake-enabled" "$PERSON_WAKE_ENABLED"
            shift
            ;;
        --person-wake-device)
            require_value "$1" "$2"
            PERSON_WAKE_DEVICE="$2"
            shift 2
            ;;
        --person-wake-device=*)
            PERSON_WAKE_DEVICE="${1#*=}"
            require_value "--person-wake-device" "$PERSON_WAKE_DEVICE"
            shift
            ;;
        --person-wake-cooldown-sec)
            require_value "$1" "$2"
            PERSON_WAKE_COOLDOWN_SEC="$2"
            shift 2
            ;;
        --person-wake-cooldown-sec=*)
            PERSON_WAKE_COOLDOWN_SEC="${1#*=}"
            require_value "--person-wake-cooldown-sec" "$PERSON_WAKE_COOLDOWN_SEC"
            shift
            ;;
        --person-wake-libcamera-index)
            require_value "$1" "$2"
            PERSON_WAKE_LIBCAMERA_INDEX="$2"
            shift 2
            ;;
        --person-wake-libcamera-index=*)
            PERSON_WAKE_LIBCAMERA_INDEX="${1#*=}"
            require_value "--person-wake-libcamera-index" "$PERSON_WAKE_LIBCAMERA_INDEX"
            shift
            ;;
        --person-wake-motion-threshold)
            require_value "$1" "$2"
            PERSON_WAKE_MOTION_THRESHOLD="$2"
            shift 2
            ;;
        --person-wake-motion-threshold=*)
            PERSON_WAKE_MOTION_THRESHOLD="${1#*=}"
            require_value "--person-wake-motion-threshold" "$PERSON_WAKE_MOTION_THRESHOLD"
            shift
            ;;
        --web-enabled)
            require_value "$1" "$2"
            WEB_ENABLED="$2"
            shift 2
            ;;
        --web-enabled=*)
            WEB_ENABLED="${1#*=}"
            require_value "--web-enabled" "$WEB_ENABLED"
            shift
            ;;
        --web-bind)
            require_value "$1" "$2"
            WEB_BIND="$2"
            shift 2
            ;;
        --web-bind=*)
            WEB_BIND="${1#*=}"
            require_value "--web-bind" "$WEB_BIND"
            shift
            ;;
        --web-port)
            require_value "$1" "$2"
            WEB_PORT="$2"
            shift 2
            ;;
        --web-port=*)
            WEB_PORT="${1#*=}"
            require_value "--web-port" "$WEB_PORT"
            shift
            ;;
        --web-auth-enabled)
            require_value "$1" "$2"
            WEB_AUTH_ENABLED="$2"
            shift 2
            ;;
        --web-auth-enabled=*)
            WEB_AUTH_ENABLED="${1#*=}"
            require_value "--web-auth-enabled" "$WEB_AUTH_ENABLED"
            shift
            ;;
        --web-user)
            require_value "$1" "$2"
            WEB_USER="$2"
            shift 2
            ;;
        --web-user=*)
            WEB_USER="${1#*=}"
            require_value "--web-user" "$WEB_USER"
            shift
            ;;
        --web-password)
            require_value "$1" "$2"
            WEB_PASSWORD="$2"
            shift 2
            ;;
        --web-password=*)
            WEB_PASSWORD="${1#*=}"
            require_value "--web-password" "$WEB_PASSWORD"
            shift
            ;;
        --web-show-remote-addr)
            require_value "$1" "$2"
            WEB_SHOW_REMOTE_ADDR="$2"
            shift 2
            ;;
        --web-show-remote-addr=*)
            WEB_SHOW_REMOTE_ADDR="${1#*=}"
            require_value "--web-show-remote-addr" "$WEB_SHOW_REMOTE_ADDR"
            shift
            ;;
        --web-base-interval-sec)
            require_value "$1" "$2"
            WEB_BASE_INTERVAL_SEC="$2"
            shift 2
            ;;
        --web-base-interval-sec=*)
            WEB_BASE_INTERVAL_SEC="${1#*=}"
            require_value "--web-base-interval-sec" "$WEB_BASE_INTERVAL_SEC"
            shift
            ;;
        --web-burst-interval-sec)
            require_value "$1" "$2"
            WEB_BURST_INTERVAL_SEC="$2"
            shift 2
            ;;
        --web-burst-interval-sec=*)
            WEB_BURST_INTERVAL_SEC="${1#*=}"
            require_value "--web-burst-interval-sec" "$WEB_BURST_INTERVAL_SEC"
            shift
            ;;
        --web-burst-duration-sec)
            require_value "$1" "$2"
            WEB_BURST_DURATION_SEC="$2"
            shift 2
            ;;
        --web-burst-duration-sec=*)
            WEB_BURST_DURATION_SEC="${1#*=}"
            require_value "--web-burst-duration-sec" "$WEB_BURST_DURATION_SEC"
            shift
            ;;
        --web-session-hours)
            require_value "$1" "$2"
            WEB_SESSION_HOURS="$2"
            shift 2
            ;;
        --web-session-hours=*)
            WEB_SESSION_HOURS="${1#*=}"
            require_value "--web-session-hours" "$WEB_SESSION_HOURS"
            shift
            ;;
        --web-remote-timeout-sec)
            require_value "$1" "$2"
            WEB_REMOTE_TIMEOUT_SEC="$2"
            shift 2
            ;;
        --web-remote-timeout-sec=*)
            WEB_REMOTE_TIMEOUT_SEC="${1#*=}"
            require_value "--web-remote-timeout-sec" "$WEB_REMOTE_TIMEOUT_SEC"
            shift
            ;;
        --web-log-path)
            require_value "$1" "$2"
            WEB_LOG_PATH="$2"
            shift 2
            ;;
        --web-log-path=*)
            WEB_LOG_PATH="${1#*=}"
            require_value "--web-log-path" "$WEB_LOG_PATH"
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            print_usage >&2
            exit 1
            ;;
    esac
done

export QT_SCALE_FACTOR="$SCALE_VALUE"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-eglfs}"
export ORBITAL_TOUCH_INPUT_PATH="$TOUCH_INPUT_PATH"
export ORBITAL_TOUCH_INHIBIT_PATH="$TOUCH_INHIBIT_PATH"
export ORBITAL_POWER_KEY_PATH="$POWER_KEY_PATH"
export ORBITAL_VOLUME_KEY_PATH="$VOLUME_KEY_PATH"
export ORBITAL_SCREENSHOT_DIR="$SCREENSHOT_DIR"
export ORBITAL_REMOTE_HOST_1="$REMOTE_HOST_1"
export ORBITAL_REMOTE_HOST_2="$REMOTE_HOST_2"
export ORBITAL_REMOTE_PORT_1="$REMOTE_PORT_1"
export ORBITAL_REMOTE_PORT_2="$REMOTE_PORT_2"
export ORBITAL_REMOTE_NAME_1="$REMOTE_NAME_1"
export ORBITAL_REMOTE_NAME_2="$REMOTE_NAME_2"
export ORBITAL_REMOTE_INTERVAL_SEC="$REMOTE_INTERVAL_SEC"
export ORBITAL_PERSON_WAKE_ENABLED="$PERSON_WAKE_ENABLED"
export ORBITAL_PERSON_WAKE_DEVICE="$PERSON_WAKE_DEVICE"
export ORBITAL_PERSON_WAKE_COOLDOWN_SEC="$PERSON_WAKE_COOLDOWN_SEC"
export ORBITAL_PERSON_WAKE_LIBCAMERA_INDEX="$PERSON_WAKE_LIBCAMERA_INDEX"
export ORBITAL_PERSON_WAKE_MOTION_THRESHOLD="$PERSON_WAKE_MOTION_THRESHOLD"
export ORBITAL_WEB_ENABLED="$WEB_ENABLED"
export ORBITAL_WEB_BIND="$WEB_BIND"
export ORBITAL_WEB_PORT="$WEB_PORT"
export ORBITAL_WEB_AUTH_ENABLED="$WEB_AUTH_ENABLED"
export ORBITAL_WEB_USER="$WEB_USER"
export ORBITAL_WEB_PASSWORD="$WEB_PASSWORD"
export ORBITAL_WEB_SHOW_REMOTE_ADDR="$WEB_SHOW_REMOTE_ADDR"
export ORBITAL_WEB_BASE_INTERVAL_SEC="$WEB_BASE_INTERVAL_SEC"
export ORBITAL_WEB_BURST_INTERVAL_SEC="$WEB_BURST_INTERVAL_SEC"
export ORBITAL_WEB_BURST_DURATION_SEC="$WEB_BURST_DURATION_SEC"
export ORBITAL_WEB_SESSION_HOURS="$WEB_SESSION_HOURS"
export ORBITAL_WEB_REMOTE_TIMEOUT_SEC="$WEB_REMOTE_TIMEOUT_SEC"
export ORBITAL_WEB_LOG_PATH="$WEB_LOG_PATH"
export QT_QPA_GENERIC_PLUGINS="evdevtouch:${ORBITAL_TOUCH_INPUT_PATH}"

WEB_SERVER_PID=""

start_web_service() {
    if [[ "$ORBITAL_WEB_ENABLED" != "1" ]]; then
        return
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        echo "[Orbital] python3 not found, web service disabled." >&2
        return
    fi

    if [[ ! -f "./orbital_web.py" ]]; then
        echo "[Orbital] orbital_web.py missing, web service disabled." >&2
        return
    fi

    mkdir -p "$(dirname "$ORBITAL_WEB_LOG_PATH")" 2>/dev/null || true
    python3 ./orbital_web.py >>"$ORBITAL_WEB_LOG_PATH" 2>&1 &
    WEB_SERVER_PID=$!
    sleep 0.2

    if ! kill -0 "$WEB_SERVER_PID" 2>/dev/null; then
        echo "[Orbital] failed to start web service. See $ORBITAL_WEB_LOG_PATH" >&2
        WEB_SERVER_PID=""
        return
    fi

    echo "[Orbital] web service started on ${ORBITAL_WEB_BIND}:${ORBITAL_WEB_PORT} (pid=${WEB_SERVER_PID})"
}

stop_web_service() {
    if [[ -n "$WEB_SERVER_PID" ]] && kill -0 "$WEB_SERVER_PID" 2>/dev/null; then
        kill "$WEB_SERVER_PID" 2>/dev/null || true
        wait "$WEB_SERVER_PID" 2>/dev/null || true
    fi
}

trap stop_web_service EXIT INT TERM
start_web_service

RESTART_EXIT_CODE=42
while true; do
    ./Orbital
    EXIT_CODE=$?

    if [ $EXIT_CODE -ne $RESTART_EXIT_CODE ]; then
        break
    fi

    sleep 1
done
