# Project image: the lab base image + this project's own dependencies.
# Copied from ros2-humble-docker/templates/devcontainer/ - see its README.
ARG BASE_IMAGE=ghcr.io/ayalon-mrslab/ros2-humble-base:latest
FROM ${BASE_IMAGE}
ARG DEBIAN_FRONTEND=noninteractive

# System packages the project needs but no package.xml declares (uncomment and edit)
# RUN sudo apt-get update && sudo apt-get install -y --no-install-recommends \
#         <package> \
#     && sudo rm -rf /var/lib/apt/lists/*

# Everything the workspace's package.xml files declare. Dockerfile.dockerignore limits the
# build context to the manifests, so only changing a package.xml reruns this layer.
COPY --chown=ros:ros src /tmp/manifests
RUN sudo apt-get update \
    && rosdep update --rosdistro ${ROS_DISTRO} \
    && rosdep install --from-paths /tmp/manifests --ignore-src -r -y \
    && sudo rm -rf /var/lib/apt/lists/* /tmp/manifests
