import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../diagnostics/app_diagnostics.dart';
import 'app_theme.dart';

/// 诊断日志页。
///
/// 真机上没有 USB / logcat 时，这是唯一能把登录、刷新和异常的实际走向带出来的
/// 通道。内容只有事件名与判定结果，不含凭据、授权码、邮箱或响应体，可整份复制
/// 后交给开发者。
class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key, this.diagnostics});

  final AppDiagnostics? diagnostics;

  @override
  Widget build(BuildContext context) {
    final diagnostics = this.diagnostics ?? AppDiagnostics.instance;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
        ),
        title: const Text(
          '诊断日志',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: '清空',
            onPressed: () => _confirmClear(context, diagnostics),
            icon: const Icon(Icons.delete_outline_rounded, size: 21),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: diagnostics,
        builder: (context, _) {
          final entries = diagnostics.entries;
          return Column(
            children: [
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            '还没有记录。\n登录、刷新用量和程序异常都会记在这里。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: context.palette.default500,
                              fontSize: 13,
                              height: 1.7,
                            ),
                          ),
                        ),
                      )
                    // 一整段日志可以到几百行。放进单个 SelectableText 会一次
                    // 性布局全部文本，滚动明显发涩；SelectionArea 让逐行构建的
                    // 列表同样能跨行选中复制。
                    : SelectionArea(
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final line = entries[index];
                            if (line.isEmpty) {
                              return const SizedBox(height: 12);
                            }
                            return Text(
                              line,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                height: 1.7,
                              ),
                            );
                          },
                        ),
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Column(
                    children: [
                      Text(
                        entries.isEmpty
                            ? '记录里只有事件名和判定结果，不含授权码、凭据或账号信息。'
                            : '共 ${entries.length} 行。记录里只有事件名和判定结果，'
                                  '不含授权码、凭据或账号信息。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.palette.default400,
                          fontSize: 11.5,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: entries.isEmpty
                              ? null
                              : () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: diagnostics.export()),
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('已复制诊断日志')),
                                    );
                                  }
                                },
                          child: const Text('复制全部'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 清空要确认：出问题时这里是唯一的现场，误触一下就没了。
  Future<void> _confirmClear(
    BuildContext context,
    AppDiagnostics diagnostics,
  ) async {
    if (diagnostics.isEmpty) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空诊断日志'),
        content: const Text('清空后无法恢复，正在排查的问题将失去现场记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      diagnostics.clear();
    }
  }
}
