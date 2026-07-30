import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../app/app_controller.dart';
import '../domain/quota_models.dart';
import 'app_theme.dart';
import 'settings_screen.dart';

class UsageScreen extends StatelessWidget {
  const UsageScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: controller.initialized && controller.allSignedOut
                ? _Onboarding(controller: controller)
                : _UsageContent(controller: controller),
          ),
        );
      },
    );
  }
}

class _UsageContent extends StatelessWidget {
  const _UsageContent({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Header(controller: controller),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => controller.refreshAll(manual: true),
            color: context.palette.primary,
            backgroundColor: context.palette.content1,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              children: [
                if (controller.notice != null)
                  _HeldBanner(message: controller.notice!),
                if (!controller.initialized) ...[
                  const _SkeletonCard(provider: ProviderId.codex),
                  const SizedBox(height: 12),
                  const _SkeletonCard(provider: ProviderId.claude),
                ] else ...[
                  for (final provider in ProviderId.values) ...[
                    _ProviderCard(
                      key: ValueKey(provider),
                      controller: controller,
                      state: controller.provider(provider),
                    ),
                    if (provider != ProviderId.values.last)
                      const SizedBox(height: 12),
                  ],
                ],
                const SizedBox(height: 16),
                Text(
                  '只读用量 · 凭据仅保存在本机',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.palette.default400,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final subtitle = _latestSubtitle(controller);
    final dot = _statusColor(context, controller);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 10, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '用量',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    letterSpacing: -1.05,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                        boxShadow: _isLive(controller)
                            ? [
                                BoxShadow(
                                  color: context.palette.success.withValues(
                                    alpha: .22,
                                  ),
                                  spreadRadius: 3,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(subtitle, style: _metaStyle(context)),
                  ],
                ),
              ],
            ),
          ),
          _RoundAction(
            tooltip: '刷新',
            onPressed: controller.isRefreshing
                ? null
                : () => controller.refreshAll(manual: true),
            child: controller.isRefreshing
                ? const SizedBox.square(
                    dimension: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 21),
          ),
          _RoundAction(
            tooltip: '设置',
            onPressed: () => _openSettings(context, controller),
            child: const Icon(Icons.tune_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class _Onboarding extends StatelessWidget {
  const _Onboarding({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 10, top: 6),
            child: _RoundAction(
              tooltip: '设置',
              onPressed: () => _openSettings(context, controller),
              child: const Icon(Icons.tune_rounded, size: 20),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: context.palette.primary.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.speed_rounded,
                    size: 25,
                    color: context.palette.primary,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '先登录，\n才能看到额度',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    letterSpacing: -.8,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'CC Trace 只读取用量数据，不发起对话、不碰你的代码。登录信息存在这台手机上。',
                  style: TextStyle(
                    color: context.palette.default500,
                    fontSize: 14.5,
                    height: 1.65,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: controller.authorizing == null
                        ? () => controller.signIn(ProviderId.codex)
                        : null,
                    child: _LoginLabel(
                      busy: controller.authorizing == ProviderId.codex,
                      label: '登录 Codex',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: controller.authorizing == null
                        ? () => controller.signIn(ProviderId.claude)
                        : null,
                    child: _LoginLabel(
                      busy: controller.authorizing == ProviderId.claude,
                      label: '登录 Claude Code',
                    ),
                  ),
                ),
                if (controller.notice != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    controller.notice!,
                    style: TextStyle(
                      color: context.palette.danger,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          child: Text(
            '两个可以只登一个，之后在设置里补另一个',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.palette.default400, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _ProviderCard extends StatefulWidget {
  const _ProviderCard({
    required this.controller,
    required this.state,
    super.key,
  });

  final AppController controller;
  final ProviderViewState state;

  @override
  State<_ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends State<_ProviderCard>
    with SingleTickerProviderStateMixin {
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 300,
    damping: 34.6410161514,
  );

  late final AnimationController _expansion;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _expansion = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant _ProviderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_canExpand(widget.state) && _expanded) {
      _expanded = false;
      _expansion.value = 0;
    }
  }

  @override
  void dispose() {
    _expansion.dispose();
    super.dispose();
  }

  void _toggleExpansion() {
    if (!_canExpand(widget.state)) {
      return;
    }
    final target = _expanded ? 0.0 : 1.0;
    setState(() {
      _expanded = !_expanded;
    });
    if (MediaQuery.of(context).disableAnimations) {
      _expansion.value = target;
      return;
    }
    _expansion.animateWith(
      SpringSimulation(
        _spring,
        _expansion.value,
        target,
        _expansion.velocity,
        snapToEnd: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final state = widget.state;
    final visibleWindows =
        state.snapshot?.windows
            .where((window) => window.kind != QuotaWindowKind.unknown)
            .toList(growable: false) ??
        const [];
    final primary = visibleWindows.isEmpty
        ? null
        : visibleWindows.firstWhere(
            (window) => window.isPrimary,
            orElse: () => visibleWindows.first,
          );
    final secondary = primary == null
        ? const <QuotaWindow>[]
        : visibleWindows.where((window) => window.id != primary.id).toList();
    final stale = state.freshness == SnapshotFreshness.stale;
    final alert = _alertFor(state);
    final canExpand = _canExpand(state);

    return Container(
      decoration: BoxDecoration(
        color: context.palette.content1,
        borderRadius: BorderRadius.circular(18),
        boxShadow: _cardShadow(context),
      ),
      child: Material(
        color: context.palette.content1,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 可展开时保留无障碍语义，但不给可见的箭头或「轻点展开」提示：
            // 展开的是重置次数明细，属于可选信息，不值得在卡片上常驻一个控件。
            Semantics(
              button: canExpand,
              expanded: canExpand ? _expanded : null,
              child: InkWell(
                onTap: canExpand ? _toggleExpansion : null,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    17,
                    16,
                    17,
                    alert == null ? 17 : 0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CardHeader(state: state),
                      const SizedBox(height: 15),
                      if (primary != null) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _PrimaryPercent(
                              percent: primary.remainingPercent,
                              color: stale
                                  ? context.palette.foreground
                                  : _quotaColor(
                                      context,
                                      primary.remainingPercent,
                                    ),
                            ),
                            const SizedBox(width: 10),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                _windowLabel(state.provider, primary),
                                style: _windowLabelStyle(context),
                              ),
                            ),
                            const Spacer(),
                            Flexible(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: stale
                                    ? Text(
                                        _ageLabel(
                                          state.lastSuccessAt,
                                          controller.now,
                                          oldData: true,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.end,
                                        style: _metaStyle(context),
                                      )
                                    : _ResetCountdownText(
                                        resetsAt: primary.resetsAt,
                                        now: () => controller.now,
                                        textAlign: TextAlign.end,
                                        style: _metaStyle(
                                          context,
                                          emphasis: true,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _QuotaProgress(
                          percent: primary.remainingPercent,
                          color: stale
                              ? context.palette.default400
                              : _quotaColor(context, primary.remainingPercent),
                          height: 9,
                        ),
                      ] else ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '--',
                              style: TextStyle(
                                color: context.palette.default400,
                                fontSize: 38,
                                fontWeight: FontWeight.w700,
                                height: 1,
                                letterSpacing: -1.6,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                state.provider == ProviderId.codex
                                    ? 'WEEKLY'
                                    : '5HOUR',
                                style: _windowLabelStyle(context),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(_emptyMessage(state), style: _metaStyle(context)),
                      ],
                      for (final window in secondary)
                        _QuotaSubRow(
                          provider: state.provider,
                          window: window,
                          stale: stale,
                          now: () => controller.now,
                        ),
                      if (state.provider == ProviderId.codex &&
                          (state.isSignedIn || state.hasSnapshot))
                        _ResetCreditsRow(credits: state.resetCredits),
                      if (canExpand)
                        _CodexTimeDetailsReveal(
                          animation: _expansion,
                          expanded: _expanded,
                          child: _ResetCreditDetails(
                            credits: state.resetCredits!,
                            now: controller.now,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (alert != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(17, 0, 17, 17),
                child: _StateAlert(
                  alert: alert,
                  onPressed: () {
                    if (alert.action == _AlertAction.login) {
                      controller.signIn(state.provider);
                    } else {
                      controller.refreshProvider(state.provider);
                    }
                  },
                  busy: controller.authorizing == state.provider,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Provider 名 + 账号 + 套餐排成一行，按基线对齐。
///
/// 账号用 [Flexible]（loose）而不是 `Spacer` + `Flexible`：后者会让空白和账号
/// 各分走一半剩余宽度，账号因此在空间充足时也被截断。套餐留在弹性区之外，
/// 保证账号再长也不会把它挤掉。
class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.state});

  final ProviderViewState state;

  @override
  Widget build(BuildContext context) {
    final account = state.isSignedIn
        ? state.identity?.accountHint ?? '已登录'
        : '未登录';
    final plan = state.isSignedIn ? state.identity?.plan : null;
    final secondary = TextStyle(
      color: context.palette.default500,
      fontSize: 12.5,
      height: 1,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          state.provider.displayName,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            height: 1,
            letterSpacing: -.3,
          ),
        ),
        const SizedBox(width: 9),
        Flexible(
          child: Text(
            account,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: secondary,
          ),
        ),
        if (plan != null) ...[
          Text(
            ' · ',
            style: secondary.copyWith(color: context.palette.default400),
          ),
          Text(
            _planLabel(plan),
            style: secondary.copyWith(
              color: context.palette.default600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _CodexTimeDetailsReveal extends StatelessWidget {
  const _CodexTimeDetailsReveal({
    required this.animation,
    required this.expanded,
    required this.child,
  });

  final Animation<double> animation;
  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: animation,
      alignment: AlignmentDirectional.topStart,
      child: FadeTransition(
        opacity: animation,
        child: AnimatedBuilder(
          animation: animation,
          child: ExcludeSemantics(excluding: !expanded, child: child),
          builder: (context, child) {
            final progress = animation.value.clamp(0.0, 1.0);
            return Transform.translate(
              offset: Offset(0, 6 * (1 - progress)),
              child: child,
            );
          },
        ),
      ),
    );
  }
}

/// 展开态只补充折叠态没有的信息：每批重置次数各自的过期时刻。
///
/// 卡片上方已经逐窗口显示了倒计时，展开时不再把这些窗口的绝对重置时间重列一遍
/// ——那是同一份数据换个写法。这一点推翻了 `docs/移动端额度展示要求.md` §3.2
/// 原先「展开态显示所有已知额度窗口的精确重置时间」的写法，文档已同步。
class _ResetCreditDetails extends StatelessWidget {
  const _ResetCreditDetails({required this.credits, required this.now});

  final ResetCreditsSnapshot credits;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final expiryGroups = _groupCreditExpiries(credits.availableCredits);
    final undetailed = credits.availableCount > credits.availableCredits.length
        ? credits.availableCount - credits.availableCredits.length
        : 0;

    return Container(
      margin: const EdgeInsets.only(top: 11),
      padding: const EdgeInsets.only(top: 11),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.palette.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final group in expiryGroups)
            _CreditExpiryRow(
              count: group.count,
              expiry: _absoluteTimeLabel(group.expiry, now),
            ),
          if (undetailed > 0)
            _CreditExpiryRow(count: undetailed, expiry: '过期时间未知'),
        ],
      ),
    );
  }
}

class _CreditExpiryRow extends StatelessWidget {
  const _CreditExpiryRow({required this.count, required this.expiry});

  final int count;
  final String expiry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        children: [
          Text(
            '$count 次',
            style: TextStyle(
              color: context.palette.default600,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              expiry,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _metaStyle(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreditExpiryGroup {
  const _CreditExpiryGroup({required this.count, required this.expiry});

  final int count;
  final DateTime? expiry;
}

class _QuotaSubRow extends StatelessWidget {
  const _QuotaSubRow({
    required this.provider,
    required this.window,
    required this.stale,
    required this.now,
  });

  final ProviderId provider;
  final QuotaWindow window;
  final bool stale;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final color = stale
        ? context.palette.default400
        : _quotaColor(context, window.remainingPercent);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.palette.divider)),
      ),
      child: Row(
        children: [
          // 固定最小宽度，多条次级行的进度条起点才会对齐。
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 46),
            child: Text(
              _windowLabel(provider, window),
              style: _windowLabelStyle(context, size: 10.5),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QuotaProgress(
              percent: window.remainingPercent,
              color: color,
              height: 5,
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 34),
            child: Text(
              '${_whole(window.remainingPercent)}%',
              textAlign: TextAlign.end,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 40),
            child: _ResetCountdownText(
              resetsAt: window.resetsAt,
              now: now,
              textAlign: TextAlign.end,
              style: _metaStyle(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResetCreditsRow extends StatelessWidget {
  const _ResetCreditsRow({required this.credits});

  final ResetCreditsSnapshot? credits;

  @override
  Widget build(BuildContext context) {
    final earliest = credits?.earliestExpiry;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.palette.divider)),
      ),
      child: Row(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 46),
            child: Text(
              'RESETS',
              style: _windowLabelStyle(context, size: 10.5),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            credits == null ? '--' : '${credits!.availableCount} 次',
            style: TextStyle(
              color: credits == null
                  ? context.palette.default400
                  : context.palette.foreground,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const Spacer(),
          if (earliest != null)
            Text(
              '最早 ${earliest.month}/${earliest.day} 过期',
              style: _metaStyle(context),
            ),
        ],
      ),
    );
  }
}

enum _AlertAction { login, retry }

class _AlertData {
  const _AlertData({
    required this.title,
    required this.message,
    required this.button,
    required this.tone,
    required this.action,
  });

  final String title;
  final String message;
  final String button;
  final _AlertTone tone;
  final _AlertAction action;
}

enum _AlertTone { warning, danger, low }

_AlertData? _alertFor(ProviderViewState state) {
  if (!state.isSignedIn) {
    return _AlertData(
      title: '还没登录 ${state.provider.displayName}',
      message: '',
      button: '登录 ${state.provider.displayName}',
      tone: _AlertTone.low,
      action: _AlertAction.login,
    );
  }
  if (state.errorKind == ErrorKind.credentials) {
    return _AlertData(
      title: '登录已失效',
      message: state.hasSnapshot ? '现在显示的是旧数据，不是最新额度。' : '请重新登录后读取额度。',
      button: '重新登录 ${state.provider.displayName}',
      tone: _AlertTone.danger,
      action: _AlertAction.login,
    );
  }
  if (state.availability == ProviderAvailability.rateLimited) {
    return const _AlertData(
      title: '刷新已暂缓',
      message: 'Provider 要求降低刷新频率，旧数据会继续保留。',
      button: '稍后重试',
      tone: _AlertTone.warning,
      action: _AlertAction.retry,
    );
  }
  if (state.availability == ProviderAvailability.offline) {
    return const _AlertData(
      title: '暂时无法连接',
      message: '网络恢复后会在前台自动重试。',
      button: '重试',
      tone: _AlertTone.warning,
      action: _AlertAction.retry,
    );
  }
  if (state.errorKind == ErrorKind.protocol) {
    return const _AlertData(
      title: '额度数据无法识别',
      message: 'Provider 的响应格式可能发生了变化。',
      button: '重试',
      tone: _AlertTone.danger,
      action: _AlertAction.retry,
    );
  }
  return null;
}

class _StateAlert extends StatelessWidget {
  const _StateAlert({
    required this.alert,
    required this.onPressed,
    required this.busy,
  });

  final _AlertData alert;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final tone = switch (alert.tone) {
      _AlertTone.warning => context.palette.warning,
      _AlertTone.danger => context.palette.danger,
      _AlertTone.low => context.palette.low,
    };
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          tone.withValues(alpha: .12),
          context.palette.content1,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                tone.withValues(alpha: .24),
                context.palette.content1,
              ),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(Icons.warning_amber_rounded, size: 15, color: tone),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.title,
                  style: TextStyle(
                    color: tone,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (alert.message.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    alert.message,
                    style: TextStyle(
                      color: context.palette.default600,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                TextButton(
                  onPressed: busy ? null : onPressed,
                  style: TextButton.styleFrom(
                    foregroundColor: tone,
                    backgroundColor: Color.alphaBlend(
                      tone.withValues(alpha: .16),
                      context.palette.content1,
                    ),
                    minimumSize: const Size(44, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: busy
                      ? SizedBox.square(
                          dimension: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: tone,
                          ),
                        )
                      : Text(alert.button),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeldBanner extends StatelessWidget {
  const _HeldBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 15,
            color: context.palette.warning,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              message,
              style: TextStyle(
                color: context.palette.warning,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.provider});

  final ProviderId provider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(17, 16, 17, 17),
      decoration: BoxDecoration(
        color: context.palette.content1,
        borderRadius: BorderRadius.circular(18),
        boxShadow: _cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                provider.displayName,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  letterSpacing: -.3,
                ),
              ),
              const SizedBox(width: 9),
              const _Skeleton(width: 132, height: 11, radius: 999),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '--',
                style: TextStyle(
                  color: context.palette.default400,
                  fontSize: 38,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  letterSpacing: -1.6,
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  provider == ProviderId.codex ? 'WEEKLY' : '5HOUR',
                  style: _windowLabelStyle(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _Skeleton(width: double.infinity, height: 9, radius: 999),
          const SizedBox(height: 12),
          Text('正在检查额度', style: _metaStyle(context)),
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.palette.default200,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// 主读数：数字用等宽数位避免倒计时刷新时抖动，`%` 单独降一档字号，
/// 让视线先落在数字上而不是符号上。
class _PrimaryPercent extends StatelessWidget {
  const _PrimaryPercent({required this.percent, required this.color});

  final double percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '${_whole(percent)}'),
          TextSpan(
            text: '%',
            style: TextStyle(
              fontSize: 18,
              letterSpacing: -.3,
              color: color.withValues(alpha: .75),
            ),
          ),
        ],
      ),
      style: TextStyle(
        color: color,
        fontSize: 38,
        fontWeight: FontWeight.w700,
        height: 1,
        letterSpacing: -1.6,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _QuotaProgress extends StatelessWidget {
  const _QuotaProgress({
    required this.percent,
    required this.color,
    required this.height,
  });

  final double percent;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: percent.clamp(0, 100).toDouble() / 100,
        minHeight: height,
        backgroundColor: context.palette.default100,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}

class _ResetCountdownText extends StatefulWidget {
  const _ResetCountdownText({
    required this.resetsAt,
    required this.now,
    required this.style,
    this.textAlign,
  });

  final DateTime? resetsAt;
  final DateTime Function() now;
  final TextStyle style;
  final TextAlign? textAlign;

  @override
  State<_ResetCountdownText> createState() => _ResetCountdownTextState();
}

class _ResetCountdownTextState extends State<_ResetCountdownText> {
  Timer? _minuteTicker;

  @override
  void initState() {
    super.initState();
    _minuteTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _minuteTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _resetLabel(widget.resetsAt, widget.now()),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: widget.textAlign,
      style: widget.style,
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: child,
      color: context.palette.default600,
      disabledColor: context.palette.default400,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(44),
        maximumSize: const Size.square(44),
        shape: const CircleBorder(),
      ),
    );
  }
}

class _LoginLabel extends StatelessWidget {
  const _LoginLabel({required this.busy, required this.label});

  final bool busy;
  final String label;

  @override
  Widget build(BuildContext context) {
    return busy
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(label);
  }
}

void _openSettings(BuildContext context, AppController controller) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(controller: controller),
    ),
  );
}

Color _quotaColor(BuildContext context, double percent) {
  if (percent == 0) {
    return context.palette.danger;
  }
  if (percent < 20) {
    return context.palette.low;
  }
  if (percent <= 50) {
    return context.palette.warning;
  }
  return context.palette.foreground;
}

int _whole(double value) => value.round().clamp(0, 100).toInt();

/// 窗口标签走小型大写的缩写，跟大号读数拉开层级。
///
/// Claude 的 `weekly_all` 显示成 `ALL`——它要跟同为周窗口的 `OPUS` / `SONNET`
/// 区分开，写 `WEEKLY` 反而看不出差别；Codex 只有一个周窗口，仍写 `WEEKLY`。
String _windowLabel(ProviderId provider, QuotaWindow window) {
  return switch (window.kind) {
    QuotaWindowKind.fiveHour => '5HOUR',
    QuotaWindowKind.weekly => provider == ProviderId.claude ? 'ALL' : 'WEEKLY',
    QuotaWindowKind.modelWeekly =>
      (window.displayName ?? 'MODEL').toUpperCase(),
    QuotaWindowKind.unknown => (window.displayName ?? 'OTHER').toUpperCase(),
  };
}

TextStyle _windowLabelStyle(BuildContext context, {double size = 11}) {
  return TextStyle(
    color: context.palette.default400,
    fontSize: size,
    fontWeight: FontWeight.w600,
    height: 1,
    letterSpacing: .7,
  );
}

/// 倒计时、时刻、账号年龄这类附属数字统一用等宽数位，避免每分钟刷新时宽度跳动。
TextStyle _metaStyle(BuildContext context, {bool emphasis = false}) {
  return TextStyle(
    color: emphasis ? context.palette.default600 : context.palette.default500,
    fontSize: 12.5,
    fontWeight: emphasis ? FontWeight.w600 : FontWeight.w400,
    height: 1,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// 只有重置次数值得展开——额度窗口的重置时刻卡片上已经以倒计时形式给过了。
bool _canExpand(ProviderViewState state) {
  if (state.provider != ProviderId.codex) {
    return false;
  }
  final credits = state.resetCredits;
  if (credits == null) {
    return false;
  }
  return credits.availableCount > 0 || credits.availableCredits.isNotEmpty;
}

List<_CreditExpiryGroup> _groupCreditExpiries(List<ResetCreditEntry> credits) {
  final counts = <DateTime?, int>{};
  for (final credit in credits) {
    counts.update(credit.expiresAt, (count) => count + 1, ifAbsent: () => 1);
  }
  final groups = counts.entries
      .map((entry) => _CreditExpiryGroup(count: entry.value, expiry: entry.key))
      .toList();
  groups.sort((left, right) {
    final leftExpiry = left.expiry;
    final rightExpiry = right.expiry;
    if (leftExpiry == null) {
      return rightExpiry == null ? 0 : 1;
    }
    if (rightExpiry == null) {
      return -1;
    }
    return leftExpiry.compareTo(rightExpiry);
  });
  return groups;
}

/// 本地时刻。跨年才补年份；不带「重置」「过期」后缀，语境由所在行给出。
String _absoluteTimeLabel(DateTime? value, DateTime now) {
  if (value == null) {
    return '--';
  }
  final local = value.toLocal();
  final localNow = now.toLocal();
  final date = local.year == localNow.year
      ? '${local.month}/${local.day}'
      : '${local.year}/${local.month}/${local.day}';
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$date $hour:$minute';
}

String _emptyMessage(ProviderViewState state) {
  if (!state.isSignedIn) {
    return '登录后才能读到额度';
  }
  if (state.refresh == RefreshState.loading) {
    return '正在检查额度';
  }
  return switch (state.availability) {
    ProviderAvailability.offline => '暂时无法连接 Provider',
    ProviderAvailability.rateLimited => 'Provider 暂缓了刷新',
    ProviderAvailability.error => '暂时无法读取额度',
    ProviderAvailability.unsupported => '当前额度窗口暂不支持',
    _ => '尚未成功刷新',
  };
}

/// 倒计时压成 `6d2h` / `1h42m` / `35m`。语境已经由窗口标签给出，不再写「后重置」。
String _resetLabel(DateTime? reset, DateTime now) {
  if (reset == null) {
    return '--';
  }
  final remainingMinutes = reset.difference(now).inMinutes;
  if (remainingMinutes < 1) {
    return '<1m';
  }
  final days = remainingMinutes ~/ Duration.minutesPerDay;
  final hours = (remainingMinutes % Duration.minutesPerDay) ~/ 60;
  final minutes = remainingMinutes % 60;
  if (days > 0) {
    return hours > 0 ? '${days}d${hours}h' : '${days}d';
  }
  if (hours > 0) {
    return minutes > 0 ? '${hours}h${minutes}m' : '${hours}h';
  }
  return '${minutes}m';
}

String _planLabel(String value) {
  final normalized = value.trim();
  return switch (normalized.toLowerCase()) {
    'plus' => 'Plus',
    'pro' => 'Pro',
    'max' => 'Max',
    'team' => 'Team',
    'enterprise' => 'Enterprise',
    _ => normalized,
  };
}

/// 过去时长同样压成 `1m` / `2h` / `4d`，只保留一个量级。
String _compactSpan(Duration elapsed) {
  if (elapsed.inHours < 1) {
    return '${elapsed.inMinutes}m';
  }
  if (elapsed.inDays < 1) {
    return '${elapsed.inHours}h';
  }
  return '${elapsed.inDays}d';
}

String _ageLabel(DateTime? value, DateTime now, {bool oldData = false}) {
  if (value == null) {
    return oldData ? '旧数据' : '尚未刷新';
  }
  final difference = now.difference(value);
  if (difference.inMinutes < 1) {
    return oldData ? '刚才的数据' : '刚刚已刷新';
  }
  final span = _compactSpan(difference);
  return oldData ? '$span 前的数据' : '$span 前已刷新';
}

String _latestSubtitle(AppController controller) {
  final successful = controller.providers
      .map((state) => state.lastSuccessAt)
      .whereType<DateTime>()
      .toList(growable: false);
  if (successful.isEmpty) {
    return '尚未刷新';
  }
  final hasStale = controller.providers.any(
    (state) => state.freshness == SnapshotFreshness.stale,
  );
  final representative = successful.reduce((left, right) {
    if (hasStale) {
      return left.isBefore(right) ? left : right;
    }
    return left.isAfter(right) ? left : right;
  });
  return _ageLabel(representative, controller.now);
}

bool _isLive(AppController controller) {
  return controller.providers.any(
    (state) => state.freshness == SnapshotFreshness.live,
  );
}

Color _statusColor(BuildContext context, AppController controller) {
  if (controller.providers.any(
    (state) => state.freshness == SnapshotFreshness.stale,
  )) {
    return context.palette.warning;
  }
  if (_isLive(controller)) {
    return context.palette.success;
  }
  return context.palette.default400;
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
