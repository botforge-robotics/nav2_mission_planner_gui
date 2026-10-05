#!/usr/bin/env bash
# ==============================================================================
# Start Mock Restaurant Kiosk (Frontend + Backend REST API)
# For NavPro Mini Autonomous Dining / Ordering Robot Demos
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${RESTAURANT_PORT:-5050}"

# Parse optional --port argument
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--port)
      PORT="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

export RESTAURANT_PORT="$PORT"

# Detect local LAN IP
LOCAL_IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1 || echo "127.0.0.1")

echo ""
echo "================================================================="
echo " 🍽️  STARTING BISTROBOT RESTAURANT KIOSK (MOCK BACKEND & FRONTEND)"
echo "================================================================="
echo " • Local URL:        http://localhost:${PORT}"
echo " • LAN Robot URL:    http://${LOCAL_IP}:${PORT}"
echo " • Menu REST API:    http://${LOCAL_IP}:${PORT}/api/menu"
echo " • Orders REST API:  http://${LOCAL_IP}:${PORT}/api/orders"
echo "-----------------------------------------------------------------"
echo " 👉 In Mission Planner 'ui_browser' node, set URL to:"
echo "    http://${LOCAL_IP}:${PORT}"
echo "================================================================="
echo "Press Ctrl+C to stop the server."
echo ""

cd "${SCRIPT_DIR}"
exec python3 server.py
