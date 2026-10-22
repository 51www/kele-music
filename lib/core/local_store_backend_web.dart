/// Web 平台后端：localStorage 持久化。
///
/// localStorage 本身是同步读写的，正好匹配 LocalStore 的同步 API；
/// 数据随浏览器持久化（同源策略内），刷新/重开浏览器不丢。
library;

// ignore: deprecated_member_use
import 'dart:html' as html;

const String _kStateKey = 'app_state.json';

Future<String?> readPersistedState() async {
  final raw = html.window.localStorage[_kStateKey];
  return (raw == null || raw.isEmpty) ? null : raw;
}

void writePersistedState(String raw) {
  html.window.localStorage[_kStateKey] = raw;
}
