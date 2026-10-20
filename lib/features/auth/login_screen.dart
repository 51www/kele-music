import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants.dart';
import '../../core/styles.dart';
import '../../data/app_config.dart';
import '../../providers.dart';

/// 登录页：玻璃卡片 + 动态光影背景 + 分段式切换 + 发光输入框 + 入场动效。
/// 登录逻辑（验证码 / 二维码轮询）与旧版完全一致，仅重构视觉层。
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  late final TabController _tab;
  final _phone = TextEditingController();
  final _captcha = TextEditingController();
  final _phoneFocus = FocusNode();
  final _captchaFocus = FocusNode();
  bool _sending = false;
  bool _logging = false;
  String? _error;
  String? _qrImg;
  String? _qrKey;
  bool _qrBusy = false;
  bool _qrExpired = false;
  DateTime? _qrExpireAt;

  // 入场动效（分层淡入上滑）+ 背景光影漂移。
  late final AnimationController _entry;
  late final AnimationController _drift;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _entry = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();
    _drift = AnimationController(vsync: this, duration: const Duration(seconds: 12))
      ..repeat(reverse: true);
    _phoneFocus.addListener(_onFocus);
    _captchaFocus.addListener(_onFocus);
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tab.dispose();
    _phone.dispose();
    _captcha.dispose();
    _phoneFocus.dispose();
    _captchaFocus.dispose();
    _entry.dispose();
    _drift.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_phone.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(authRepositoryProvider).sendCaptcha(_phone.text.trim());
    } catch (e) {
      setState(() => _error = e.toString());
    }
    setState(() => _sending = false);
  }

  Future<void> _login() async {
    setState(() => _logging = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .loginCellphone(_phone.text.trim(), _captcha.text.trim());
      await ref.read(authStateProvider.notifier).completeLogin();
      if (mounted) context.go('/');
    } catch (e) {
      setState(() => _error = e.toString());
    }
    setState(() => _logging = false);
  }

  /// 切到二维码页时自动生成：无图或已失效才重新生成，
  /// 有效期内切走再切回不打断进行中的轮询。
  void _ensureQr() {
    if (_qrBusy) return;
    if (_qrImg == null || _qrExpired) _startQr();
  }

  Future<void> _startQr() async {
    if (_qrBusy) return;
    setState(() {
      _qrKey = null; // 置空即停止旧轮询循环
      _qrExpired = false;
      _qrExpireAt = null;
      _qrBusy = true;
      _error = null;
    });
    try {
      final key = await ref.read(authRepositoryProvider).qrKey();
      final img = await ref.read(authRepositoryProvider).qrCreate(key);
      if (img.isEmpty) {
        setState(() => _error = '二维码生成失败，请重试');
        return;
      }
      setState(() {
        _qrKey = key;
        _qrImg = img;
        _qrExpireAt = DateTime.now().add(const Duration(milliseconds: kQrValidityMs));
      });
      _poll();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _qrBusy = false);
    }
  }

  /// 二维码失效：保留旧图供遮罩展示，仅停轮询、标记失效。
  /// 有效期判定 = 本地 3 分钟超时（_poll 每轮检查）∪ 服务端 800，双兜底。
  void _expireQr() {
    if (!mounted) return;
    setState(() {
      _qrKey = null;
      _qrExpired = true;
      _qrExpireAt = null;
    });
  }

  void _poll() {
    Future.doWhile(() async {
      if (!mounted || _qrKey == null) return false;
      if (_qrExpireAt != null && DateTime.now().isAfter(_qrExpireAt!)) {
        _expireQr();
        return false;
      }
      try {
        final st = await ref.read(authRepositoryProvider).qrCheck(_qrKey!);
        if (st == 'confirmed') {
          await ref.read(authStateProvider.notifier).completeLogin();
          if (mounted) context.go('/');
          return false;
        }
        if (st == 'expired') {
          _expireQr();
          return false;
        }
      } catch (_) {
        // 单次轮询失败不终止轮询；本地超时兜底会强制失效。
        await Future.delayed(const Duration(seconds: 3));
        return true;
      }
      await Future.delayed(const Duration(seconds: 2));
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: style.backgroundGradient),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _backgroundGlow(style),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                      24, 24, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
                  child: ConstrainedBox(
                    // 响应式：宽屏限宽居中成卡片，窄屏自然铺满。
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: _glassCard(style),
                  ),
                ),
              ),
            ),
            // 页面左上角：设置入口（API 地址 / 主题）。
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _settingsButton(style),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 背景光影：两团 accent 柔光缓慢漂移，营造纵深而不喧宾夺主。
  Widget _backgroundGlow(AppStyle style) {
    return AnimatedBuilder(
      animation: _drift,
      builder: (c, _) {
        final t = Curves.easeInOut.transform(_drift.value);
        return Stack(
          children: [
            Positioned(
              top: -120 + t * 40,
              right: -100 + t * -30,
              child: _glowCircle(320, style.accent.withValues(alpha: 0.22)),
            ),
            Positioned(
              bottom: -140 - t * 40,
              left: -120 - t * 30,
              child: _glowCircle(380, Colors.white.withValues(alpha: 0.10)),
            ),
            Positioned(
              top: 180 - t * 20,
              left: -60 + t * 20,
              child: _glowCircle(180, style.accent.withValues(alpha: 0.10)),
            ),
          ],
        );
      },
    );
  }

  Widget _glowCircle(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      );

  /// 左上角设置按钮：小号玻璃圆钮，与卡片同风格。
  Widget _settingsButton(AppStyle style) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _showSettingsSheet,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Color.alphaBlend(style.surface, const Color(0x66000000)),
              shape: BoxShape.circle,
              border: Border.all(color: style.surfaceBorder),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Icon(Icons.tune_rounded,
                size: 20, color: style.textPrimary),
          ),
        ),
      );

  /// 设置面板：接口地址（自定义 + 保存）与主题切换，玻璃风格与登录卡一致。
  /// 内容包 Consumer：主题切换时弹窗自身随 provider 重建，选中态即时刷新。
  void _showSettingsSheet() {
    final urlCtrl = TextEditingController(text: AppConfig.instance.baseUrl);
    final urlFocus = FocusNode();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (bc) => Consumer(builder: (bc2, sheetRef, _) {
        final style = kStyles[sheetRef.watch(styleIndexProvider)];
        final radius = BorderRadius.circular(style.uiRadius + 10);
        void toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(msg),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2)),
            );
        Future<void> save() async {
          final url = urlCtrl.text.trim();
          if (url.isEmpty || !url.startsWith('http')) {
            toast('地址需以 http(s):// 开头');
            return;
          }
          await AppConfig.saveBaseUrl(url);
          // 当前会话立即生效；下次启动由 AppConfig.load 读回。
          ref.read(apiProvider).setBaseUrl(url);
          toast('已保存：$url');
        }

        return Padding(
          // 键盘弹出时让位。
          padding: EdgeInsets.only(bottom: MediaQuery.of(bc).viewInsets.bottom),
          child: SafeArea(
            child: Center(
              child: Container(
                margin: const EdgeInsets.all(16),
                constraints: const BoxConstraints(maxWidth: 420),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                      style.surface, const Color(0x73000000)),
                  borderRadius: radius,
                  border: Border.all(color: style.surfaceBorder),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 48,
                        offset: const Offset(0, 18)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: radius,
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 拖拽把手 + 标题
                          Center(
                            child: Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: style.textSecondary
                                    .withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Icon(Icons.tune_rounded,
                                  size: 18, color: style.accent),
                              const SizedBox(width: 8),
                              Text('设置',
                                  style: TextStyle(
                                      color: style.textPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                          const SizedBox(height: 20),
                          // ── 接口地址 ──
                          Text('接口地址',
                              style: TextStyle(
                                  color: style.textSecondary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: urlCtrl,
                            focusNode: urlFocus,
                            onSubmitted: (_) => save(),
                            style: TextStyle(
                                color: style.textPrimary, fontSize: 14),
                            decoration: InputDecoration(
                              prefixIcon: Icon(Icons.link_rounded,
                                  size: 19, color: style.textSecondary),
                              hintText: 'https://your-api.example.com',
                              hintStyle: TextStyle(
                                  color: style.textSecondary
                                      .withValues(alpha: 0.5),
                                  fontSize: 13),
                              isDense: true,
                              filled: true,
                              fillColor: style.textSecondary
                                  .withValues(alpha: 0.10),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 14),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                      style.uiRadius),
                                  borderSide: BorderSide.none),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                      style.uiRadius),
                                  borderSide: BorderSide(
                                      color: style.surfaceBorder)),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                      style.uiRadius),
                                  borderSide: BorderSide(
                                      color: style.accent, width: 1.4)),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Material(
                            color: style.accent,
                            borderRadius:
                                BorderRadius.circular(style.uiRadius),
                            child: InkWell(
                              borderRadius:
                                  BorderRadius.circular(style.uiRadius),
                              onTap: save,
                              child: Container(
                                height: 44,
                                alignment: Alignment.center,
                                child: Text('保存接口地址',
                                    style: TextStyle(
                                        color: const Color(0xE6000000),
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          // ── 主题 ──
                          Text('主题',
                              style: TextStyle(
                                  color: style.textSecondary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1)),
                          const SizedBox(height: 8),
                          for (final (i, s) in kStyles.indexed)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => ref
                                    .read(styleIndexProvider.notifier)
                                    .set(i),
                                child: AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: i == sheetRef.watch(styleIndexProvider)
                                        ? style.accent.withValues(alpha: 0.14)
                                        : style.textSecondary
                                            .withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(
                                        style.uiRadius),
                                    border: Border.all(
                                        color: i == sheetRef.watch(styleIndexProvider)
                                            ? style.accent
                                                .withValues(alpha: 0.55)
                                            : style.surfaceBorder),
                                  ),
                                  child: Row(
                                    children: [
                                      // 主题预览色球（accent 渐变）
                                      Container(
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              s.accent,
                                              s.bgTop
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(s.name,
                                            style: TextStyle(
                                                color: style.textPrimary,
                                                fontSize: 13.5,
                                                fontWeight: i ==
                                                        sheetRef.watch(
                                                            styleIndexProvider)
                                                    ? FontWeight.w600
                                                    : FontWeight.w400)),
                                      ),
                                      if (i == sheetRef.watch(styleIndexProvider))
                                        Icon(Icons.check_circle_rounded,
                                            size: 18, color: style.accent),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        }),
      );
  }

  /// 入场动效：第 [step] 层延迟淡入 + 上滑。
  Widget _staggered(int step, Widget child) {
    final begin = (step * 0.12).clamp(0.0, 0.6);
    final anim = CurvedAnimation(
      parent: _entry,
      curve: Interval(begin, (begin + 0.4).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.18), end: Offset.zero)
            .animate(anim),
        child: child,
      ),
    );
  }

  Widget _glassCard(AppStyle style) {
    final radius = BorderRadius.circular(style.uiRadius + 10);
    return Container(
      decoration: BoxDecoration(
        color: Color.alphaBlend(style.surface, const Color(0x73000000)),
        borderRadius: radius,
        border: Border.all(color: style.surfaceBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 48,
              offset: const Offset(0, 18)),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _staggered(0, _brandMark(style)),
                const SizedBox(height: 18),
                _staggered(1, _headline(style)),
                const SizedBox(height: 20),
                _staggered(2, _segmentTabs(style)),
                const SizedBox(height: 20),
                _staggered(3, _errorBanner(style)),
                // 表单区：高度自适应，TabBarView 负责滑动切换。
                _staggered(
                  4,
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    child: SizedBox(
                      height: _formHeight(),
                      child: TabBarView(
                        controller: _tab,
                        children: [
                          _phoneForm(style),
                          _qrForm(style),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 验证码表单高约 3 行控件；二维码表单更高（码图 210 + 提示）。
  double _formHeight() => _tab.index == 0 ? 240 : 320;

  Widget _brandMark(AppStyle style) => Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [style.accent, style.accent.withValues(alpha: 0.55)],
              ),
              boxShadow: [
                BoxShadow(
                    color: style.accent.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8)),
              ],
            ),
            child: const Icon(Icons.graphic_eq_rounded,
                color: Color(0xE6000000), size: 28),
          ),
        ],
      );

  Widget _headline(AppStyle style) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('马上进入音乐',
              style: TextStyle(
                  color: style.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Text('二维码 / 短信验证码登录 · 密码登录受云盾限制',
              style: TextStyle(
                  color: style.textSecondary,
                  fontSize: 12.5,
                  letterSpacing: 0.2)),
        ],
      );

  /// 分段式切换：药丸容器 + accent 滑块（替代原生 TabBar）。
  Widget _segmentTabs(AppStyle style) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: style.textSecondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final (i, label) in ['手机验证码', '二维码'].indexed)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _tab.animateTo(i,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic);
                  // 切到二维码页时自动生成，无需手动点击。
                  if (i == 1) _ensureQr();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _tab.index == i
                        ? style.accent
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: _tab.index == i
                        ? [BoxShadow(
                              color: style.accent.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 3))]
                        : const [],
                  ),
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 250),
                      style: TextStyle(
                        color: _tab.index == i
                            ? const Color(0xE6000000)
                            : style.textSecondary,
                        fontSize: 13.5,
                        fontWeight: _tab.index == i
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                      child: Text(label),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _errorBanner(AppStyle style) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: _error == null
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(style.uiRadius),
                border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline,
                      color: Colors.redAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 12.5)),
                  ),
                ],
              ),
            ),
    );
  }

  /// 发光输入框：聚焦时 accent 描边 + 柔光。
  Widget _field(
    AppStyle style, {
    required TextEditingController controller,
    required FocusNode focus,
    required IconData icon,
    required String hint,
    TextInputType? keyboard,
    Widget? suffix,
  }) {
    final focused = focus.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: style.textSecondary
            .withValues(alpha: focused ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(style.uiRadius),
        border: Border.all(
            color: focused ? style.accent : style.surfaceBorder,
            width: focused ? 1.4 : 1),
        boxShadow: focused
            ? [BoxShadow(
                  color: style.accent.withValues(alpha: 0.18),
                  blurRadius: 14)]
            : const [],
      ),
      child: TextField(
        controller: controller,
        focusNode: focus,
        keyboardType: keyboard,
        style: TextStyle(color: style.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          prefixIcon: Icon(icon,
              color: focused ? style.accent : style.textSecondary, size: 20),
          hintText: hint,
          hintStyle: TextStyle(
              color: style.textSecondary.withValues(alpha: 0.6),
              fontSize: 13.5),
          border: InputBorder.none,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 15),
          suffixIcon: suffix,
        ),
      ),
    );
  }

  Widget _phoneForm(AppStyle style) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _field(
            style,
            controller: _phone,
            focus: _phoneFocus,
            icon: Icons.smartphone_rounded,
            hint: '手机号',
            keyboard: TextInputType.phone,
          ),
          const SizedBox(height: 14),
          _field(
            style,
            controller: _captcha,
            focus: _captchaFocus,
            icon: Icons.lock_outline_rounded,
            hint: '验证码',
            keyboard: TextInputType.number,
            suffix: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: _sending ? null : _send,
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  backgroundColor:
                      style.accent.withValues(alpha: _sending ? 0.08 : 0.16),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(style.uiRadius - 2)),
                ),
                child: _sending
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: style.accent))
                    : Text('获取验证码',
                        style: TextStyle(
                            color: style.accent,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _loginButton(style),
        ],
      );

  /// 主按钮：accent 实心 + 悬停加光 + 按压反馈，加载中转圈。
  Widget _loginButton(AppStyle style) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: style.accent,
        borderRadius: BorderRadius.circular(style.uiRadius + 2),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(style.uiRadius + 2),
          hoverColor: Colors.white.withValues(alpha: 0.14),
          splashColor: Colors.white.withValues(alpha: 0.22),
          onTap: _logging ? null : _login,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _logging ? 0.7 : 1.0,
            child: Container(
              height: 50,
              alignment: Alignment.center,
              child: _logging
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: const Color(0xE6000000)))
                  : const Text('登 录',
                      style: TextStyle(
                          color: Color(0xE6000000),
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 6)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _qrForm(AppStyle style) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_qrImg == null)
            // 切入本页即自动生成，这里只做加载占位（无手动按钮）。
            Container(
              width: 216,
              height: 216,
              decoration: BoxDecoration(
                color: style.textSecondary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: style.surfaceBorder),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: style.accent)),
                    const SizedBox(height: 12),
                    Text(_qrBusy ? '正在生成二维码…' : '准备中…',
                        style: TextStyle(
                            color: style.textSecondary, fontSize: 12.5)),
                  ],
                ),
              ),
            )
          else
            // 二维码保持静止：仅失效时叠加模糊遮罩，点击刷新。
            GestureDetector(
              onTap: (_qrExpired && !_qrBusy) ? _startQr : null,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 250),
                    opacity: _qrExpired ? 0.25 : 1.0,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 24,
                              offset: const Offset(0, 10)),
                        ],
                      ),
                      child: _qrImage(_qrImg!),
                    ),
                  ),
                  if (_qrExpired || _qrBusy)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                        child: Container(
                          width: 216,
                          height: 216,
                          color: Colors.black.withValues(alpha: 0.45),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                    _qrBusy
                                        ? Icons.hourglass_top_rounded
                                        : Icons.refresh_rounded,
                                    color: Colors.white,
                                    size: 30),
                                const SizedBox(height: 8),
                                Text(_qrBusy ? '加载中…' : '二维码已失效\n点击刷新',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        height: 1.6)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.nfc_rounded,
                  size: 15, color: style.textSecondary),
              const SizedBox(width: 5),
              Text('用网易云音乐 App 扫码登录',
                  style: TextStyle(color: style.textSecondary, fontSize: 12.5)),
            ],
          ),
        ],
      );

  Widget _qrImage(String dataUri) {
    final b64 = dataUri.contains(',') ? dataUri.split(',').last : dataUri;
    late final Uint8List bytes;
    try {
      bytes = base64Decode(b64);
    } catch (_) {
      return const Icon(Icons.qr_code, size: 188, color: Colors.black54);
    }
    return Image.memory(bytes, width: 188, height: 188);
  }
}
