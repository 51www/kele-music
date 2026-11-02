// 导入备份后使新数据生效：各 Notifier 仅在构造时 load，可靠生效方式是重启。
// - Android/iOS：restart_app 插件重启进程
// - Web：刷新页面
// - 桌面：插件不支持，返回 false，由 UI 提示手动重启

export 'restart_stub.dart'
    if (dart.library.html) 'restart_web.dart'
    if (dart.library.io) 'restart_io.dart';
