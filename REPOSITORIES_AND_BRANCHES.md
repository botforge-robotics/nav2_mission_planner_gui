# NavPro Ecosystem Repositories, Branches & Release Engineering Guide

This document is the master operational reference for AI agents, developers, and maintainers working across the NavPro robotics ecosystem. It covers:
1. **The 4-Tier Branch Architecture Matrix** across all repositories.
2. **Current Live Deployment State** on the local PC and physical robot AMR (`192.168.0.128`).
3. **Repository Directory & Roles**.
4. **Step-by-Step Release & Update Guide** (version bumping, multi-platform builds, GitHub releases, robot OTA deployment).
5. **Future RMF Resumption Runbook**.

---

## 1. The 4-Tier Branch Architecture Matrix

Every repository in the NavPro ecosystem adheres to a standardized 4-tier branch strategy:
- **Tier 1: Public Stable**: Production-grade, tagged release branch for public users and field AMRs.
- **Tier 2: Dev Branch**: Daily development and integration branch for core standalone AMR features.
- **Tier 3: RMF Dev Branch**: Active Open-RMF multi-robot fleet orchestration and traffic editor features.
- **Tier 4: RMF Stable Branch**: Validated, production-grade Open-RMF deployment branch (*`-` indicates to be created when RMF multi-robot field testing is ready*).

| Repository & Role | 1. Public Stable Branch | 2. Dev Branch | 3. RMF Dev Branch | 4. RMF Stable Branch |
| :--- | :--- | :--- | :--- | :--- |
| **`nav2_mission_planner`**<br>*(Flutter Desktop/Mobile GUI)* | **`navpro-mini`** (`38db32f`)<br>*(Active on PC)* | **`dev`** (`38db32f`) | **`rmf-dev`** (`029833e`) | `-` *(will create later)* |
| **`Nav_Pro_Mini`**<br>*(ROS 2 Nav2, Autonomy, Docking)* | **`nav2`** (`01ac61e`)<br>*(Active on PC & Robot)* | **`dev`** (`01ac61e`) | **`rmf-dev`** (`9ec588a`) | `-` *(will create later)* |
| **`navpro-fleet-server`**<br>*(Fleet Backend, Web, Zenoh)* | **`main`** (`109f84b`)<br>*(Active on PC)* | **`dev`** (`109f84b`) | **`rmf-dev`** (`a1be305`) | **`rmf-jazzy`** (`c72dc7a`) |
| **`navpromini_robot_ui`**<br>*(On-Robot Touchscreen Display)* | **`main`** (`fc0e7fb`)<br>*(Active on PC & Robot)* | **`dev`** (`1c5fefe`) | `-` *(will create later)* | `-` *(will create later)* |
| **`navpromini_sdk`**<br>*(Python REST API & Telemetry)* | **`main`** (`1a7df5b`)<br>*(Active on PC & Robot)* | **`dev`** (`1a7df5b`) | `-` *(will create later)* | `-` *(will create later)* |
| **`navpromini_wearos`**<br>*(Smartwatch Wear OS App)* | **`master`** (`80f2262`) | `-` *(will create later)* | `-` *(will create later)* | `-` *(will create later)* |
| **`navpromini_sdk_badge`**<br>*(ESP32-S3 AMOLED Touch Badge)* | **`main`** (`e2cde8c`) | `-` *(will create later)* | `-` *(will create later)* | `-` *(will create later)* |
| **`NavProMiniFimware`**<br>*(MCU Motor Controller Firmware)* | **`main`** (`761584c`) | `-` *(will create later)* | `-` *(will create later)* | `-` *(will create later)* |

> **Special Purpose Branch (Isolated):**
> - **`jazzy`** in `nav2_mission_planner`: Locked to commit `caaa44e` for upstream general ROS 2 Jazzy GUI users, intentionally isolated from the NavPro Mini robot line.

---

## 2. Current Live Deployment State

### A. Local PC (`/home/chaitu/Projects/`)
All local checkouts are on their **Public Stable** releases:
- `nav2_mission_planner`: **`navpro-mini`** (`38db32f`)
- `Nav_Pro_Mini`: **`nav2`** (`01ac61e`)
- `navpro-fleet-server`: **`main`** (`109f84b`)
- `navpromini_robot_ui`: **`main`** (`fc0e7fb`)
- `navpromini_sdk`: **`main`** (`1a7df5b`)

### B. Robot AMR (`navpromini@192.168.0.128`)
The physical AMR is running matching **Public Stable** releases:
- `/home/navpromini/NavProMini_ws/src` (`Nav_Pro_Mini`): **`nav2`** (`e93988f`)
- `/home/navpromini/navpromini_robot_ui`: **`main`** (`fc0e7fb`)
- `/home/navpromini/navpromini_sdk`: **`main`** (`1a7df5b`)

---

## 3. Detailed Repository & Branch Directory

### 1. `nav2_mission_planner`
- **Path:** `/home/chaitu/Projects/nav2_mission_planner`
- **Remote:** `git@github.com:botforge-robotics/nav2_mission_planner_gui.git`
- **Tech Stack:** Flutter 3.x, Dart, Linux/Windows/Android Desktop & Mobile.
- **Branches:**
  - `navpro-mini`: Public stable release branch for standalone robots (gamepad teleop with LT/RT triggers, responsive cockpit split view, compact app bars).
  - `dev`: Active standalone development (reset to `navpro-mini` baseline `ae25cc4`).
  - `rmf-dev`: Open-RMF traffic editor, building graph synchronization, dual-mode fleet management, and 401 token auto-refresh.
  - `jazzy`: General ROS 2 Jazzy GUI branch locked to `caaa44e`.

### 2. `Nav_Pro_Mini`
- **Path:** `/home/chaitu/Projects/Nav_Pro_Mini`
- **Remote:** `git@github.com:botforge-robotics/Nav_Pro_Mini.git`
- **Tech Stack:** ROS 2 Jazzy, Nav2, Python/C++, colcon.
- **Branches:**
  - `nav2`: Primary stable autonomy branch at `e93988f` (RPP wrapped with `RotationShimController`, in-place rotate to goal yaw, visual servoing docking).
  - `dev`: Daily development branch aligned with `e93988f`.
  - `rmf-dev`: Dock standoff persistence, multi-robot costmaps.

### 3. `navpro-fleet-server`
- **Path:** `/home/chaitu/Projects/navpro-fleet-server`
- **Remotes:** `chaitanya-mandala/navpro-fleet-server.git` (`origin`), `botforge-robotics/navpro-fleet-server.git` (`botforge`).
- **Tech Stack:** Docker Compose, Express/TypeScript (`platform-api`), React/Vite (`web-gui`), PostgreSQL, Redis, Zenoh, Open-RMF core.
- **Branches:**
  - `main`: Stable fleet ops server release (`109f84b`).
  - `rmf-jazzy`: Merged Open-RMF stack (`c72dc7a`).
  - `rmf-dev`: Dynamic `building.yaml` generation and traffic editor reload hooks.
  - `dev`: Staging branch for fleet ops and teleop bridge.

### 4. `navpromini_robot_ui`
- **Path:** `/home/chaitu/Projects/navpromini_robot_ui`
- **Remote:** `git@github.com:botforge-robotics/navpromini_robot_ui.git`
- **Tech Stack:** Electron, Node.js, Web frontend.
- **Branches:** `main` (Stable release), `dev` (Active staging).

### 5. `navpromini_sdk`
- **Path:** `/home/chaitu/Projects/navpromini_sdk`
- **Remote:** `git@github.com:botforge-robotics/navpromini_sdk.git`
- **Tech Stack:** Python 3.10+, FastAPI/aiohttp, MkDocs.
- **Branches:** `main` (Stable release), `dev` (Dev), `gh-pages` (Docs).

### 6. `navpromini_wearos`
- **Path:** `/home/chaitu/Projects/navpromini_wearos`
- **Role:** Android Wear OS smartwatch companion app for wrist-based robot status, teleop, and dispatching missions.
- **Branch:** `master` (`80f2262`)
- **Deploy to Watch:**
  ```bash
  cd /home/chaitu/Projects/navpromini_wearos
  ./install_to_watch.sh <WATCH_IP> <ADB_PORT>
  ```

### 7. `navpromini_sdk_badge`
- **Path:** `/home/chaitu/Projects/navpromini_sdk_badge`
- **Target Hardware:** Waveshare ESP32-S3-Touch-AMOLED-1.75 (466×466 capacitive touch display, 16MB Flash, OPI PSRAM).
- **Tech Stack:** PlatformIO, Arduino framework, ESP32-S3, LVGL graphics, ArduinoJson.
- **Role:** Ultra-compact handheld wireless teleop badge. Connects directly to the robot's SDK HTTP server on port `8090` over Wi-Fi. Features curved cylindrical arc wheel scrolling for saved locations, one-tap goal dispatch, live teleop driving, and docking control.
- **Branch:** `main` (`e2cde8c`) — Production release.
- **Build & Flash Commands:**
  ```bash
  cd /home/chaitu/Projects/navpromini_sdk_badge
  pio run                  # Compile firmware
  pio run --target upload  # Flash to connected ESP32-S3 over USB CDC
  pio device monitor       # Open serial debug console (115200 baud)
  ```

### 8. `NavProMiniFimware`
- **Path:** `/home/chaitu/Projects/NavProMiniFimware`
- **Role:** Low-level motor controller firmware and micro-ROS agent connection over serial/USB for the onboard MCU.
- **Branch:** `main` (`761584c`)
- **Build Tool:** VS Code PlatformIO.

---

## 4. Release Engineering & Update Handout Guide

Future AI agents and developers must follow this strict workflow when creating and deploying releases.

### A. Semantic Versioning Standard
NavPro releases follow standard SemVer: `vMAJOR.MINOR.PATCH+BUILD`
- **MAJOR (`v2.x`)**: Architectural redesigns or breaking changes.
- **MINOR (`v2.2.0`)**: Significant new features (e.g., new teleop capabilities, docking improvements).
- **PATCH (`v2.1.4`)**: Bug fixes, parameter tuning, calibration adjustments.

---

### B. Releasing the Mission Planner GUI (`nav2_mission_planner`)

#### Step 1: Bump Version Numbers
Update the version string in `pubspec.yaml`:
```yaml
# Example: bump from 2.1.3+7 to 2.1.4+8
version: 2.1.4+8
```
Also update Android configuration in `android/app/build.gradle` if build numbers are managed explicitly.

#### Step 2: Validate Code Cleanliness
```bash
cd /home/chaitu/Projects/nav2_mission_planner
flutter clean
flutter pub get
flutter analyze --no-pub
flutter test
```
*Never create a release if `flutter analyze` reports any errors or warnings.*

#### Step 3: Commit and Merge to Stable Branch
```bash
# Work on dev
git checkout dev
git add pubspec.yaml pubspec.lock
git commit -m "chore(release): bump version to 2.1.4+8"

# Merge cleanly into public stable branch
git checkout navpro-mini
git merge dev --ff-only   # or standard merge
git push origin navpro-mini
```

#### Step 4: Tag the Release
Tag the commit using the annotated format:
```bash
git tag -a v2.1.4 -m "Release v2.1.4: [Brief summary of highlights]"
git push origin v2.1.4
```

#### Step 5: Trigger CI/CD Multi-Platform Builds
The repository includes automated GitHub Actions at `.github/workflows/release.yml`. Pushing a tag matching `v*` automatically triggers parallel builds for:
- **Android**: `NavProMini-Android.apk`
- **Linux**: `NavProMini-Linux-x86_64.tar.gz`
- **Windows**: `NavProMini-Windows-x64.zip`

The workflow automatically creates a GitHub Release draft and attaches these artifacts.

#### Step 6: Local Manual Release Builds (Fallback)
If manual builds are needed without GitHub Actions:
```bash
# Build Linux Desktop Bundle
flutter build linux --release
tar -czvf NavProMini-Linux-x86_64.tar.gz -C build/linux/x64/release/bundle .

# Build Android APK
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk NavProMini-Android.apk
```

---

### C. Releasing Robot Autonomy Software (`Nav_Pro_Mini`)

#### Step 1: Commit and Merge on `Nav_Pro_Mini`
```bash
cd /home/chaitu/Projects/Nav_Pro_Mini
git checkout dev
# Once verified, merge to stable branch
git checkout nav2
git merge dev
git push origin nav2
```

#### Step 2: Tag the Robot Release
```bash
git tag -a v2.1.4 -m "v2.1.4: [Description of navigation/docking updates]"
git push origin v2.1.4
```

#### Step 3: Deploy to Physical AMR via SSH
```bash
# 1. SSH into the robot
ssh navpromini@192.168.0.128

# 2. Pull stable release code
cd /home/navpromini/NavProMini_ws/src
git fetch origin
git checkout nav2
git pull origin nav2

# 3. Build workspace using colcon
cd /home/navpromini/NavProMini_ws
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release
source install/setup.bash

# 4. Restart affected background services
sudo systemctl restart navpromini-navigation.service
sudo systemctl restart navpromini-docking.service
```

#### Step 4: Verify Robot Health Post-Deploy
```bash
# Check running ROS 2 nodes
ros2 node list

# Check Nav2 lifecycle manager
ros2 lifecycle get /lifecycle_manager_navigation

# Check battery & motor telemetry
ros2 topic echo /battery_state --once
```

---

### D. Releasing Robot Touchscreen UI (`navpromini_robot_ui`)

```bash
# 1. Push to main on local PC
cd /home/chaitu/Projects/navpromini_robot_ui
git checkout main
git merge dev
git push origin main

# 2. Deploy to Robot
ssh navpromini@192.168.0.128 '
cd /home/navpromini/navpromini_robot_ui
git pull origin main
npm install --production
sudo systemctl restart navpromini-robot-ui.service
'
```

---

### E. Releasing Robot Python SDK (`navpromini_sdk`)

```bash
# 1. Push to main on local PC
cd /home/chaitu/Projects/navpromini_sdk
git checkout main
git merge dev
git push origin main

# 2. Deploy to Robot
ssh navpromini@192.168.0.128 '
cd /home/navpromini/navpromini_sdk
git pull origin main
sudo systemctl restart navpromini-sdk.service
'
```

---

## 5. Resuming Open-RMF Development Runbook

When the user requests to resume Open-RMF development:

### 1. Switch Repositories to `rmf-dev`
```bash
# Mission Planner GUI
cd /home/chaitu/Projects/nav2_mission_planner
git checkout rmf-dev

# Robot ROS 2 packages
cd /home/chaitu/Projects/Nav_Pro_Mini
git checkout rmf-dev

# Fleet Server
cd /home/chaitu/Projects/navpro-fleet-server
git checkout rmf-dev   # or rmf-jazzy
```

### 2. Update Robot AMR
```bash
ssh navpromini@192.168.0.128 '
cd /home/navpromini/NavProMini_ws/src
git checkout rmf-dev
cd /home/navpromini/NavProMini_ws
colcon build --symlink-install
'
```

### 3. Start the Fleet Stack
```bash
cd /home/chaitu/Projects/navpro-fleet-server
docker compose -f docker-compose.prod.yml up -d
```
All in-progress Open-RMF code, traffic editor studios, building YAML synchronizers, and direct AMR dispatch fallbacks will immediately resume where they left off.
