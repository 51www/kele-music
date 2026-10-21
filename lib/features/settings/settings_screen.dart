import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../core/styles.dart';
import '../../data/app_config.dart';
import '../../providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final idx = ref.watch(styleIndexProvider);
    final notifier = ref.watch(styleIndexProvider.notifier);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: style.backgroundGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('设置',
                    style: TextStyle(
                        color: style.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 24),
                Text('界面风格',
                    style: TextStyle(
                        color: style.textPrimary, fontSize: 18)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  children: [
                    for (int i = 0; i < kStyles.length; i++)
                      ChoiceChip(
                        label: Text(kStyles[i].name),
                        selected: idx == i,
                        selectedColor: style.accent,
                        labelStyle: TextStyle(
                            color: idx == i
                                ? style.bgBottom
                                : style.textPrimary),
                        onSelected: (_) => notifier.set(i),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('后端 Base URL（当前实际生效）',
                    style: TextStyle(color: style.textSecondary)),
                const SizedBox(height: 4),
                // 显示实际生效地址（AppConfig 单例），而非编译期常量 kBaseUrl：
                // saved 覆盖 / asset 覆盖 / dart-define 都可能让实际值 ≠ 默认值。
                SelectableText(AppConfig.instance.baseUrl,
                    style: TextStyle(color: style.textPrimary)),
                if (AppConfig.instance.baseUrl != kBaseUrl)
                  StatefulBuilder(builder: (context, setLocal) {
                    return TextButton(
                      onPressed: () async {
                        await AppConfig.resetBaseUrl();
                        setLocal(() {}); // 刷新按钮可见性。
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content:
                                  Text('已恢复默认：${AppConfig.instance.baseUrl}'),
                              behavior: SnackBarBehavior.floating));
                        }
                      },
                      child: const Text('恢复默认地址'),
                    );
                  }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
