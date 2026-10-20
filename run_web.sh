#!/usr/bin/env bash
# 启动 Web 端（Git Bash 用）。本地自托管 canvaskit，避免 gstatic 被墙。
set -e
echo "[run_web] 使用本地自托管 canvaskit 启动 Chrome..."
flutter run -d chrome --dart-define=FLUTTER_WEB_CANVASKIT_URL=/canvaskit/
