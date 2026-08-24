import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../auth/oauth_coordinator.dart';
import '../domain/quota_models.dart';
import '../q3/browser_bridge.dart';
import 'app_theme.dart';

/// 登录期间的唯一交互入口。
///
/// 一个不可误触关闭的底部面板，串起「选浏览器 → 等待 → 收敛」三段：
/// 选浏览器每次都做（不记住上次选择），等待期间始终有取消，回到应用而回调
/// 还没到时给出换浏览器重试，而不是让用户对着转圈干等到超时。
Future<void> startSignIn(
  BuildContext context,
  AppController controller,
  ProviderId provider,
) async {
  if (controller.authorizing != null) {
    return;
  }
  final session = SignInSession();
  // 先发起：`signIn` 在第一个 await 之前就会把 authorizing 置位，
  // 面板据此判断自己该不该立刻自闭。
  final flow = controller.signIn(provider, selector: session.choose);
  await showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SignInSheet(
      controller: controller,
      session: session,
      provider: provider,
    ),
  );
  await flow;
  session.dispose();
}

/// 把 coordinator 的「请用户选浏览器」请求接到面板上。
class SignInSession extends ChangeNotifier {
  List<BrowserChoice>? _choices;
  Completer<BrowserChoice?>? _picker;

  List<BrowserChoice>? get choices => _choices;

  Future<BrowserChoice?> choose(List<BrowserChoice> choices) {
    _picker?.complete(null);
    final completer = Completer<BrowserChoice?>();
    _choices = choices;
    _picker = completer;
    notifyListeners();
    return completer.future;
  }

  void pick(BrowserChoice? choice) {
    final completer = _picker;
    _picker = null;
    _choices = null;
    notifyListeners();
    if (completer != null && !completer.isCompleted) {
      completer.complete(choice);
    }
  }

  @override
  void dispose() {
    _picker?.complete(null);
    _picker = null;
    super.dispose();
  }
}

class _SignInSheet extends StatefulWidget {
  const _SignInSheet({
    required this.controller,
    required this.session,
    required this.provider,
  });

  final AppController controller;
  final SignInSession session;
  final ProviderId provider;

  @override
  State<_SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends State<_SignInSheet> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    widget.session.addListener(_onSessionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _closeIfFinished());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    widget.session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    _closeIfFinished();
  }

  void _onSessionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _closeIfFinished() {
    if (!mounted || widget.controller.authorizing == widget.provider) {
      return;
    }
    // 收敛通知可能落在一帧的构建过程中，推迟到帧末再关，避免在构建期间弹路由。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.controller.authorizing != widget.provider) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final choices = widget.session.choices;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _cancel();
        }
      },
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          decoration: BoxDecoration(
            color: context.palette.content1,
            borderRadius: BorderRadius.circular(20),
          ),
          child: choices != null
              ? _BrowserPicker(
                  provider: widget.provider,
                  choices: choices,
                  onPick: widget.session.pick,
                )
              : _WaitingPanel(
                  provider: widget.provider,
                  phase: widget.controller.authPhase,
                  onRetry: _retry,
                  onCancel: _cancel,
                ),
        ),
      ),
    );
  }

  void _cancel() {
    widget.session.pick(null);
    widget.controller.cancelSignIn();
  }

  void _retry() {
    unawaited(
      widget.controller.reopenSignInBrowser(selector: widget.session.choose),
    );
  }
}

class _BrowserPicker extends StatelessWidget {
  const _BrowserPicker({
    required this.provider,
    required this.choices,
    required this.onPick,
  });

  final ProviderId provider;
  final List<BrowserChoice> choices;
  final ValueChanged<BrowserChoice?> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '用哪个浏览器登录 ${provider.displayName}？',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          '挑一个你已经登录过 ${provider.displayName} 的浏览器，能省掉一次登录，也更不容易卡在空白页。',
          style: TextStyle(
            color: context.palette.default500,
            fontSize: 12.5,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: choices.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final choice = choices[index];
              return _BrowserRow(choice: choice, onTap: () => onPick(choice));
            },
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => onPick(null),
            child: const Text('取消'),
          ),
        ),
      ],
    );
  }
}

class _BrowserRow extends StatelessWidget {
  const _BrowserRow({required this.choice, required this.onTap});

  final BrowserChoice choice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.palette.content2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      choice.label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (choice.isDefault) '系统默认',
                        if (choice.supportsCustomTabs) '内置登录页' else '外部浏览器',
                      ].join(' · '),
                      style: TextStyle(
                        color: context.palette.default500,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: context.palette.default400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WaitingPanel extends StatelessWidget {
  const _WaitingPanel({
    required this.provider,
    required this.phase,
    required this.onRetry,
    required this.onCancel,
  });

  final ProviderId provider;
  final OAuthPhase? phase;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final stalled = phase == OAuthPhase.returnedWithoutResult;
    final (title, message) = switch (phase) {
      OAuthPhase.returnedWithoutResult => (
        '还没收到登录结果',
        '如果还没在浏览器里登录完，切回去继续即可；如果页面一直空白或已经登录完却没反应，可以换个浏览器重试。',
      ),
      OAuthPhase.exchanging => ('正在完成登录…', '已收到授权，正在换取凭据。'),
      OAuthPhase.waitingInBrowser => (
        '已在浏览器中打开登录页',
        '登录完成后回到 CC Trace 就行，不用等浏览器自动跳转。',
      ),
      _ => ('正在准备登录…', '正在启动本机回调监听。'),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (stalled)
              Icon(
                Icons.help_outline_rounded,
                size: 20,
                color: context.palette.default500,
              )
            else
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          message,
          style: TextStyle(
            color: context.palette.default500,
            fontSize: 12.5,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: onCancel, child: const Text('取消登录')),
            if (stalled) ...[
              const SizedBox(width: 8),
              FilledButton(onPressed: onRetry, child: const Text('换个浏览器重试')),
            ],
          ],
        ),
      ],
    );
  }
}
