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
      // 自动跳转必被浏览器拦截，还会引出没有本应用的「打开方式」选择器：
      // 页面只保留需要用户点击的按钮。
      expect(page, isNot(contains('http-equiv="refresh"')));
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
