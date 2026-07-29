import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class Q3AuthorizeMaterial {
  const Q3AuthorizeMaterial({required this.state, required this.codeChallenge});

  final String state;
  final String codeChallenge;
}

Q3AuthorizeMaterial createQ3AuthorizeMaterial() {
  final state = _secureRandomBase64Url(32);
  final verifier = _secureRandomBase64Url(64);
  final challengeBytes = sha256.convert(utf8.encode(verifier)).bytes;

  return Q3AuthorizeMaterial(
    state: state,
    codeChallenge: base64UrlEncode(challengeBytes).replaceAll('=', ''),
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
