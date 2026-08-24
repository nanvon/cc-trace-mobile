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
      if (request.method != 'GET' || request.uri.path != config.callbackPath) {
        await _respond(request, false);
        _emit(const OAuthCallbackEvent.invalid());
        return;
      }
      final parameters = request.uri.queryParameters;
      final state = parameters['state'];
      if (state == null || state != expectedState) {
        await _respond(request, false);
        _emit(const OAuthCallbackEvent.invalid());
        return;
      }
      if (parameters.containsKey('error')) {
        await _respond(request, false);
        _emit(const OAuthCallbackEvent.providerCancelled());
        return;
      }
      final code = parameters['code'];
      if (code == null || code.isEmpty) {
        await _respond(request, false);
        _emit(const OAuthCallbackEvent.invalid());
        return;
      }
      await _respond(request, true);
      OAuthDiagnostics.instance.record('callback.accepted');
      _emit(OAuthCallbackEvent.accepted(code));
    } on Object {
      try {
        await _respond(request, false);
      } on Object {
        // The response may already be closed. Never expose request details.
      }
      _emit(const OAuthCallbackEvent.serverError());
    }
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
