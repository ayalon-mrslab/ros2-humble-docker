#!/bin/bash
# Start the ROS 2 Humble container (GPU by default) and open a shell in it.
set -e
cd "$(dirname "$0")"

CONTAINER_NAME=ros2_humble
ENV_FILE=.env
USE_GPU=true
INSTALL_DEPS=true
BUILD_FLAG=""
WS_ARG=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --ws PATH    Local workspace (the folder that contains src/) to mount (saved to
               ${ENV_FILE} for next runs). --src PATH is accepted too (its parent is used).
  --no-gpu     Run without NVIDIA GPU passthrough
  --no-deps    Skip installing missing workspace dependencies (rosdep)
  --build      Rebuild the image before starting
  -h, --help   Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ws|--src)
            [[ -n "$2" ]] || { echo "Error: $1 requires a path" >&2; exit 1; }
            WS_ARG="$2"; shift ;;
        --no-gpu)   USE_GPU=false ;;
        --no-deps)  INSTALL_DEPS=false ;;
        --build)   BUILD_FLAG="--build" ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
    shift
done

# Already running, and nothing asked to change it (--build, --ws, --no-gpu)? Just open
# another shell in it.
if [[ -z "${BUILD_FLAG}${WS_ARG}" ]] && $USE_GPU \
        && [[ "$(docker inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null)" == "true" ]]; then
    echo "${CONTAINER_NAME} is already running: opening a shell in it."
    exec docker exec -it "${CONTAINER_NAME}" bash
fi

# Resolve the workspace to mount: --ws overrides (and is saved), otherwise read from .env
if [[ -n "${WS_ARG}" ]]; then
    [[ -d "${WS_ARG}" ]] || { echo "Error: '${WS_ARG}' is not a directory" >&2; exit 1; }
    ROS_WS=$(realpath "${WS_ARG}")
    # Given the workspace's src/ instead of the workspace? Use its parent.
    if [[ "$(basename "${ROS_WS}")" == "src" ]]; then
        ROS_WS=$(dirname "${ROS_WS}")
        echo "Note: using '${ROS_WS}' (the workspace that contains the given src/)"
    fi
    touch "${ENV_FILE}"
    { grep -v -E '^ROS_WS(_SRC)?=' "${ENV_FILE}" || true; echo "ROS_WS=${ROS_WS}"; } > "${ENV_FILE}.tmp"
    mv "${ENV_FILE}.tmp" "${ENV_FILE}"
    echo "Saved ROS_WS to ${ENV_FILE}"
elif [[ -f "${ENV_FILE}" ]]; then
    ROS_WS=$(grep -E '^ROS_WS=' "${ENV_FILE}" | tail -n 1 | cut -d= -f2-)
    if [[ -z "${ROS_WS}" ]]; then  # an .env from before --ws: ROS_WS_SRC was its src/
        ROS_WS_SRC=$(grep -E '^ROS_WS_SRC=' "${ENV_FILE}" | tail -n 1 | cut -d= -f2-)
        [[ -n "${ROS_WS_SRC}" ]] && ROS_WS=$(dirname "${ROS_WS_SRC}")
    fi
fi

if [[ -z "${ROS_WS}" ]]; then
    echo "Error: no workspace configured." >&2
    echo "Run once with: $(basename "$0") --ws /path/to/your_ws" >&2
    exit 1
fi
if [[ ! -d "${ROS_WS}" ]]; then
    echo "Error: ROS_WS='${ROS_WS}' (from ${ENV_FILE}) does not exist." >&2
    echo "Fix it with: $(basename "$0") --ws /path/to/your_ws" >&2
    exit 1
fi
if [[ ! -d "${ROS_WS}/src" ]]; then
    echo "Warning: '${ROS_WS}' has no src/ folder - is this the right workspace?" >&2
fi
export ROS_WS
# One set of build/install/log volumes per workspace, named after its folder
export WS_NAME=$(basename "${ROS_WS}" | sed 's/[^a-zA-Z0-9_.-]/_/g')
# The volumes are mounted over these folders; create them as you, so Docker doesn't
# create them on the host as root.
mkdir -p "${ROS_WS}/build" "${ROS_WS}/install" "${ROS_WS}/log"

COMPOSE_FILES=(-f docker-compose.yml)
if $USE_GPU; then
    if ! command -v nvidia-ctk >/dev/null 2>&1; then
        echo "Error: nvidia-container-toolkit not found. Install it or run with --no-gpu." >&2
        exit 1
    fi
    COMPOSE_FILES+=(-f docker-compose.gpu.yml)
fi

# Match container user to host user so files in ./src keep host ownership
export HOST_UID=$(id -u)
export HOST_GID=$(id -g)

# Allow GUI apps in the container to use the host X server
xhost +local:docker >/dev/null 2>&1 || echo "Warning: xhost failed - GUI apps may not open." >&2

echo "Starting ${CONTAINER_NAME} (GPU: ${USE_GPU})"
echo "Mounting ${ROS_WS} -> /home/ros/ros2_ws (build/ install/ log/: volumes ros2_humble_${WS_NAME}_*)"
# Build with the host's network (like the container, network_mode: host): behind a VPN,
# Docker's default bridge network often can't reach the internet. Compose can't do this
# without extra permissions, so the image is built here.
if [[ -n "${BUILD_FLAG}" ]]; then
    docker build --network host \
        --build-arg USERNAME=ros --build-arg USER_UID="${HOST_UID}" --build-arg USER_GID="${HOST_GID}" \
        -t ros2-humble-dev .
fi
# Compose recreates the container if the image, the GPU mode or the workspace changed
docker compose "${COMPOSE_FILES[@]}" up -d


# Install system dependencies declared in the workspace package.xml files.
# Installed packages persist until the container is recreated (--build, --src change, GPU mode change).
if $INSTALL_DEPS; then
    echo "Checking workspace dependencies (rosdep)..."
    docker exec -e DEBIAN_FRONTEND=noninteractive "${CONTAINER_NAME}" bash -c '
        source /opt/ros/${ROS_DISTRO}/setup.bash
        cd ${WORKSPACE}
        if rosdep install --from-paths src --ignore-src -r --simulate 2>/dev/null | grep -q "apt-get install"; then
            sudo apt-get update -qq
            rosdep install --from-paths src --ignore-src -r -y
        else
            echo "All dependencies already installed."
        fi
    ' || echo "Warning: dependency installation failed - see output above." >&2
fi

docker exec -it "${CONTAINER_NAME}" bash
