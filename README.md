# Nav2 Mission Planner (Flutter Web + PC API)

## Stack
- **web** — Flutter web UI (nginx `:8080`)
- **api** — Express + SQLite claim / heartbeat / nearby scan (`:3001`, host network)

Rosbridge runs **on the robot** (`:9090`), not in this Docker stack.

## Run
```bash
flutter build web --release --no-tree-shake-icons --no-wasm-dry-run
docker compose up --build -d
```
Open http://localhost:8080

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
