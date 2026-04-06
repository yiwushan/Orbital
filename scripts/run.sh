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
export QT_QPA_GENERIC_PLUGINS="evdevtouch:${ORBITAL_TOUCH_INPUT_PATH}"
RESTART_EXIT_CODE=42
while true; do
    ./Orbital
    EXIT_CODE=$?

    if [ $EXIT_CODE -ne $RESTART_EXIT_CODE ]; then
        break
    fi

    sleep 1
done
