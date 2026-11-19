# MRS Lab ROS 2 Humble Base Image

The lab's shared Docker environment for ROS 2 Humble projects. It has three parts:

| Part | What it is | Who uses it |
|---|---|---|
| [`Dockerfile`](Dockerfile) | The **base image**, published to `ghcr.io/ayalon-mrslab/ros2-humble-base` | Every project builds `FROM` it |
| [`templates/devcontainer/`](templates/devcontainer/) | A VS Code Dev Container to copy into a project | Each project, once |
| [`docker_run.sh`](docker_run.sh) | A script that runs any workspace in the base (or a project) image | Machines without VS Code, e.g. a robot's computer |

**One project = one git repo = one ROS workspace = one container.** The project repo holds
`src/` and a `.devcontainer/` folder with the project's own dependencies. Opening the repo
in VS Code starts its container; several projects can run side by side.

## What the base image contains

Ubuntu 22.04 with:

- ROS 2 Humble desktop (RViz, rqt), `ros-dev-tools` (colcon, rosdep, vcstool)
- Nav2, slam_toolbox, robot_localization
- ros2_control + ros2_controllers, xacro, joint_state_publisher_gui
- CycloneDDS (`rmw_cyclonedds_cpp`), tf2 tools, rqt_tf_tree
- Editors: gedit, nano, vim
- A `ros` user with passwordless sudo, and the workspace at `/home/ros/ros2_ws`
- ROS and the workspace overlay (once built) sourced in every shell

**Not included, on purpose:**

- **Gazebo**: projects need different versions (Go2 uses Fortress, Crazyflie uses Harmonic), so each project installs its own.
- **CUDA**: added later if it turns out several projects need it.
- **Robot-specific packages** (Unitree, CHAMP, crazyswarm2, ...): these belong in the project's image.

Rule of thumb: a package goes in the base image only if more than one project uses it and it rarely changes.

## One-time host setup

```bash
# Run docker without sudo (reboot afterwards for the change to take effect;
# logging out and back in is often not enough)
sudo usermod -aG docker $USER

# GPU passthrough (optional): install NVIDIA Container Toolkit
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

For Dev Containers, also install the VS Code extension **Dev Containers** (`ms-vscode-remote.remote-containers`).

## Working on a project (VS Code Dev Container, the default)

If the project already has a `.devcontainer/` folder:

1. Clone the project repo and open its folder in VS Code.
2. Choose **Reopen in Container** (from the pop-up, or `F1` → *Dev Containers: Reopen in Container*).
   The first time, this pulls the base image and builds the project image, which takes a few minutes.
3. In the VS Code terminal (already in `/home/ros/ros2_ws`, with ROS sourced):
   ```bash
   colcon build --symlink-install
   ```

What the Dev Container does for you:

- Mounts the repo at `/home/ros/ros2_ws`, so the right folder is always used, with no path settings.
- Keeps the container's `build/`, `install/` and `log/` in Docker volumes, separate from any host build and kept across rebuilds.
- Remaps the `ros` user to your UID/GID, so files you create keep your ownership.
- Uses the NVIDIA GPU when the host has one, and runs without it otherwise.
- Uses the host network and your display, so ROS discovery and RViz/Gazebo windows work.

**After changing dependencies** (a `package.xml`, or the project's `.devcontainer/Dockerfile`): `F1` → *Dev Containers: Rebuild Container*.
To try a dependency without rebuilding, install it in the running container with `rosdep install --from-paths src --ignore-src -r -y`.
It is lost on the next rebuild unless a `package.xml` or the Dockerfile declares it.

## Adding the Dev Container to a project

The project repo must be the workspace, with `src/` at its root:

```
my_project/              ← the git repo = the ROS workspace
├── .devcontainer/       ← copied from templates/devcontainer/
│   ├── devcontainer.json
│   └── Dockerfile
└── src/
    └── ...
```

1. Copy [`templates/devcontainer/`](templates/devcontainer/) to the project as `.devcontainer/`.
2. In `devcontainer.json`, set `"name"` to the project name.
3. In `.devcontainer/Dockerfile`, add any system packages that no `package.xml` declares, such as a Gazebo version or vendor SDK packages.
   Everything that the workspace's `package.xml` files declare is installed automatically with `rosdep`.
4. Add `build/`, `install/` and `log/` to the project's `.gitignore`.
5. Commit `.devcontainer/`, so everyone on the project gets the same environment.

The project's Dockerfile installs dependencies from the `package.xml` files only, not the whole `src/`.
Editing code therefore never rebuilds the dependency layer; only changing a `package.xml` does.

**Pinning the base version:** the template uses `ros2-humble-base:latest`.
For a project that must not change under you (e.g. before a deadline), set `BASE_IMAGE` in `devcontainer.json` to a release tag such as `:1.0`.

## Running without VS Code (`docker_run.sh`)

For machines without VS Code, or a workspace without a `.devcontainer/`. The script pulls the base image when missing.

```bash
# First run: point to YOUR local workspace (saved to .env, so only needed once)
./docker_run.sh --ws ~/my_ros2_ws

./docker_run.sh              # later runs; opens another shell if it's already running
./docker_run.sh --no-gpu     # run without NVIDIA GPU
./docker_run.sh --no-deps    # skip the automatic rosdep dependency install
./docker_run.sh --pull       # update to the newest published base image
./docker_run.sh --build      # build the base image from this folder (testing Dockerfile changes)
./docker_run.sh --image NAME # run a project image built FROM the base image
./docker_run.sh --name NAME  # container name (default ros2_humble); one per project

# More shells
docker exec -it ros2_humble bash      # or the name given with --name

# Stop (keeps the container: the next docker_run.sh starts it again)
docker stop ros2_humble
# Remove the container (the build volumes stay)
docker compose -p ros2_humble down
```

Notes:

- **Settings:** the workspace, image and name are saved in a local, gitignored `.env` (see `.env.example`), so later runs need no flags.
  Plain `docker compose` refuses to start without `ROS_WS`, so a wrong or empty folder is never mounted silently.
- **Dependencies:** on every start, the script runs `rosdep install` for the mounted workspace, which is quick when nothing is missing.
  Installed packages last until the container is recreated.
- **UID:** if your UID/GID isn't 1000, the script runs a local copy of the image with the user remapped, as Dev Containers do.
- **Build volumes:** the container's `build/`, `install/` and `log/` are volumes named `ros2_humble_<workspace folder>_*`.
  For a clean build, remove them with `docker volume rm`.
- **Isolation:** all containers use the host network, so nodes of two running projects see each other.
  Give each project its own `ROS_DOMAIN_ID` to keep them apart.

## Maintaining the base image

CI ([`.github/workflows/build-base.yml`](.github/workflows/build-base.yml)) builds the image and pushes it to `ghcr.io/<repo owner>/ros2-humble-base`:

| Event | Tags |
|---|---|
| Push to `main` that changes the `Dockerfile`, entrypoint or workflow | `latest`, `sha-<commit>` |
| Git tag `v1.2.3` | `1.2.3`, `1.2`, `1` |
| Manual run (Actions tab → *Build base image* → *Run workflow*) | as for the branch it runs on |

**Changing the base image:**

1. Edit the `Dockerfile` and test it locally with `./docker_run.sh --build`.
2. Push to `main`, and CI publishes `latest`.
3. For a version that projects can pin: `git tag v1.1.0 && git push origin v1.1.0`.

Projects pick up a new base image on their next *Rebuild Container*.

**First publish only:** a new package on ghcr.io is private.
Make it public once, under GitHub → your profile (or the organization) → *Packages* → `ros2-humble-base` → *Package settings* → *Change visibility* → *Public*.
Public packages are free and can be pulled without logging in.

**Moving the repo to the MRSTechnion organization:**

- CI takes the owner from the repo, so after the transfer it publishes `ghcr.io/mrstechnion/ros2-humble-base` with no change to the workflow.
  Run the workflow once by hand and make the new package public, as above.
- Images already published stay under `ayalon-mrslab`; delete them once nothing uses them.
- Then replace `ghcr.io/ayalon-mrslab/` with `ghcr.io/mrstechnion/` in `docker_run.sh`, `docker-compose.yml`, the template, and each project's `.devcontainer/`.

## Quick checks (inside the container)

```bash
ros2 run demo_nodes_cpp talker   # ROS works
rviz2                            # GUI works
nvidia-smi                       # GPU works (when the host has one)
```
