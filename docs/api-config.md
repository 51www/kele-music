# API 接入层配置化方案

> 目标：API 地址、密钥、超时等参数可通过配置文件或环境变量灵活切换；
> 登录依赖该配置，因此配置必须在**应用初始化前（任何请求发出前）**读取完成。

## 配置结构

| 键 | 类型 | 说明 | 默认值 |
|---|---|---|---|
| `baseUrl` | String | API 根地址（不带末尾斜杠，载入时自动归一） | `constants.dart` 的 `kBaseUrl`（当前 `https://music.2000321.xyz`） |
| `apiKey` | String | 网关鉴权预留，非空时自动附加 `X-API-Key` 请求头 | 空（不附加） |
| `connectTimeoutMs` | int | 连接超时（毫秒） | 15000 |
| `receiveTimeoutMs` | int | 接收超时（毫秒） | 20000 |

## 加载时机与优先级

```
main() {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();          // ← 最外层：runApp 之前，任何 API 调用之前
  ...创建 NcmApi / AuthRepository...
  runApp(ProviderScope(...));      // 登录页及所有请求均读取已加载的配置
}
```

优先级（高 → 低），高优先级存在且合法时覆盖低优先级：

1. **运行时配置文件** `assets/config/app_config.json` —— 改文件重新部署即可切换，无需重新编译
2. **编译期环境变量** `--dart-define` —— CI / 多环境打包时注入
3. **内置默认值** `lib/core/constants.dart`

配置文件缺失、损坏或某键缺省时，静默回落到下一级，不阻断启动。

## 用法示例

```bash
# 编译期注入（Web / APK 通用）
flutter build apk --release --dart-define=API_BASE_URL=https://your-api.example.com
flutter build web --dart-define=API_BASE_URL=https://your-api.example.com --dart-define=API_KEY=xxx

# 运行时覆盖：编辑 assets/config/app_config.json 后重新部署构建产物
{ "baseUrl": "https://your-api.example.com", "apiKey": "secret" }
```

发布时 `assets/config/app_config.json` 当前为 `{}`（全部走 dart-define / 默认值）；
完整键位示例见 `assets/config/app_config.example.json`。

## 改动模块清单

| 文件 | 改动 |
|---|---|
| `lib/data/app_config.dart` | **新增**：AppConfig 类，三级优先级合并 + 静态单例 |
| `lib/data/api_client.dart` | `NcmApi` 构造参数缺省改读 `AppConfig.instance`；新增 `X-API-Key` 头支持；超时可配置 |
| `lib/main.dart` | `main()` 在 `runApp` 前 `await AppConfig.load()` |
| `lib/core/constants.dart` | `kBaseUrl` 降级为「内置默认值」（保留，作为最后兜底） |
| `pubspec.yaml` | 声明 `assets/config/app_config.json` 资产 |
| `assets/config/app_config.json` | **新增**：运行时配置（发布为空对象） |
| `assets/config/app_config.example.json` | **新增**：完整键位示例 |

## 注意事项

- `AppConfig.load()` 只应在 `main()` 调用一次；`NcmApi` 构造时读取的是当时的快照
- 换 `baseUrl` 后端时注意新后端需实现相同端点契约（含 GET 缓存穿透 timestamp、301 登录态语义）
- `apiKey` 当前为预留字段，后端网关未启用鉴权时保持为空即可
- **地址归一**：所有来源的地址（配置文件 / `--dart-define` / 用户保存）都会去掉末尾斜杠，
  即 `https://music.2000321.xyz/` → `https://music.2000321.xyz`，避免拼接出 `//path`
- **保存值优先**：用户通过登录页/设置面板保存的 API 地址优先级最高，保存什么就用什么；
  想回到内置默认地址时，点设置页「后端服务 → 恢复默认地址」清除覆盖即可
