// 统一错误类型，UI 层据此展示友好文案。
class ApiException implements Exception {
  final int? code;
  final String message;
  const ApiException(this.code, this.message);

  @override
  String toString() => 'ApiException(${code ?? '-'}): $message';

  String get userMessage {
    if (code == 301) return '需要登录后再操作';
    if (code == 400) return '验证码已失效或有误，请重新获取后再登录';
    if (code == 502) return '服务端异常，请稍后再试';
    if (code == 503) return '操作过于频繁或验证码有误，请稍后再试';
    return message.isNotEmpty ? message : '网络请求失败';
  }
}
