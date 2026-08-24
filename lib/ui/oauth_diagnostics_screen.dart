import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/oauth_diagnostics.dart';
import 'app_theme.dart';

/// 登录诊断页。
///
/// 真机上没有 USB / logcat 时，这是唯一能把登录链路的实际走向带出来的通道。
/// 内容只有事件名与判定结果，不含 code、token、账号或回调 query，可整份复制。
class OAuthDiagnosticsScreen extends StatelessWidget {
  const OAuthDiagnosticsScreen({super.key, this.diagnostics});

  final OAuthDiagnostics? diagnostics;

  @override
  Widget build(BuildContext context) {
    final diagnostics = this.diagnostics ?? OAuthDiagnostics.instance;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
        ),
        title: const Text(
          '登录诊断',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: '清空',
            onPressed: diagnostics.clear,
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
                            '还没有登录记录。\n发起一次登录后，这里会记录每一步的结果。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: context.palette.default500,
                              fontSize: 13,
                              height: 1.7,
                            ),
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        children: [
                          SelectableText(
                            diagnostics.export(),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              height: 1.7,
                            ),
                          ),
                        ],
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Column(
                    children: [
                      Text(
                        '记录里只有事件名和判定结果，不含授权码、凭据或账号信息。',
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
                                      const SnackBar(
                                        content: Text('已复制登录诊断记录'),
                                      ),
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
}
