@echo off
REM 启动 Web 端。
REM 关键：FLUTTER_WEB_CANVASKIT_URL 指向 web/canvaskit/（已自托管），
REM 避免默认从 www.gstatic.com 下载 canvaskit（国内被墙 -> ERR_CONNECTION_CLOSED -> 启动失败）。
echo [run_web] 使用本地自托管 canvaskit 启动 Chrome...
flutter run -d chrome --dart-define=FLUTTER_WEB_CANVASKIT_URL=/canvaskit/
