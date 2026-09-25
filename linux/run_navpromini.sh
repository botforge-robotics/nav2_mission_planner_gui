#!/usr/bin/env bash
# Launcher script for NavPro Mini Linux Application
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

if [ -x "${PROJECT_ROOT}/build/linux/x64/release/bundle/navpromini" ]; then
  exec "${PROJECT_ROOT}/build/linux/x64/release/bundle/navpromini" "$@"
elif [ -x "${PROJECT_ROOT}/build/linux/x64/debug/bundle/navpromini" ]; then
  exec "${PROJECT_ROOT}/build/linux/x64/debug/bundle/navpromini" "$@"
else
  # Try launching via flutter run if not built yet
  cd "${PROJECT_ROOT}" && exec flutter run -d linux "$@"
fi
