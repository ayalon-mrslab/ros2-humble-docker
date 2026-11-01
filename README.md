# ROS 2 Humble Dev Container

Ubuntu 22.04 + ROS 2 Humble (desktop) with a workspace at `/home/ros/ros2_ws`.
Your local workspace (the folder that contains `src/`, configured per developer, see below) is mounted to `/home/ros/ros2_ws`, so you edit code on the host and build/run inside the container.
The container's `build/`, `install/` and `log/` are Docker volumes (`ros2_humble_<workspace folder name>_*`): separate from the host's, so host and container builds never mix, and kept when the container is recreated.
ROS (and the workspace overlay, once built) is sourced automatically in every shell.

## One-time host setup

```bash
# Run docker without sudo (reboot afterwards for the change to take effect;
# logging out and back in is often not enough)
sudo usermod -aG docker $USER

# GPU passthrough: install NVIDIA Container Toolkit
# https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# Verify GPU access from a container
docker run --rm --gpus all ubuntu:22.04 nvidia-smi
```

> Without the NVIDIA toolkit, use `--no-gpu` (see below).

## Usage

```bash
# First run: point to YOUR local workspace (saved to .env, so only needed once)
./docker_run.sh --build --ws ~/my_ros2_ws

# Start the container and open a shell (GPU enabled by default)
./docker_run.sh --build      # after Dockerfile changes
./docker_run.sh              # subsequent runs
./docker_run.sh --no-gpu     # run without NVIDIA GPU
./docker_run.sh --no-deps    # skip the automatic rosdep dependency install

# Open additional shells (repeat in as many terminals as you like): when the container is
# already running, docker_run.sh just opens a shell in it (same as docker exec)
./docker_run.sh
docker exec -it ros2_humble bash

# Inside the container
colcon build --symlink-install
source install/setup.bash   # only needed in the current shell; new shells pick it up automatically

# Stop
docker compose down
```

`docker_run.sh` sets `HOST_UID`/`HOST_GID`, runs `xhost +local:docker`, and adds `docker-compose.gpu.yml` on top of `docker-compose.yml` unless `--no-gpu` is given.
Plain `docker compose up -d` (without the script) starts the container **without** GPU.

On every start, `docker_run.sh` also runs `rosdep install` for the mounted workspace, installing any missing system dependencies declared in the `package.xml` files. It is quick when nothing is missing. Installed packages persist until the container is recreated (`--build`, a `--ws` change, or switching GPU mode), and are then reinstalled automatically.
If you add a dependency while the container is running, install it with:
`rosdep install --from-paths src --ignore-src -r -y`

## Choosing the mounted folder

Each developer's workspace is stored as `ROS_WS` in a local `.env` file (gitignored; see `.env.example`).

- `./docker_run.sh --ws PATH` checks that the folder exists, saves its absolute path to `.env` and uses it from then on. Run it again with a different path to switch.
- If you pass a workspace's `src/` (or use the old `--src`), its parent is used. An old `.env` with `ROS_WS_SRC` still works.
- Every start prints the mounted path, and warns if the folder has no `src/`.
- Plain `docker compose` refuses to start if `ROS_WS` is not set, so a wrong or empty folder is never mounted silently.

## Layout

| Host | Container |
|---|---|
| `$ROS_WS` (from `.env`) | `/home/ros/ros2_ws` |
| volumes `ros2_humble_<name>_build`, `_install`, `_log` | `/home/ros/ros2_ws/build`, `install`, `log` |

The host's own `build/`, `install/` and `log/` (if you also build there) are hidden inside the container, not touched. The volumes survive `docker compose down` and recreating the container; remove them with `docker volume rm ros2_humble_<name>_build ros2_humble_<name>_install ros2_humble_<name>_log` for a clean build.

## Quick checks

```bash
ros2 run demo_nodes_cpp talker   # ROS works
rviz2                            # GUI works
nvidia-smi                       # GPU works
```
