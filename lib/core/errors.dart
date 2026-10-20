// 统一错误类型，UI 层据此展示友好文案。
class ApiException implements Exception {
  final int? code;
  final String message;
  const ApiException(this.code, this.message);

  @override
  String toString() => 'ApiException(${code ?? '-'}): $message';

  String get userMessage {
    if (code == 301) return '需要登录后再操作';
    if (code == 400) return '请求参数有误';
    if (code == 502) return '网易服务端异常，请稍后再试';
    return message.isNotEmpty ? message : '网络请求失败';
  }
}
