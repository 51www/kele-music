@echo off
REM 离线 Mock 开发模式：--dart-define=USE_MOCK=true。
REM 注意 bool.fromEnvironment 只认字面 "true"（传 1 无效）！
REM 所有请求（含 QR 登录、短信登录、签到）由本地 Mock 拦截器返回，不出网、零风控风险。
REM 用途：日常 UI / 业务开发调试。联调真实数据与音源时请用 run_web.bat。
echo [run_web_mock] USE_MOCK=true offline mock mode, starting Chrome...
flutter run -d chrome --dart-define=FLUTTER_WEB_CANVASKIT_URL=/canvaskit/ --dart-define=USE_MOCK=true
