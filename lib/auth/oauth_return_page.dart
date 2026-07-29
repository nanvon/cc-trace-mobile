import 'dart:convert';
import 'dart:io';

const oauthReturnUri = 'cctrace://oauth-finished';

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
  final returnMetadata = shouldOfferReturn
      ? '<meta http-equiv="refresh" content="0;url=$oauthReturnUri">'
      : '';
  final returnAction = shouldOfferReturn
      ? '''
    <p><a href="$oauthReturnUri">返回 CC Trace</a></p>
    <p class="hint">如果没有自动返回，请点击上方按钮。</p>'''
      : '';

  return '''
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  $returnMetadata
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
