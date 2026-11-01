#!/bin/bash
set -e

# Source ROS 2 and, if built, the workspace overlay
source "/opt/ros/${ROS_DISTRO}/setup.bash"
if [ -f "${WORKSPACE}/install/setup.bash" ]; then
    source "${WORKSPACE}/install/setup.bash"
fi

exec "$@"
