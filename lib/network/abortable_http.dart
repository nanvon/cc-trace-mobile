import 'dart:async';

import 'package:http/http.dart' as http;

/// 带真实取消的 HTTP 请求：超过 [timeout] 后中止底层连接。
///
/// 与 `Future.timeout` 不同，超时不只是让业务层停止等待，而是通过
/// `AbortableRequest` 让底层 client 终止实际请求（IOClient / BrowserClient
/// 支持 abort）。中止统一以 [TimeoutException] 呈现，调用方沿用现有超时
/// 映射，不新增错误分类。
///
/// 正常完成后超时 Timer 会被取消，不会对后续请求产生副作用。
Future<http.Response> sendWithTimeout(
  http.Client client,
  http.Request request, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final abort = Completer<void>();
  final timer = Timer(timeout, () {
    if (!abort.isCompleted) {
      abort.complete();
    }
  });
  try {
    final streamed = await client.send(
      http.AbortableRequest(request.method, request.url, abortTrigger: abort.future)
        ..headers.addAll(request.headers)
        ..bodyBytes = request.bodyBytes,
    );
    return await http.Response.fromStream(streamed);
  } on http.RequestAbortedException {
    throw TimeoutException('Request timed out after $timeout', timeout);
  } finally {
    timer.cancel();
  }
}
