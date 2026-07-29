import 'dart:async';
import 'dart:io';

import '../auth/loopback_bindings.dart';
import '../auth/oauth_return_page.dart';
import 'q3_provider.dart';

enum Q3CallbackKind {
  accepted,
  providerError,
  stateMismatch,
  missingState,
  missingCode,
  invalidMethod,
  invalidPath,
  serverError,
}

class Q3CallbackEvent {
  const Q3CallbackEvent({
    required this.kind,
    this.stateMatches,
    this.codePresent,
  });

  final Q3CallbackKind kind;
  final bool? stateMatches;
  final bool? codePresent;
}

class Q3LoopbackServer {
  Q3LoopbackServer._({
    required this._servers,
    required this.config,
    required this.expectedState,
  }) {
    _subscriptions = [
      for (final server in _servers)
        server.listen(
          _handleRequest,
          onError: (_) {
            if (!_events.isClosed) {
              _events.add(
                const Q3CallbackEvent(kind: Q3CallbackKind.serverError),
              );
            }
          },
          cancelOnError: false,
        ),
    ];
  }

  final List<HttpServer> _servers;
  final Q3ProviderConfig config;
  final String expectedState;
  final StreamController<Q3CallbackEvent> _events =
      StreamController<Q3CallbackEvent>.broadcast(sync: true);

  late final List<StreamSubscription<HttpRequest>> _subscriptions;
  bool _closed = false;

  int get port => _servers.first.port;

  Stream<Q3CallbackEvent> get events => _events.stream;

  static Future<Q3LoopbackServer> bind({
    required Q3ProviderConfig config,
    required String expectedState,
  }) async {
    for (final port in config.ports) {
      try {
        final servers = await bindLoopbackServers(port);
        return Q3LoopbackServer._(
          servers: servers,
          config: config,
          expectedState: expectedState,
        );
      } on SocketException {
        continue;
      }
    }

    throw const SocketException('Provider callback ports are unavailable.');
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.method != 'GET') {
        await _respond(
          request,
          statusCode: HttpStatus.methodNotAllowed,
          title: '无效回调',
          message: '只接受 Provider 发起的 GET 回调。',
        );
        _emit(const Q3CallbackEvent(kind: Q3CallbackKind.invalidMethod));
        return;
      }

      if (request.uri.path != config.callbackPath) {
        await _respond(
          request,
          statusCode: HttpStatus.notFound,
          title: '无效回调',
          message: '回调路径不匹配，请返回应用重试。',
        );
        _emit(const Q3CallbackEvent(kind: Q3CallbackKind.invalidPath));
        return;
      }

      final parameters = request.uri.queryParameters;
      final callbackState = parameters['state'];
      if (callbackState == null || callbackState.isEmpty) {
        await _respond(
          request,
          statusCode: HttpStatus.badRequest,
          title: '无效回调',
          message: '回调缺少必要校验，请返回应用重试。',
        );
        _emit(
          const Q3CallbackEvent(
            kind: Q3CallbackKind.missingState,
            stateMatches: false,
          ),
        );
        return;
      }

      if (callbackState != expectedState) {
        await _respond(
          request,
          statusCode: HttpStatus.badRequest,
          title: '无效回调',
          message: '回调校验失败，请返回应用重试。',
        );
        _emit(
          const Q3CallbackEvent(
            kind: Q3CallbackKind.stateMismatch,
            stateMatches: false,
          ),
        );
        return;
      }

      if (parameters.containsKey('error')) {
        await _respond(
          request,
          statusCode: HttpStatus.badRequest,
          title: '授权未完成',
          message: '授权已取消或未被 Provider 接受，请返回应用。',
        );
        _emit(
          const Q3CallbackEvent(
            kind: Q3CallbackKind.providerError,
            stateMatches: true,
            codePresent: false,
          ),
        );
        return;
      }

      final codePresent = parameters['code']?.isNotEmpty ?? false;
      if (!codePresent) {
        await _respond(
          request,
          statusCode: HttpStatus.badRequest,
          title: '无效回调',
          message: '回调缺少授权结果，请返回应用重试。',
        );
        _emit(
          const Q3CallbackEvent(
            kind: Q3CallbackKind.missingCode,
            stateMatches: true,
            codePresent: false,
          ),
        );
        return;
      }

      await _respond(
        request,
        statusCode: HttpStatus.ok,
        title: '授权回调已接收',
        message: 'CC Trace Mobile 未交换授权码，可以返回应用。',
        offerReturnToApp: true,
      );
      _emit(
        const Q3CallbackEvent(
          kind: Q3CallbackKind.accepted,
          stateMatches: true,
          codePresent: true,
        ),
      );
    } on Object {
      try {
        await _respond(
          request,
          statusCode: HttpStatus.internalServerError,
          title: '回调处理失败',
          message: '本地验证工具未能处理回调，请返回应用。',
        );
      } on Object {
        // The response may already be closed. Never surface request details.
      }
      _emit(const Q3CallbackEvent(kind: Q3CallbackKind.serverError));
    }
  }

  Future<void> _respond(
    HttpRequest request, {
    required int statusCode,
    required String title,
    required String message,
    bool offerReturnToApp = false,
  }) async {
    final response = request.response;
    response.statusCode = statusCode;
    response.headers
      ..contentType = ContentType.html
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('Pragma', 'no-cache')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set(
        'Content-Security-Policy',
        "default-src 'none'; style-src 'unsafe-inline'; "
            "base-uri 'none'; form-action 'none'",
      );
    response.write(
      buildOAuthReturnPage(
        title: title,
        message: message,
        success: offerReturnToApp,
      ),
    );
    await response.close();
  }

  void _emit(Q3CallbackEvent event) {
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
