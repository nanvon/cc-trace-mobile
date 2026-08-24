import 'dart:async';
import 'dart:io';

import 'loopback_bindings.dart';
import 'oauth_config.dart';
import 'oauth_diagnostics.dart';
import 'oauth_return_page.dart';

enum OAuthCallbackKind { accepted, providerCancelled, invalid, serverError }

class OAuthCallbackEvent {
  const OAuthCallbackEvent._(this.kind, {this.authorizationCode});

  const OAuthCallbackEvent.accepted(String code)
    : this._(OAuthCallbackKind.accepted, authorizationCode: code);

  const OAuthCallbackEvent.providerCancelled()
    : this._(OAuthCallbackKind.providerCancelled);

  const OAuthCallbackEvent.invalid() : this._(OAuthCallbackKind.invalid);

  const OAuthCallbackEvent.serverError()
    : this._(OAuthCallbackKind.serverError);

  final OAuthCallbackKind kind;
  final String? authorizationCode;

  @override
  String toString() => 'OAuthCallbackEvent($kind, <redacted>)';
}

class OAuthCallbackServer {
  OAuthCallbackServer._({
    required this._servers,
    required this.config,
    required this.expectedState,
  }) {
    _subscriptions = [
      for (final server in _servers)
        server.listen(
          _handle,
          onError: (_) => _emit(const OAuthCallbackEvent.serverError()),
          cancelOnError: false,
        ),
    ];
  }

  final List<HttpServer> _servers;
  final OAuthConfig config;
  final String expectedState;
  final StreamController<OAuthCallbackEvent> _events =
      StreamController<OAuthCallbackEvent>.broadcast(sync: true);
  late final List<StreamSubscription<HttpRequest>> _subscriptions;
  bool _closed = false;

  int get port => _servers.first.port;
  Stream<OAuthCallbackEvent> get events => _events.stream;

  static Future<OAuthCallbackServer> bind({
    required OAuthConfig config,
    required String expectedState,
  }) async {
    for (final port in config.ports) {
      try {
        final servers = await bindLoopbackServers(port);
        OAuthDiagnostics.instance.record('server.bound', {
          'port': servers.first.port,
          'listeners': servers.length,
        });
        return OAuthCallbackServer._(
          servers: servers,
          config: config,
          expectedState: expectedState,
        );
      } on SocketException {
        OAuthDiagnostics.instance.record('server.portBusy', {'port': port});
        continue;
      }
    }
    throw const SocketException('OAuth callback ports unavailable.');
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      // 只记录判定结果，绝不记录 query 内容：这份日志是给用户整份复制走的。
      OAuthDiagnostics.instance.record('callback.request', {
        'method.get': request.method == 'GET',
        'path.match': request.uri.path == config.callbackPath,
      });
      if (request.method != 'GET') {
        await _respond(request, false);
        _emit(const OAuthCallbackEvent.invalid());
        return;
      }
      final event = evaluateCallbackUri(request.uri);
      await _respond(request, event.kind == OAuthCallbackKind.accepted);
      if (event.kind == OAuthCallbackKind.accepted) {
        OAuthDiagnostics.instance.record('callback.accepted');
      }
      _emit(event);
    } on Object {
      try {
        await _respond(request, false);
      } on Object {
        // The response may already be closed. Never expose request details.
      }
      _emit(const OAuthCallbackEvent.serverError());
    }
  }

  /// 回调 URI 的唯一判定口径。HTTP 回调和 intent 回调共用，两条路的严格程度
  /// 必须完全一致，否则 intent 这条就成了绕过 state 校验的后门。
  OAuthCallbackEvent evaluateCallbackUri(Uri uri) {
    if (uri.path != config.callbackPath) {
      return const OAuthCallbackEvent.invalid();
    }
    final parameters = uri.queryParameters;
    final state = parameters['state'];
    if (state == null || state != expectedState) {
      return const OAuthCallbackEvent.invalid();
    }
    if (parameters.containsKey('error')) {
      return const OAuthCallbackEvent.providerCancelled();
    }
    final code = parameters['code'];
    if (code == null || code.isEmpty) {
      return const OAuthCallbackEvent.invalid();
    }
    return OAuthCallbackEvent.accepted(code);
  }

  /// 浏览器把 loopback 重定向交给系统 Resolver、用户再选回 CC Trace 时的入口。
  ///
  /// Firefox 一类浏览器会拦截 http 导航去问「用哪个应用打开」，此时 loopback
  /// server 收不到任何请求，授权码只能从这条 intent 通路回来。
  void acceptExternalCallback(Uri uri) {
    if (_closed) {
      return;
    }
    final event = evaluateCallbackUri(uri);
    // 只记判定结果，绝不记 query：这份日志是给用户整份复制走的。
    OAuthDiagnostics.instance.record('callback.intent', {
      'accepted': event.kind == OAuthCallbackKind.accepted,
    });
    _emit(event);
  }

  Future<void> _respond(HttpRequest request, bool success) async {
    final title = success ? '授权已收到' : '登录未完成';
    final message = success
        ? '可以关闭此页面，返回 CC Trace 就能看到额度。'
        : '请返回 CC Trace 后重试。';
    request.response
      ..statusCode = success ? HttpStatus.ok : HttpStatus.badRequest
      ..headers.contentType = ContentType.html
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
      ..headers.set('Pragma', 'no-cache')
      ..headers.set('X-Content-Type-Options', 'nosniff')
      ..headers.set(
        'Content-Security-Policy',
        "default-src 'none'; style-src 'unsafe-inline'; "
            "base-uri 'none'; form-action 'none'",
      )
      ..write(
        buildOAuthReturnPage(title: title, message: message, success: success),
      );
    await request.response.close();
  }

  void _emit(OAuthCallbackEvent event) {
    if (event.kind != OAuthCallbackKind.accepted) {
      OAuthDiagnostics.instance.record('callback.rejected', {
        'kind': event.kind.name,
      });
    }
    if (!_events.isClosed) {
      _events.add(event);
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    for (final server in _servers) {
      await server.close(force: true);
    }
    await _events.close();
  }
}
