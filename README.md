# Nav2 Mission Planner (React)

Single-robot **NavProMini** web console. Opens on the home screen, discovers nearby rosbridge robots, and **claims** one. Launch files / topics / frames are locked to NavProMini defaults. Claim + settings/missions/bookmarks are stored in **SQLite** (API service).

## Architecture

- **PC Docker:** React UI (`:8080`) + API (`:3001`, SQLite)
- **Robot:** Botforge rosbridge `:9090` + `nav2_mission_planner` packages
- Heartbeat every ~3s against the claimed robot

## Quick start

```bash
cp .env.example .env
docker compose up --build -d
```

Open [http://localhost:8080](http://localhost:8080) → **Scan nearby** or enter IP → **Claim**.

Optional: set `SCAN_CIDR=192.168.1.0/24` in `.env` if auto-detect misses your LAN.

### Local dev

```bash
# terminal 1 — API + SQLite
cd server && npm install && DB_PATH=./data/app.db npm start

# terminal 2 — Vite (proxies /api → :3001)
npm install && npm run dev
```

## Robot

```bash
cd ~/NavProMini_ws
sudo apt remove ros-jazzy-rosbridge* ros-jazzy-rosapi* || true
colcon build && source install/setup.bash
export ROS_LOCALHOST_ONLY=0
ros2 launch nav2_mission_planner nav2_mission_planner.launch.py
```

Locked app defaults: `/cmd_vel_teleop`, `geometry_msgs/Twist`, `navpromini_mission_planner/mapping_launch` + `navigation_launch`, maps `navpromini_mapping/maps`.

## License

MIT — see [LICENSE](LICENSE).
