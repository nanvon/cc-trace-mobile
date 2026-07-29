import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class OAuthMaterial {
  const OAuthMaterial({
    required this.state,
    required this.verifier,
    required this.challenge,
  });

  final String state;
  final String verifier;
  final String challenge;

  @override
  String toString() => 'OAuthMaterial(<redacted>)';
}

OAuthMaterial createOAuthMaterial() {
  final state = _secureRandomBase64Url(32);
  final verifier = _secureRandomBase64Url(64);
  final digest = sha256.convert(utf8.encode(verifier)).bytes;
  return OAuthMaterial(
    state: state,
    verifier: verifier,
    challenge: base64UrlEncode(digest).replaceAll('=', ''),
  );
}

String _secureRandomBase64Url(int byteCount) {
  final random = Random.secure();
  final bytes = List<int>.generate(
    byteCount,
    (_) => random.nextInt(256),
    growable: false,
  );
  return base64UrlEncode(bytes).replaceAll('=', '');
}
