# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Nav2 Mission Planner is a Flutter app (mobile + web) that connects directly to a ROS2 robot's
**rosbridge** websocket server (default port `9090`) to drive teleop, mapping, navigation, and
scripted multi-waypoint "missions" (goals, service calls, action calls, image capture) against a
Nav2-based robot stack. It ships alongside a small Node/Express **PC API** (`server/`) used only in
the web/Docker deployment for robot discovery, claim/heartbeat, and persisted settings — the Flutter
app talks to rosbridge directly for all robot control; the PC API never touches ROS itself.

This build is customized/locked for a specific robot product line ("NavProMini") — see
`lib/constants/default_settings.dart` and the `DEFAULT_SETTINGS`/lock logic in `server/src/index.js`
for the topic names, launch files, and frames that are treated as fixed contract rather than
user-editable defaults.

## Commands

Flutter app (run from repo root):
```bash
flutter pub get                 # install/refresh deps (needed after touching pubspec.yaml)
flutter analyze                 # lint (flutter_lints via analysis_options.yaml)
dart format .                   # format
flutter run                     # run on a connected device/emulator
flutter build web --release --no-tree-shake-icons --no-wasm-dry-run   # production web build (see docker-compose)
flutter build apk               # Android build
```
There is no top-level `test/` directory for the app itself. The only Dart tests live under the
vendored `lib/plugins/ros2_api/test/` package (websocket pub/sub/service/action client tests):
```bash
cd lib/plugins/ros2_api && dart test
```

PC API server (`server/`, Node ESM + Express + better-sqlite3):
```bash
cd server
npm install
npm start                       # node src/index.js, PORT from API_PORT (default 3001)
npm run dev                     # same, with --watch
```

Full stack via Docker (prebuilt Flutter web served by nginx + the API on host networking):
```bash
flutter build web --release --no-tree-shake-icons --no-wasm-dry-run
docker compose up --build -d
# web on http://localhost:8080 (nginx proxies /api -> the api service on :3001)
```
Rosbridge itself runs **on the robot**, not in this Docker stack.

## Architecture

### Two runtimes, two responsibilities
- **Flutter app (`lib/`)** owns all ROS interaction: connecting to rosbridge, subscribing to
  topics, calling services/actions, running missions, teleop control, live map/lidar/camera
  rendering.
- **PC API (`server/src/index.js`)** is a stateless-ish helper the web build talks to over
  `/api/*` (same-origin behind nginx in Docker; `PC_API_BASE` env / `http://127.0.0.1:3001` for
  local `flutter run`, see `lib/services/pc_api_service.dart`). It:
  - LAN-scans for reachable rosbridge hosts (`/api/nearby`) and lets the UI "claim" one
    (`/api/claim`), then polls it (`/api/heartbeat`, 3s from `ConnectionProvider`).
  - Stores/returns app settings and arbitrary key/value blobs in SQLite (`/api/settings`,
    `/api/data/:key`), re-applying the NavProMini "locked" fields on every PUT so a client can't
    drift the robot's core transport config.
  - Has no knowledge of ROS message types; it only does TCP port probing (`net.Socket`) to check
    if rosbridge is alive.

### ROS2 connectivity (`lib/plugins/ros2_api` + generated message packages)
`lib/plugins/ros2_api` is the rosbridge client: `Ros2` (websocket lifecycle in
`ros2_websocket.dart`), plus `Topic`, `Service`, and `ActionClient` wrappers
(`topic.dart`/`service.dart`/`action.dart`) implementing the rosbridge JSON protocol (`op:
subscribe/publish/call_service/send_action_goal/...`).

Everything else under `lib/plugins/*_msgs`, `lib/plugins/*_interfaces` (e.g. `nav2_msgs`,
`geometry_msgs`, `nav_msgs`, `sensor_msgs`, `rosapi_msgs`, `nav2_mission_planner_interfaces`) is
**generated/vendored ROS message & service/action bindings**, each its own local Dart package
referenced by path in `pubspec.yaml`. Treat these as generated code: mirror the existing
`msg`/`srv`/`action` file layout if a new interface package is ever added, don't hand-restructure
them.

### State management
Provider (`ChangeNotifier`) wired up in `lib/main.dart`:
- `ConnectionProvider` — rosbridge connection lifecycle, robot profile list (persisted via
  `shared_preferences`), heartbeat polling through `PcApiService`.
- `SettingsProvider` — per-robot settings (topics, frames, launch files, velocities, bookmarks,
  missions), keyed by `robotId` = `activeRobot.settingsId`; re-created/updated automatically when
  the active robot changes (`ChangeNotifierProxyProvider` in `main.dart`).
- `ROS2DataProvider` — depends on both of the above; exposes live topic/service/action data to
  screens.
- `BrandingProvider` — runtime theming/branding.
- `MissionExecutionService` / `LaunchManager` — mission playback and remote launch-file
  orchestration (via `nav2_mission_planner_interfaces` launch service/actions) respectively.

### Screens & widgets
Top-level modes live in `lib/screens/` (`connection_screen`, `home_screen`, `teleop_screen`,
`mapping_screen`, `navigation_screen`, `mission_screen` referenced from `screens.dart`,
`settings/`). `lib/constants/modes.dart` defines the `AppModes` enum driving the mode switcher.
Settings screens (`lib/screens/settings/`) are split by domain (general/teleop/mapping/navigation)
each composed from shared `widgets/setting_card.dart` / `setting_header.dart` primitives.
`lib/widgets/waypoint_panel/` holds the mission/waypoint editor (service/action/publish forms,
pattern dialogs) used by the mission and navigation screens to build a `Mission`
(`lib/modals/mission.dart`) made of ordered `MissionItem`s (goal, service call, action call, wait,
image capture, etc.).

### Settings contract
`lib/constants/default_settings.dart` (`DefaultSettings`) and `server/src/index.js`
(`DEFAULT_SETTINGS`) both encode the same NavProMini defaults (topic names, frames, launch files)
and must be kept in sync when either changes — the server additionally *enforces* several of these
fields as non-overridable on every `PUT /api/settings` (see the `locked` object in that handler).

## Style notes from `.cursor/rules/`
- Keep the existing `lib/` folder split (constants / providers / screens / widgets / theme /
  services / modals) — don't collapse or relocate these categories.
- Settings screens stay under `lib/screens/settings/` with their `widgets/` subfolder for
  settings-specific components; don't scatter settings widgets into the general `lib/widgets/`
  tree.
