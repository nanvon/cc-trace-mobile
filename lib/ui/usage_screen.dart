import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

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
        final palette = context.palette;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: isDark ? palette.background : palette.content2,
            statusBarIconBrightness: isDark
                ? Brightness.light
                : Brightness.dark,
            statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
            systemStatusBarContrastEnforced: false,
          ),
          child: Scaffold(
            body: SafeArea(
              bottom: false,
              child: controller.initialized && controller.allSignedOut
                  ? _Onboarding(controller: controller)
                  : _UsageContent(controller: controller),
            ),
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
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: context.palette.default500,
                        fontSize: 13,
                      ),
                    ),
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
    final primaryAvailable = primary == null
        ? false
        : _windowHasUsableQuota(primary);
    final primaryNotStarted = primary != null && _windowNotStarted(primary);
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
            Semantics(
              button: canExpand,
              expanded: canExpand ? _expanded : null,
              hint: canExpand ? (_expanded ? '轻点收起时间明细' : '轻点展开时间明细') : null,
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
                      Row(
                        children: [
                          Text(
                            state.provider.displayName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.27,
                            ),
                          ),
                          if (state.identity?.plan case final String plan) ...[
                            const SizedBox(width: 8),
                            _PlanChip(_planLabel(plan)),
                          ],
                          const Spacer(),
                          Flexible(
                            child: Text(
                              state.isSignedIn
                                  ? state.identity?.accountHint ?? '已登录'
                                  : '未登录',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                color: context.palette.default500,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (canExpand) ...[
                            const SizedBox(width: 4),
                            ExcludeSemantics(
                              child: SizedBox.square(
                                dimension: 28,
                                child: RotationTransition(
                                  turns: Tween<double>(
                                    begin: 0,
                                    end: .5,
                                  ).animate(_expansion),
                                  child: Icon(
                                    Icons.expand_more_rounded,
                                    size: 22,
                                    color: context.palette.default500,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (primary != null) ...[
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              primaryAvailable
                                  ? '${_whole(primary.remainingPercent)}%'
                                  : '--',
                              style: TextStyle(
                                color: !primaryAvailable
                                    ? context.palette.default400
                                    : stale
                                    ? context.palette.foreground
                                    : _quotaColor(
                                        context,
                                        primary.remainingPercent,
                                      ),
                                fontSize: 38,
                                fontWeight: FontWeight.w700,
                                height: .95,
                                letterSpacing: -1.5,
                              ),
                            ),
                            const SizedBox(width: 9),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                _windowLabel(primary),
                                style: TextStyle(
                                  color: context.palette.default500,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Flexible(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child:
                                    !primaryAvailable ||
                                        primaryNotStarted ||
                                        stale
                                    ? Text(
                                        !primaryAvailable
                                            ? '当前不可用'
                                            : primaryNotStarted
                                            ? '未开始'
                                            : _ageLabel(
                                                state.lastSuccessAt,
                                                controller.now,
                                                oldData: true,
                                              ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.end,
                                        style: TextStyle(
                                          color: context.palette.default500,
                                          fontSize: 13,
                                        ),
                                      )
                                    : _ResetCountdownText(
                                        resetsAt: primary.resetsAt,
                                        now: () => controller.now,
                                        textAlign: TextAlign.end,
                                        style: TextStyle(
                                          color: context.palette.default500,
                                          fontSize: 13,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 13),
                        _QuotaProgress(
                          percent: primaryAvailable
                              ? primary.remainingPercent
                              : 0,
                          color: !primaryAvailable
                              ? context.palette.default400
                              : stale
                              ? context.palette.default400
                              : _quotaColor(context, primary.remainingPercent),
                          height: 10,
                        ),
                      ] else ...[
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '--',
                              style: TextStyle(
                                color: context.palette.default400,
                                fontSize: 38,
                                fontWeight: FontWeight.w700,
                                height: .95,
                                letterSpacing: -1.5,
                              ),
                            ),
                            const SizedBox(width: 9),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                state.provider == ProviderId.codex
                                    ? '每周窗口'
                                    : '5 小时窗口',
                                style: TextStyle(
                                  color: context.palette.default500,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 13),
                        Text(
                          _emptyMessage(state),
                          style: TextStyle(
                            color: context.palette.default500,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      for (final window in secondary)
                        _QuotaSubRow(
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
                          child: _CodexTimeDetails(
                            windows: visibleWindows,
                            credits: state.resetCredits,
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

class _CodexTimeDetails extends StatelessWidget {
  const _CodexTimeDetails({
    required this.windows,
    required this.credits,
    required this.now,
  });

  final List<QuotaWindow> windows;
  final ResetCreditsSnapshot? credits;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final availableCredits =
        credits?.availableCredits ?? const <ResetCreditEntry>[];
    final expiryGroups = _groupCreditExpiries(availableCredits);
    final unavailableDetailCount = credits == null
        ? 0
        : credits!.availableCount > availableCredits.length
        ? credits!.availableCount - availableCredits.length
        : 0;

    return Container(
      margin: const EdgeInsets.only(top: 13),
      padding: const EdgeInsets.only(top: 13),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.palette.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '时间明细',
                style: TextStyle(
                  color: context.palette.foreground,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '本地时间',
                style: TextStyle(
                  color: context.palette.default400,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _TimeSectionLabel(label: '额度窗口'),
          if (windows.isEmpty)
            const _TimeDetailRow(label: '额度窗口', value: '暂时没有可用明细')
          else
            for (final window in windows)
              _TimeDetailRow(
                label: _windowLabel(window),
                value: _absoluteTimeLabel(
                  window.resetsAt,
                  now,
                  suffix: '重置',
                  unknown: '重置时间未知',
                ),
              ),
          const SizedBox(height: 9),
          _TimeSectionLabel(label: '重置次数'),
          if (credits == null)
            const _TimeDetailRow(label: '可用次数', value: '暂时无法读取')
          else if (credits!.availableCount == 0 && expiryGroups.isEmpty)
            const _TimeDetailRow(label: '可用次数', value: '当前没有可用次数')
          else if (expiryGroups.isEmpty)
            _TimeDetailRow(
              label: '${credits!.availableCount} 次',
              value: '接口未提供过期时间',
            )
          else ...[
            for (final group in expiryGroups)
              _TimeDetailRow(
                label: '${group.count} 次',
                value: _absoluteTimeLabel(
                  group.expiry,
                  now,
                  suffix: '过期',
                  unknown: '过期时间未知',
                ),
              ),
            if (unavailableDetailCount > 0)
              _TimeDetailRow(
                label: '$unavailableDetailCount 次',
                value: '接口未提供过期时间',
              ),
          ],
        ],
      ),
    );
  }
}

class _TimeSectionLabel extends StatelessWidget {
  const _TimeSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text(
        label,
        style: TextStyle(
          color: context.palette.default500,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TimeDetailRow extends StatelessWidget {
  const _TimeDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: context.palette.default600, fontSize: 12.5),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: context.palette.default500,
                fontSize: 12.5,
              ),
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
    required this.window,
    required this.stale,
    required this.now,
  });

  final QuotaWindow window;
  final bool stale;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final available = _windowHasUsableQuota(window);
    final notStarted = _windowNotStarted(window);
    final color = stale
        ? context.palette.default400
        : _quotaColor(context, window.remainingPercent);
    return Container(
      margin: const EdgeInsets.only(top: 13),
      padding: const EdgeInsets.only(top: 13),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: context.palette.divider,
            style: BorderStyle.solid,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            _windowLabel(window),
            style: TextStyle(
              color: available
                  ? context.palette.default500
                  : context.palette.default400,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QuotaProgress(
              percent: available ? window.remainingPercent : 0,
              color: color,
              height: 5,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            available ? '${_whole(window.remainingPercent)}%' : '--',
            style: TextStyle(
              color: available ? color : context.palette.default400,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          window.isActive
              ? _ResetCountdownText(
                  resetsAt: window.resetsAt,
                  now: now,
                  style: TextStyle(
                    color: context.palette.default500,
                    fontSize: 12,
                  ),
                )
              : Text(
                  notStarted ? '未开始' : '当前不可用',
                  style: TextStyle(
                    color: notStarted
                        ? context.palette.default500
                        : context.palette.default400,
                    fontSize: 12,
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
    return Container(
      margin: const EdgeInsets.only(top: 13),
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.palette.divider)),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: context.palette.default100,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.history_rounded,
              size: 14,
              color: context.palette.default500,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '重置次数',
            style: TextStyle(color: context.palette.default500, fontSize: 12.5),
          ),
          const SizedBox(width: 8),
          Text(
            credits == null ? '--' : '${credits!.availableCount} 次可用',
            style: TextStyle(
              color: credits == null
                  ? context.palette.default400
                  : context.palette.foreground,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (credits?.earliestExpiry != null) ...[
            const Spacer(),
            Text(
              '最早 ${credits!.earliestExpiry!.month}/${credits!.earliestExpiry!.day} 过期',
              style: TextStyle(color: context.palette.default500, fontSize: 12),
            ),
          ],
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
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              _Skeleton(width: 44, height: 22, radius: 999),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '--',
                style: TextStyle(
                  color: context.palette.default400,
                  fontSize: 38,
                  fontWeight: FontWeight.w700,
                  height: .95,
                ),
              ),
              const SizedBox(width: 9),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  provider == ProviderId.codex ? '每周窗口' : '5 小时窗口',
                  style: TextStyle(
                    color: context.palette.default500,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          const _Skeleton(width: double.infinity, height: 10, radius: 999),
          const SizedBox(height: 13),
          Text(
            '正在检查额度',
            style: TextStyle(color: context.palette.default500, fontSize: 13),
          ),
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

class _PlanChip extends StatelessWidget {
  const _PlanChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.palette.default100,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: context.palette.default600,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
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

String _windowLabel(QuotaWindow window) {
  return switch (window.kind) {
    QuotaWindowKind.fiveHour => '5 小时窗口',
    QuotaWindowKind.weekly => '每周窗口',
    QuotaWindowKind.modelWeekly => '${window.displayName ?? '模型'} 每周',
    QuotaWindowKind.unknown => window.displayName ?? '其他窗口',
  };
}

bool _canExpand(ProviderViewState state) {
  if (state.provider != ProviderId.codex) {
    return false;
  }
  final hasVisibleWindow =
      state.snapshot?.windows.any(
        (window) => window.kind != QuotaWindowKind.unknown,
      ) ??
      false;
  return hasVisibleWindow || state.resetCredits != null;
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

String _absoluteTimeLabel(
  DateTime? value,
  DateTime now, {
  required String suffix,
  required String unknown,
}) {
  if (value == null) {
    return unknown;
  }
  final local = value.toLocal();
  final localNow = now.toLocal();
  final date = local.year == localNow.year
      ? '${local.month}/${local.day}'
      : '${local.year}/${local.month}/${local.day}';
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$date $hour:$minute $suffix';
}

bool _windowNotStarted(QuotaWindow window) {
  return !window.isActive &&
      (window.kind == QuotaWindowKind.fiveHour ||
          window.kind == QuotaWindowKind.weekly);
}

bool _windowHasUsableQuota(QuotaWindow window) {
  return window.isActive || _windowNotStarted(window);
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

String _resetLabel(DateTime? reset, DateTime now) {
  if (reset == null) {
    return '重置时间未知';
  }
  final remainingMinutes = reset.difference(now).inMinutes;
  if (remainingMinutes < 1) {
    return '即将重置';
  }
  final days = remainingMinutes ~/ Duration.minutesPerDay;
  final hours = (remainingMinutes % Duration.minutesPerDay) ~/ 60;
  final minutes = remainingMinutes % 60;
  if (days > 0) {
    return hours > 0 ? '$days 天 $hours 小时后重置' : '$days 天后重置';
  }
  if (hours > 0) {
    return minutes > 0 ? '$hours 小时 $minutes 分钟后重置' : '$hours 小时后重置';
  }
  return '$minutes 分钟后重置';
}

String _planLabel(String value) {
  final normalized = value.trim();
  return switch (normalized.toLowerCase()) {
    'plus' => 'Plus',
    'pro' => 'Pro',
    'max' => 'Max',
    _ => normalized,
  };
}

String _ageLabel(DateTime? value, DateTime now, {bool oldData = false}) {
  if (value == null) {
    return oldData ? '旧数据' : '尚未成功刷新';
  }
  final difference = now.difference(value);
  if (difference.inMinutes < 1) {
    return oldData ? '刚才的数据' : '刚刚刷新';
  }
  if (difference.inHours < 1) {
    return oldData
        ? '${difference.inMinutes} 分钟前的数据'
        : '${difference.inMinutes} 分钟前刷新';
  }
  if (difference.inDays < 1) {
    return oldData
        ? '${difference.inHours} 小时前的数据'
        : '${difference.inHours} 小时前刷新';
  }
  return oldData ? '${difference.inDays} 天前的数据' : '${difference.inDays} 天前刷新';
}

String _latestSubtitle(AppController controller) {
  final successful = controller.providers
      .map((state) => state.lastSuccessAt)
      .whereType<DateTime>()
      .toList(growable: false);
  if (successful.isEmpty) {
    return '尚未成功刷新';
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
