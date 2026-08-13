import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cc_trace_mobile/q3/browser_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.nanvon.cctrace.mobile/oauth_browser');

  void mockPlatform(Future<Object?> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  }

  test('release forwards to the platform release method', () async {
    final calls = <String>[];
    mockPlatform((call) async {
      calls.add(call.method);
      return null;
    });

    final bridge = OAuthBrowserBridge();
    await bridge.release();
    await bridge.dispose();

    expect(calls, ['release', 'release']);
  });

  test('release is best-effort when the platform fails', () async {
    mockPlatform((call) async {
      if (call.method == 'release') {
        throw PlatformException(code: 'RELEASE_FAILED');
      }
      return null;
    });

    final bridge = OAuthBrowserBridge();
    await bridge.release();
    await bridge.dispose();
  });

  test('release is best-effort when the platform channel is gone', () async {
    mockPlatform((call) async {
      throw MissingPluginException('no implementation');
    });

    final bridge = OAuthBrowserBridge();
    await bridge.release();
    await bridge.dispose();
  });
}
