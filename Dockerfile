# MRS lab ROS 2 Humble base image: published by CI to ghcr.io/<owner>/ros2-humble-base.
# Holds what most lab projects share; robot-specific packages belong in each project's
# .devcontainer/Dockerfile (see templates/). Gazebo is not included: projects use different
# versions (Go2: Fortress, Crazyflie: Harmonic).
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG USERNAME=ros
ARG USER_UID=1000
ARG USER_GID=1000

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    ROS_DISTRO=humble

# Locale + base tools + universe repository
RUN apt-get update && apt-get install -y --no-install-recommends \
        locales \
        software-properties-common \
        curl \
        ca-certificates \
        gnupg \
    && locale-gen en_US en_US.UTF-8 \
    && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
    && add-apt-repository -y universe \
    && rm -rf /var/lib/apt/lists/*

# ROS 2 apt source (official ros2-apt-source package)
RUN set -eux; \
    ROS_APT_SOURCE_VERSION=$(curl -fsSL https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest \
        | grep -F '"tag_name"' | awk -F'"' '{print $4}'); \
    test -n "${ROS_APT_SOURCE_VERSION}"; \
    curl -fsSL -o /tmp/ros2-apt-source.deb \
        "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.$(. /etc/os-release && echo ${UBUNTU_CODENAME:-${VERSION_CODENAME}})_all.deb"; \
    dpkg -i /tmp/ros2-apt-source.deb; \
    rm /tmp/ros2-apt-source.deb

# ROS 2 Humble desktop, lab-wide ROS packages and development tools
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
        ros-humble-desktop \
        ros-dev-tools \
        ros-humble-rmw-cyclonedds-cpp \
        ros-humble-navigation2 \
        ros-humble-nav2-bringup \
        ros-humble-slam-toolbox \
        ros-humble-robot-localization \
        ros-humble-ros2-control \
        ros-humble-ros2-controllers \
        ros-humble-xacro \
        ros-humble-joint-state-publisher-gui \
        ros-humble-tf2-tools \
        ros-humble-rqt-tf-tree \
        python3-pip \
        python3-colcon-common-extensions \
        build-essential \
        git \
        sudo \
        bash-completion \
        nano \
        vim \
        gedit \
    && rm -rf /var/lib/apt/lists/*

RUN rosdep init

# Non-root user. The published image uses UID/GID 1000; on hosts with another UID, Dev
# Containers (updateRemoteUserUID) and docker_run.sh remap it, so files in the mounted
# workspace keep host ownership.
RUN groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USERNAME} \
    && usermod -aG video ${USERNAME} \
    && printf '%s ALL=(ALL) NOPASSWD:ALL\nDefaults env_keep += "DEBIAN_FRONTEND"\n' "${USERNAME}" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

COPY ros_entrypoint.sh /ros_entrypoint.sh
RUN chmod +x /ros_entrypoint.sh

USER ${USERNAME}
ENV WORKSPACE=/home/${USERNAME}/ros2_ws
# build/ install/ log/ are Docker volumes (see docker-compose.yml). Creating the folders
# here, as this user, makes new volumes start out owned by this user, not root.
RUN mkdir -p ${WORKSPACE}/src ${WORKSPACE}/build ${WORKSPACE}/install ${WORKSPACE}/log \
    && rosdep update --rosdistro ${ROS_DISTRO}

# Source ROS + workspace in every interactive shell (covers `docker exec ... bash`)
RUN { \
      echo ''; \
      echo '# ROS 2 environment'; \
      echo 'source /opt/ros/${ROS_DISTRO}/setup.bash'; \
      echo 'if [ -f "${WORKSPACE}/install/setup.bash" ]; then source "${WORKSPACE}/install/setup.bash"; fi'; \
      echo 'source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash'; \
    } >> /home/${USERNAME}/.bashrc

WORKDIR ${WORKSPACE}

ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["bash"]
