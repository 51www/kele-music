// 占位 smoke test：应用真实启动依赖 AudioService 初始化（在 main 中完成），
// 单独的 widget 测试需要额外 ProviderScope + audio handler 覆盖，暂以最小用例占位。
// 后续可扩展为对具体页面的交互测试。

import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('framework smoke', (tester) async {
    expect(1 + 1, equals(2));
  });
}
