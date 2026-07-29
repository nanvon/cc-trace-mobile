import 'package:flutter/material.dart';

import 'q3_controller.dart';
import 'q3_provider.dart';

class Q3Screen extends StatefulWidget {
  const Q3Screen({super.key});

  @override
  State<Q3Screen> createState() => _Q3ScreenState();
}

class _Q3ScreenState extends State<Q3Screen> {
  late final Q3Controller _controller;

  @override
  void initState() {
    super.initState();
    _controller = Q3Controller();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Q3 Loopback 验证')),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Q3 验证工具，不交换 token',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                const Text('authorization code 只判断是否存在，不显示、不记录、不持久化。'),
                const SizedBox(height: 20),
                SegmentedButton<Q3Provider>(
                  segments: const [
                    ButtonSegment(
                      value: Q3Provider.codex,
                      label: Text('Codex'),
                    ),
                    ButtonSegment(
                      value: Q3Provider.claude,
                      label: Text('Claude'),
                    ),
                  ],
                  selected: {_controller.provider},
                  onSelectionChanged: _controller.isActive
                      ? null
                      : (selection) {
                          _controller.selectProvider(selection.first);
                        },
                ),
                const SizedBox(height: 16),
                _StatusCard(controller: _controller),
                const SizedBox(height: 20),
                Text(
                  '真实 Provider',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: _controller.isActive
                          ? null
                          : () => _controller.startProvider(),
                      child: const Text('启动授权'),
                    ),
                    if (_controller.provider == Q3Provider.codex)
                      OutlinedButton(
                        onPressed: _controller.isActive
                            ? null
                            : () => _controller.startProvider(
                                selectedPortMode: Q3PortMode.occupyCodexPrimary,
                              ),
                        child: const Text('预占 1455 后启动'),
                      ),
                    if (_controller.provider == Q3Provider.codex)
                      OutlinedButton(
                        onPressed: _controller.isActive
                            ? null
                            : () => _controller.startProvider(
                                selectedPortMode: Q3PortMode.occupyCodexAll,
                              ),
                        child: const Text('预占 1455 / 1457'),
                      ),
                    OutlinedButton(
                      onPressed: _controller.phase == Q3Phase.browserOpen
                          ? _controller.cancelCurrent
                          : null,
                      child: const Text('取消当前等待'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('本地故障注入', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text('每项都会新建一轮 listener，不打开 Provider 页面。'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _controller.isActive
                          ? null
                          : () => _controller.runSyntheticScenario(
                              Q3SyntheticScenario.duplicate,
                            ),
                      child: const Text('合法回调 × 2'),
                    ),
                    OutlinedButton(
                      onPressed: _controller.isActive
                          ? null
                          : () => _controller.runSyntheticScenario(
                              Q3SyntheticScenario.wrongStateThenValid,
                            ),
                      child: const Text('错误 state → 合法'),
                    ),
                    OutlinedButton(
                      onPressed: _controller.isActive
                          ? null
                          : () => _controller.runSyntheticScenario(
                              Q3SyntheticScenario.missingCodeThenValid,
                            ),
                      child: const Text('缺少 code → 合法'),
                    ),
                    OutlinedButton(
                      onPressed: _controller.isActive
                          ? null
                          : () => _controller.runSyntheticScenario(
                              Q3SyntheticScenario.cancelThenLateCallback,
                            ),
                      child: const Text('取消 → late callback'),
                    ),
                    OutlinedButton(
                      onPressed: _controller.isActive
                          ? null
                          : () => _controller.runSyntheticScenario(
                              Q3SyntheticScenario.successThenBrowserReturn,
                            ),
                      child: const Text('成功 → 浏览器返回'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller});

  final Q3Controller controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _StatusRow(label: '阶段', value: controller.phase.label),
            _StatusRow(
              label: '轮次',
              value: controller.runKind == Q3RunKind.provider
                  ? '真实 Provider'
                  : '本地 synthetic',
            ),
            _StatusRow(
              label: '监听端口',
              value: controller.port?.toString() ?? '—',
            ),
            _StatusRow(
              label: 'state 匹配',
              value: _booleanLabel(controller.stateMatches),
            ),
            _StatusRow(
              label: 'code 存在',
              value: _booleanLabel(controller.codePresent),
            ),
            _StatusRow(
              label: 'callback / duplicate',
              value:
                  '${controller.callbackCount} / '
                  '${controller.duplicateCount}',
            ),
            _StatusRow(
              label: 'late event',
              value: controller.lateEventCount.toString(),
            ),
            _StatusRow(label: '耗时', value: '${controller.elapsed.inSeconds}s'),
            _StatusRow(label: '错误类别', value: controller.errorCategory ?? '—'),
          ],
        ),
      ),
    );
  }

  String _booleanLabel(bool? value) {
    return switch (value) {
      true => '是',
      false => '否',
      null => '—',
    };
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
