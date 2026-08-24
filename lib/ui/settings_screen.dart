import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../domain/app_settings.dart';
import '../domain/quota_models.dart';
import '../q3/q3_screen.dart';
import 'app_theme.dart';
import 'oauth_diagnostics_screen.dart';
import 'sign_in_flow.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: '返回',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
            ),
            title: const Text(
              '设置',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
            children: [
              const _SectionLabel('账户'),
              _SettingsCard(
                children: [
                  for (final provider in ProviderId.values) ...[
                    _AccountRow(controller: controller, provider: provider),
                    if (provider != ProviderId.values.last)
                      const _InnerDivider(),
                  ],
                ],
              ),
              const SizedBox(height: 24),
              const _SectionLabel('外观'),
              _SettingsCard(
                children: [
                  _ChoiceGroup<AppearancePreference>(
                    value: controller.settings.appearance,
                    values: AppearancePreference.values,
                    label: _appearanceLabel,
                    onChanged: controller.setAppearance,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _SectionLabel('刷新间隔'),
              _SettingsCard(
                children: [
                  for (final interval in RefreshInterval.values) ...[
                    _RadioRow<RefreshInterval>(
                      value: interval,
                      groupValue: controller.settings.refreshInterval,
                      label: '${interval.minutes} 分钟',
                      onChanged: controller.setRefreshInterval,
                    ),
                    if (interval != RefreshInterval.values.last)
                      const _InnerDivider(),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '仅在应用位于前台时自动刷新；下拉刷新仍受 1 分钟节流和 Provider 退避限制。',
                  style: TextStyle(
                    color: context.palette.default500,
                    fontSize: 12.5,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const _SectionLabel('登录'),
              _SettingsCard(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    minTileHeight: 58,
                    title: const Text(
                      '登录诊断',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '登录失败时把记录复制给开发者',
                      style: TextStyle(
                        color: context.palette.default500,
                        fontSize: 12,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: context.palette.default400,
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const OAuthDiagnosticsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
              if (kDebugMode) ...[
                const SizedBox(height: 24),
                const _SectionLabel('开发'),
                _SettingsCard(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      minTileHeight: 58,
                      title: const Text(
                        'Q3 Loopback 验证工具',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '仅 Debug 构建可见',
                        style: TextStyle(
                          color: context.palette.default500,
                          fontSize: 12,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: context.palette.default400,
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const Q3Screen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 26),
              Text(
                'CC Trace 只读取 Provider 用量，不发起对话、不读取代码，也不把凭据发送到自有服务器。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.palette.default400,
                  fontSize: 11.5,
                  height: 1.55,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _appearanceLabel(AppearancePreference appearance) {
    return switch (appearance) {
      AppearancePreference.system => '跟随系统',
      AppearancePreference.light => '浅色',
      AppearancePreference.dark => '深色',
    };
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.controller, required this.provider});

  final AppController controller;
  final ProviderId provider;

  @override
  Widget build(BuildContext context) {
    final state = controller.provider(provider);
    final busy = controller.authorizing == provider;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider.displayName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  state.isSignedIn
                      ? state.identity?.accountHint ?? '已登录'
                      : '未登录',
                  style: TextStyle(
                    color: context.palette.default500,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (state.isSignedIn)
            PopupMenuButton<String>(
              tooltip: '${provider.displayName} 账户操作',
              color: context.palette.content1,
              onSelected: (value) async {
                if (value == 'login') {
                  await startSignIn(context, controller, provider);
                } else if (value == 'logout' &&
                    context.mounted &&
                    await _confirmLogout(context, provider)) {
                  await controller.signOut(provider);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'login', child: Text('重新登录')),
                PopupMenuItem(value: 'logout', child: Text('退出登录')),
              ],
              icon: const Icon(Icons.more_horiz_rounded),
            )
          else
            TextButton(
              onPressed: () => startSignIn(context, controller, provider),
              child: const Text('登录'),
            ),
        ],
      ),
    );
  }

  Future<bool> _confirmLogout(BuildContext context, ProviderId provider) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: context.palette.content1,
            title: Text('退出 ${provider.displayName}？'),
            content: const Text('本机保存的登录凭据和额度缓存会一并删除。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(
                  foregroundColor: context.palette.danger,
                ),
                child: const Text('退出登录'),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class _ChoiceGroup<T> extends StatelessWidget {
  const _ChoiceGroup({
    required this.value,
    required this.values,
    required this.label,
    required this.onChanged,
  });

  final T value;
  final List<T> values;
  final String Function(T value) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<T>(
          segments: [
            for (final candidate in values)
              ButtonSegment<T>(value: candidate, label: Text(label(candidate))),
          ],
          selected: {value},
          showSelectedIcon: false,
          onSelectionChanged: (selected) => onChanged(selected.first),
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            side: WidgetStatePropertyAll(
              BorderSide(color: context.palette.divider),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadioRow<T> extends StatelessWidget {
  const _RadioRow({
    required this.value,
    required this.groupValue,
    required this.label,
    required this.onChanged,
  });

  final T value;
  final T groupValue;
  final String label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return InkWell(
      onTap: () => onChanged(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 14.5)),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 20,
              color: selected
                  ? context.palette.primary
                  : context.palette.default400,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        label,
        style: TextStyle(
          color: context.palette.default500,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.palette.content1,
        borderRadius: BorderRadius.circular(18),
        boxShadow: _cardShadow(context),
      ),
      child: Column(children: children),
    );
  }
}

class _InnerDivider extends StatelessWidget {
  const _InnerDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 16,
      endIndent: 16,
      color: context.palette.divider,
    );
  }
}

List<BoxShadow> _cardShadow(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 14,
            offset: Offset(0, 2),
          ),
          BoxShadow(color: Color(0x0dffffff), spreadRadius: 1),
        ]
      : const [
          BoxShadow(
            color: Color(0x0f111111),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
          BoxShadow(color: Color(0x08111111), spreadRadius: 1),
        ];
}
