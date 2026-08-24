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

  test('browser choices survive the platform round trip', () async {
    mockPlatform((call) async {
      if (call.method == 'listBrowsers') {
        return [
          {
            'packageName': 'com.example.tabs',
            'label': 'Tabs',
            'supportsCustomTabs': true,
            'isDefault': false,
          },
          // 缺 packageName 的条目必须被丢弃，不能变成一个点不动的选项。
          {'label': 'Broken'},
        ];
      }
      return null;
    });

    final bridge = OAuthBrowserBridge();
    final choices = await bridge.listBrowsers();
    await bridge.dispose();

    expect(choices, hasLength(1));
    expect(choices.single.packageName, 'com.example.tabs');
    expect(choices.single.supportsCustomTabs, isTrue);
  });

  test('listBrowsers degrades to empty when the platform has none', () async {
    mockPlatform((call) async {
      throw MissingPluginException('no implementation');
    });

    final bridge = OAuthBrowserBridge();
    expect(await bridge.listBrowsers(), isEmpty);
    await bridge.dispose();
  });

  test('open passes the chosen browser package through', () async {
    Map<Object?, Object?>? arguments;
    mockPlatform((call) async {
      if (call.method == 'open') {
        arguments = call.arguments as Map<Object?, Object?>;
      }
      return null;
    });

    final bridge = OAuthBrowserBridge();
    await bridge.open(
      Uri.parse('https://claude.com/cai/oauth/authorize'),
      packageName: 'com.example.tabs',
    );
    await bridge.dispose();

    expect(arguments?['package'], 'com.example.tabs');
    expect(arguments?['url'], 'https://claude.com/cai/oauth/authorize');
  });

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
