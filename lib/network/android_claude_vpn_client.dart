import 'dart:async';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Android 的 Claude 刷新传输。原生侧选取 VPN 并约束 DNS 和连接。
final class AndroidClaudeVpnClient extends http.BaseClient {
  static const _channel = MethodChannel('com.nanvon.cctrace.mobile/claude_vpn');
  static int _nextRequestId = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final id = _nextRequestId++;
    final body = await request.finalize().toBytes();
    final abort = request is http.Abortable ? request.abortTrigger : null;
    var finished = false;
    try {
      final pending = _channel.invokeMapMethod<String, Object?>('send', {
        'id': id,
        'method': request.method,
        'url': request.url.toString(),
        'headers': request.headers,
        'body': body,
      });
      final response = abort == null
          ? await pending
          : await Future.any([
              pending,
              abort.then<Map<String, Object?>?>((_) {
                if (!finished) {
                  unawaited(_cancel(id));
                }
                throw http.RequestAbortedException(request.url);
              }),
            ]);
      if (response == null) {
        throw http.ClientException('VPN transport returned no response');
      }
      return http.StreamedResponse(
        Stream.value(response['body'] as Uint8List),
        response['status'] as int,
        headers: (response['headers'] as Map).cast<String, String>(),
        request: request,
      );
    } on PlatformException catch (error) {
      throw http.ClientException(error.code);
    } on MissingPluginException {
      throw http.ClientException('VPN transport unavailable');
    } finally {
      finished = true;
    }
  }

  Future<void> _cancel(int id) async {
    try {
      await _channel.invokeMethod<void>('cancel', id);
    } on PlatformException {
      // 原生请求也有独立超时。
    } on MissingPluginException {
      // 引擎拆除时原生侧会取消其请求。
    }
  }
}
