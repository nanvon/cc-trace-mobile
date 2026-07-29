import 'package:cc_trace_mobile/auth/oauth_return_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'successful Android callback offers only a non-sensitive app return',
    () {
      final page = buildOAuthReturnPage(
        title: '登录已接收',
        message: '可以返回应用。',
        success: true,
        offerAndroidReturn: true,
      );

      expect(page, contains('cctrace://oauth-finished'));
      expect(page, contains('返回 CC Trace'));
      expect(page, isNot(contains('code=')));
      expect(page, isNot(contains('state=')));
      expect(page, isNot(contains('token')));
    },
  );

  test('failed callback never attempts to open the app', () {
    final page = buildOAuthReturnPage(
      title: '登录未完成',
      message: '请返回应用重试。',
      success: false,
      offerAndroidReturn: true,
    );

    expect(page, isNot(contains(oauthReturnUri)));
  });
}
