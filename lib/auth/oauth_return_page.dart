import 'dart:convert';
import 'dart:io';

const oauthReturnUri = 'cctrace://oauth-finished';

/// 回调落地页。
///
/// **不做自动跳转。** `<meta http-equiv="refresh">` 跳自定义 scheme 属于无用户手势的
/// 重定向，Chrome 一律拦截，部分浏览器还会弹出一个没有本应用的「打开方式」选择器。
/// 这里只留一个需要用户点击的按钮（有手势，浏览器才放行），并明确告诉用户：
/// 授权已经交给应用了，直接切回去即可，点不点按钮都不影响登录结果。
String buildOAuthReturnPage({
  required String title,
  required String message,
  required bool success,
  bool? offerAndroidReturn,
}) {
  final escapedTitle = const HtmlEscape().convert(title);
  final escapedMessage = const HtmlEscape().convert(message);
  final shouldOfferReturn =
      success && (offerAndroidReturn ?? Platform.isAndroid);
  final returnAction = shouldOfferReturn
      ? '''
    <p><a href="$oauthReturnUri">返回 CC Trace</a></p>
    <p class="hint">按钮无效也没关系：手动切回 CC Trace 同样能看到结果。</p>'''
      : '';

  return '''
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>$escapedTitle</title>
  <style>
    body { font: 16px -apple-system,BlinkMacSystemFont,sans-serif; padding: 32px; }
    main { max-width: 520px; margin: 0 auto; }
    a {
      display: inline-block;
      padding: 12px 18px;
      border-radius: 10px;
      background: #111827;
      color: #fff;
      text-decoration: none;
    }
    .hint { color: #6b7280; font-size: 14px; }
  </style>
</head>
<body>
  <main>
    <h1>$escapedTitle</h1>
    <p>$escapedMessage</p>
    $returnAction
  </main>
</body>
</html>
''';
}
