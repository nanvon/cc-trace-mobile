enum Q3Provider { codex, claude }

extension Q3ProviderDetails on Q3Provider {
  Q3ProviderConfig get config {
    return switch (this) {
      Q3Provider.codex => const Q3ProviderConfig(
        provider: Q3Provider.codex,
        displayName: 'Codex',
        authorizeEndpoint: 'https://auth.openai.com/oauth/authorize',
        clientId: 'app_EMoamEEZ73f0CkXaXp7hrann',
        scopes:
            'openid profile email offline_access '
            'api.connectors.read api.connectors.invoke',
        callbackPath: '/auth/callback',
        ports: [1455, 1457],
        extraAuthorizeParameters: {
          'id_token_add_organizations': 'true',
          'codex_cli_simplified_flow': 'true',
          'originator': 'codex_cli_rs',
        },
      ),
      Q3Provider.claude => const Q3ProviderConfig(
        provider: Q3Provider.claude,
        displayName: 'Claude',
        authorizeEndpoint: 'https://claude.com/cai/oauth/authorize',
        clientId: '9d1c250a-e61b-44d9-88ed-5944d1962f5e',
        scopes:
            'org:create_api_key user:profile user:inference '
            'user:sessions:claude_code user:mcp_servers user:file_upload',
        callbackPath: '/callback',
        ports: [41999],
        extraAuthorizeParameters: {'code': 'true'},
      ),
    };
  }
}

class Q3ProviderConfig {
  const Q3ProviderConfig({
    required this.provider,
    required this.displayName,
    required this.authorizeEndpoint,
    required this.clientId,
    required this.scopes,
    required this.callbackPath,
    required this.ports,
    required this.extraAuthorizeParameters,
  });

  final Q3Provider provider;
  final String displayName;
  final String authorizeEndpoint;
  final String clientId;
  final String scopes;
  final String callbackPath;
  final List<int> ports;
  final Map<String, String> extraAuthorizeParameters;

  Uri buildAuthorizeUri({
    required int port,
    required String state,
    required String codeChallenge,
  }) {
    final redirectUri = 'http://localhost:$port$callbackPath';
    final parameters = <String, String>{
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'scope': scopes,
      'code_challenge_method': 'S256',
      'code_challenge': codeChallenge,
      'state': state,
      ...extraAuthorizeParameters,
    };

    return Uri.parse(authorizeEndpoint).replace(queryParameters: parameters);
  }
}
