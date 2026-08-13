import 'dart:async';
import 'dart:io';

import 'package:cc_trace_mobile/network/abortable_http.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('aborts the underlying connection after the timeout', () async {
    final serverSocket = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => serverSocket.close());
    final connectionSeen = Completer<void>();
    final connectionDropped = Completer<void>();

    serverSocket.listen((socket) {
      socket.listen(
        (data) {
          if (!connectionSeen.isCompleted) {
            connectionSeen.complete();
          }
        },
        onDone: () {
          if (!connectionDropped.isCompleted) {
            connectionDropped.complete();
          }
        },
        onError: (_) {
          if (!connectionDropped.isCompleted) {
            connectionDropped.complete();
          }
        },
      );
    });

    final client = http.Client();
    addTearDown(client.close);

    await expectLater(
      sendWithTimeout(
        client,
        http.Request('GET', Uri.parse('http://127.0.0.1:${serverSocket.port}/')),
        timeout: const Duration(milliseconds: 300),
      ),
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.duration,
          'duration',
          const Duration(milliseconds: 300),
        ),
      ),
    );

    await connectionSeen.future;
    await connectionDropped.future.timeout(const Duration(seconds: 5));
  });

  test('returns the response when the server answers in time', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.ok
        ..write('ok')
        ..close();
    });

    final client = http.Client();
    addTearDown(client.close);

    final response = await sendWithTimeout(
      client,
      http.Request('GET', Uri.parse('http://127.0.0.1:${server.port}/')),
      timeout: const Duration(seconds: 5),
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(response.body, 'ok');
  });

  test('surfaces a client-side abort as TimeoutException', () async {
    final client = MockClient((request) async {
      throw http.RequestAbortedException(request.url);
    });

    await expectLater(
      sendWithTimeout(
        client,
        http.Request('GET', Uri.parse('https://example.test/')),
        timeout: const Duration(seconds: 5),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('forwards method, headers and body unchanged', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://example.test/path');
      expect(request.headers['accept'], 'application/json');
      expect(request.headers['content-type'], 'application/json');
      expect(request.body, '{"hello":"world"}');
      return http.Response('ok', 200);
    });

    final response = await sendWithTimeout(
      client,
      http.Request('POST', Uri.parse('https://example.test/path'))
        ..headers.addAll({
          'accept': 'application/json',
          'content-type': 'application/json',
        })
        ..body = '{"hello":"world"}',
      timeout: const Duration(seconds: 5),
    );

    expect(response.statusCode, 200);
  });
}
