import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/quota_models.dart';

class TokenBundle {
  const TokenBundle({
    required this.provider,
    required this.accessToken,
    required this.refreshToken,
    required this.obtainedAt,
    this.idToken,
    this.expiresAt,
    this.accountId,
    this.accountHint,
    this.accountFingerprint,
  });

  final ProviderId provider;
  final String accessToken;
  final String refreshToken;
  final String? idToken;
  final DateTime obtainedAt;
  final DateTime? expiresAt;
  final String? accountId;
  final String? accountHint;
  final String? accountFingerprint;

  bool expiresWithin(DateTime now, Duration skew) {
    final expiry = expiresAt;
    return expiry != null && !expiry.isAfter(now.add(skew));
  }

  /// Compares only the bearer material that authorizes requests.
  ///
  /// This is deliberately not an object equality check: timestamps and parsed
  /// account hints may legitimately change while the same credential remains
  /// current. It is used by secure storage's compare-and-replace protection so
  /// an in-flight refresh cannot overwrite a later sign-in or sign-out.
  bool hasSameAuthMaterialAs(TokenBundle other) {
    return provider == other.provider &&
        accessToken == other.accessToken &&
        refreshToken == other.refreshToken &&
        idToken == other.idToken;
  }

  String? get identityKey {
    final value = accountId;
    if (value != null && value.isNotEmpty) {
      return _fingerprint(value);
    }
    if (accountFingerprint != null && accountFingerprint!.isNotEmpty) {
      return accountFingerprint;
    }
    final hint = accountHint;
    if (hint == null || hint.isEmpty) {
      return null;
    }
    return _fingerprint(hint);
  }

  TokenBundle copyWith({
    String? accessToken,
    String? refreshToken,
    String? idToken,
    DateTime? obtainedAt,
    DateTime? expiresAt,
    String? accountId,
    String? accountHint,
    String? accountFingerprint,
  }) {
    return TokenBundle(
      provider: provider,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      idToken: idToken ?? this.idToken,
      obtainedAt: obtainedAt ?? this.obtainedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      accountId: accountId ?? this.accountId,
      accountHint: accountHint ?? this.accountHint,
      accountFingerprint: accountFingerprint ?? this.accountFingerprint,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': 1,
      'provider': provider.name,
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'idToken': idToken,
      'obtainedAt': obtainedAt.toUtc().toIso8601String(),
      'expiresAt': expiresAt?.toUtc().toIso8601String(),
      'accountId': accountId,
      'accountHint': accountHint,
      'accountFingerprint': accountFingerprint,
    };
  }

  factory TokenBundle.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported credential schema.');
    }
    return TokenBundle(
      provider: ProviderId.values.firstWhere(
        (provider) => provider.name == json['provider'],
      ),
      accessToken: json['accessToken']! as String,
      refreshToken: json['refreshToken']! as String,
      idToken: json['idToken'] as String?,
      obtainedAt: DateTime.parse(json['obtainedAt']! as String),
      expiresAt: json['expiresAt'] is String
          ? DateTime.parse(json['expiresAt']! as String)
          : null,
      accountId: json['accountId'] as String?,
      accountHint: json['accountHint'] as String?,
      accountFingerprint: json['accountFingerprint'] as String?,
    );
  }

  @override
  String toString() => 'TokenBundle(${provider.name}, <redacted>)';
}

Map<String, Object?>? decodeJwtPayload(String? token) {
  if (token == null) {
    return null;
  }
  final parts = token.split('.');
  if (parts.length != 3) {
    return null;
  }
  try {
    final normalized = base64Url.normalize(parts[1]);
    final value = jsonDecode(utf8.decode(base64Url.decode(normalized)));
    return value is Map<String, Object?> ? value : null;
  } on Object {
    return null;
  }
}

String? jwtStringClaim(Map<String, Object?>? payload, String name) {
  final direct = payload?[name];
  if (direct is String && direct.isNotEmpty) {
    return direct;
  }
  final namespace = payload?['https://api.openai.com/auth'];
  if (namespace is Map<String, Object?>) {
    final nested = namespace[name];
    if (nested is String && nested.isNotEmpty) {
      return nested;
    }
  }
  return null;
}

DateTime? jwtExpiry(Map<String, Object?>? payload) {
  final exp = payload?['exp'];
  return exp is num
      ? DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true)
      : null;
}

String? maskedEmailFromPayload(Map<String, Object?>? payload) {
  final email = jwtStringClaim(payload, 'email');
  if (email == null) {
    return null;
  }
  final at = email.indexOf('@');
  if (at <= 0) {
    return null;
  }
  final local = email.substring(0, at);
  final prefix = local.length <= 2
      ? local.substring(0, 1)
      : local.substring(0, 2);
  return '$prefix•••${email.substring(at)}';
}

String? identityFingerprintFromPayloads(
  Map<String, Object?>? primary,
  Map<String, Object?>? secondary,
) {
  final identity =
      jwtStringClaim(primary, 'sub') ??
      jwtStringClaim(secondary, 'sub') ??
      jwtStringClaim(primary, 'email') ??
      jwtStringClaim(secondary, 'email');
  return identity == null || identity.isEmpty ? null : _fingerprint(identity);
}

String _fingerprint(String value) {
  return sha256.convert(utf8.encode(value)).toString().substring(0, 16);
}
