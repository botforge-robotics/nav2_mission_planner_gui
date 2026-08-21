# Nav2 Mission Planner (Flutter Web + PC API)

## Stack
- **web** — Flutter web UI (nginx `:8080`)
- **api** — Express + SQLite claim / heartbeat / nearby scan (`:3001`, host network)

Rosbridge runs **on the robot** (`:9090`), not in this Docker stack. The `web` UI can only see a
robot if the `api` service is reachable and can reach the robot's `:9090` — if the app keeps
saying "No robots found" even though the robot is on the network, check that `api` is running
first.

## Install (new machine)

Prerequisites:
- **Flutter SDK** (`sdk: ^3.6.1`, see `pubspec.yaml`) — install per
  [flutter.dev/setup](https://docs.flutter.dev/get-started/install) and make sure `flutter/bin`
  is on your `PATH` (`flutter --version` should work in a fresh shell).
- **Docker + Docker Compose**, if you're running the deployed stack (`docker-compose.yml`).
- **Node.js 22** (matches `server/Dockerfile`), only if you want to run the PC API directly
  instead of via Docker — `server/`'s native dependency (`better-sqlite3`) can fail to build from
  source on much newer/older Node majors; if `npm install` fails with a `node-gyp`/`make` error,
  switch to Node 22 (`nvm install 22 && nvm use 22`) and reinstall.

Clone, then fetch Flutter deps once:
```bash
flutter pub get
```

## Run — deployed (Docker, matches production)
```bash
flutter build web --release --no-tree-shake-icons --no-wasm-dry-run
docker compose up --build -d
```
Open http://localhost:8080. This runs `web` (nginx serving the built Flutter app, proxying `/api`)
and `api` together on host networking, which is what lets the PC API scan your LAN for the robot.

## Run — local dev (no Docker)
Run the API and the Flutter dev server side by side, and point Flutter at the API explicitly
(the dev server has no nginx proxy for `/api`):
```bash
# terminal 1 — PC API
cd server && npm install && npm start        # listens on :3001

# terminal 2 — Flutter app
flutter run -d chrome \
  --dart-define=PC_API_BASE=http://localhost:3001
```
Swap `-d chrome` for `-d web-server --web-port=8765 --web-hostname=0.0.0.0` to serve it headlessly
instead of opening a Chrome window.

## Behavior
- Connection screen is the original Flutter UI
- On connect: PC API **claims** the robot and polls **heartbeat** every 3s
- Settings are auto-locked to **NavProMini** launch files and topics

## API
- `GET /api/health`
- `GET|POST|DELETE /api/claim`
- `GET /api/heartbeat`
- `GET /api/probe?ip=&port=`
- `GET /api/nearby?scan=1`
- `GET /api/defaults`
