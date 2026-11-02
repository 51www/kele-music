// 条件导入兜底桩：Web/IO 条件已覆盖所有平台，此桩不会被选中。

Future<bool> tryRestartApp() => throw UnsupportedError('当前平台不支持自动重启');
