// 备份服务：导出（白名单收集 → 可选加密 → JSON）与导入（选文件 → 解析/解密 →
// 确认 → 原子写回）。导入先在内存完成全部解析校验，任何一步失败都不动本地数据。
//
// 迁移范围 = LocalStore 白名单 10 个 key（设置偏好 + 搜索/播放历史 + 断点快照 +
// 收听统计 + API 地址）+ 网易云登录 cookie（secure storage，迁移后免登录）。
// 收藏/歌单已云端化（/like、/playlist/subscribe），不参与迁移。

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../constants.dart';
import '../local_store.dart';
import 'backup_crypto.dart';

/// 重导出加解密类型：UI 只需 import 本文件即可捕获 BackupCryptoException。
export 'backup_crypto.dart' show BackupCryptoException, EncryptedPayload;

/// 备份文件 magic 标识：用于快速识别文件归属。
const String kBackupMagic = 'kele-music-backup';

/// 备份格式版本：未来字段变更时递增，导入端按版本判断兼容性。
const int kBackupFormatVersion = 1;

/// 参与迁移的 LocalStore key 白名单（引用 constants.dart 常量，禁止硬编码字符串）。
const List<String> kBackupKeys = [
  kStyleIndexKey,
  kPlayQualityKey,
  kDownloadQualityKey,
  kNowPlayingVisualKey,
  kPlayModeKey,
  kSearchHistoryKey,
  kHistoryKey,
  kQueueSnapshotKey,
  kListenStatsKey,
  kApiBaseUrlKey,
];

/// 备份文件名：kele-music-backup-20261102-1530.json
String backupFileName([DateTime? at]) {
  final t = at ?? DateTime.now();
  String p2(int v) => v.toString().padLeft(2, '0');
  return 'kele-music-backup-'
      '${t.year}${p2(t.month)}${p2(t.day)}-${p2(t.hour)}${p2(t.minute)}.json';
}

/// 备份格式错误（文件损坏 / 不是本应用备份 / 版本过新）。
class BackupFormatException implements Exception {
  final String message;
  const BackupFormatException(this.message);
  @override
  String toString() => message;
}

/// 加密备份但未提供密码：UI 捕获后弹出密码输入，再带密码重试。
class BackupNeedsPasswordException implements Exception {
  const BackupNeedsPasswordException();
}

/// 解析并确认后待写回的数据。
class BackupData {
  /// 白名单内的键值（仅含文件中实际存在且类型合法的项）。
  final Map<String, dynamic> keys;

  /// 登录 cookie；文件缺失/为空时为 null（保持本机现状）。
  final String? cookie;

  const BackupData({required this.keys, this.cookie});

  /// 白名单内「文件中存在、将被覆盖」的 key 列表（用于确认框展示）。
  List<String> overwrittenKeys() => keys.keys.toList();
}

/// 生成备份文件 JSON 文本（顶层结构见 README）。
/// [password] 非空时对 payload 做 PBKDF2+AES 加密，否则明文。
Future<String> buildBackupJson({String? password}) async {
  final cookie = await const FlutterSecureStorage().read(key: kCookieKey);
  final payload = <String, dynamic>{
    'keys': LocalStore.instance.exportValues(kBackupKeys),
    'ncm_cookie': cookie,
  };

  Object encodedPayload;
  var encrypted = false;
  if (password != null && password.isNotEmpty) {
    final plain = jsonEncode(payload);
    encodedPayload = encryptBackupJson(plain, password).toJson();
    encrypted = true;
  } else {
    encodedPayload = payload;
  }

  String appVersion = '';
  try {
    final info = await PackageInfo.fromPlatform();
    appVersion = '${info.version}+${info.buildNumber}';
  } catch (_) {
    // 版本号取不到不影响备份内容。
  }

  return jsonEncode(<String, dynamic>{
    'magic': kBackupMagic,
    'formatVersion': kBackupFormatVersion,
    'createdAt': DateTime.now().toIso8601String(),
    'appVersion': appVersion,
    'encrypted': encrypted,
    'payload': encodedPayload,
  });
}

/// 弹系统文件选择器读取备份文件内容；用户取消返回 null。
Future<String?> pickBackupRawJson() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['json'],
    withData: true, // 全平台统一读 bytes，避免 dart:io 依赖
  );
  final file = result?.files.single;
  final bytes = file?.bytes;
  if (bytes != null) return utf8.decode(bytes, allowMalformed: true);
  return null;
}

/// 解析备份 JSON → [BackupData]。
///
/// - 加密文件需传入 [password]，缺失时抛 [BackupNeedsPasswordException]；
/// - 密码错误 / 密文损坏抛 [BackupCryptoException]；
/// - 其他失败抛 [BackupFormatException]，message 可直接展示给用户。
Future<BackupData> parseBackupJson(String raw, {String? password}) async {
  dynamic root;
  try {
    root = jsonDecode(raw);
  } catch (_) {
    throw const BackupFormatException('文件不是有效的 JSON');
  }
  if (root is! Map || root['magic'] != kBackupMagic) {
    throw const BackupFormatException('这不是「可乐音乐」导出的备份文件');
  }
  final version = root['formatVersion'];
  if (version is! int || version > kBackupFormatVersion) {
    throw const BackupFormatException('备份文件版本过新，请先把 App 升级到最新版本');
  }

  dynamic payload = root['payload'];
  if (root['encrypted'] == true) {
    if (password == null || password.isEmpty) {
      throw const BackupNeedsPasswordException();
    }
    if (payload is! Map) {
      throw const BackupFormatException('备份文件已损坏（缺少加密数据）');
    }
    EncryptedPayload ep;
    try {
      ep = EncryptedPayload.fromJson(Map<String, dynamic>.from(payload));
    } on BackupCryptoException {
      throw const BackupFormatException('备份文件已损坏（加密数据不完整）');
    }
    try {
      payload = jsonDecode(decryptBackupJson(ep, password));
    } on BackupCryptoException {
      rethrow; // 「密码错误或文件已损坏」
    } catch (_) {
      throw const BackupFormatException('备份文件已损坏（解密后内容无效）');
    }
  }

  if (payload is! Map) {
    throw const BackupFormatException('备份文件已损坏（数据主体缺失）');
  }
  final keysRaw = payload['keys'];
  if (keysRaw is! Map) {
    throw const BackupFormatException('备份文件已损坏（缺少数据项）');
  }

  // 只接受白名单内的键 + 类型合法的值；未知键忽略（前向兼容），null 值跳过
  // （导入语义是「只覆盖文件里有的项」）。
  final accepted = <String, dynamic>{};
  for (final entry in keysRaw.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key is String && kBackupKeys.contains(key) && _isStorable(value)) {
      accepted[key] = value;
    }
  }

  final cookie = payload['ncm_cookie'];
  return BackupData(
    keys: accepted,
    cookie: (cookie is String && cookie.isNotEmpty) ? cookie : null,
  );
}

bool _isStorable(Object? v) =>
    v is String || v is int || v is bool || (v is List && v.every((e) => e is String));

/// 确认后写回：LocalStore 一次性覆盖落盘，再写 cookie（secure storage）。
/// 到这一步前 parseBackupJson 应已成功，理论上不会失败。
Future<void> applyBackup(BackupData data) async {
  LocalStore.instance.importValues(data.keys);
  if (data.cookie != null) {
    await const FlutterSecureStorage().write(key: kCookieKey, value: data.cookie);
  }
}
