import '../domain/quota_models.dart';

class OAuthConfig {
  const OAuthConfig({
    required this.provider,
    required this.authorizeEndpoint,
    required this.tokenEndpoint,
    required this.usageEndpoint,
    required this.clientId,
    required this.scopes,
    required this.callbackPath,
    required this.ports,
    required this.extraAuthorizeParameters,
  });

  final ProviderId provider;
  final String authorizeEndpoint;
  final String tokenEndpoint;
  final String usageEndpoint;
  final String clientId;
  final String scopes;
  final String callbackPath;
  final List<int> ports;
  final Map<String, String> extraAuthorizeParameters;

  Uri redirectUri(int port) {
    return Uri.parse('http://localhost:$port$callbackPath');
  }

  Uri authorizeUri({
    required int port,
    required String state,
    required String challenge,
  }) {
    return Uri.parse(authorizeEndpoint).replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirectUri(port).toString(),
        'scope': scopes,
        'code_challenge_method': 'S256',
        'code_challenge': challenge,
        'state': state,
        ...extraAuthorizeParameters,
      },
    );
  }
}

const providerConfigs = <ProviderId, OAuthConfig>{
  ProviderId.codex: OAuthConfig(
    provider: ProviderId.codex,
    authorizeEndpoint: 'https://auth.openai.com/oauth/authorize',
    tokenEndpoint: 'https://auth.openai.com/oauth/token',
    usageEndpoint: 'https://chatgpt.com/backend-api/wham/usage',
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
  ProviderId.claude: OAuthConfig(
    provider: ProviderId.claude,
    authorizeEndpoint: 'https://claude.com/cai/oauth/authorize',
    tokenEndpoint: 'https://platform.claude.com/v1/oauth/token',
    usageEndpoint: 'https://api.anthropic.com/api/oauth/usage',
    clientId: '9d1c250a-e61b-44d9-88ed-5944d1962f5e',
    scopes:
        'org:create_api_key user:profile user:inference '
        'user:sessions:claude_code user:mcp_servers user:file_upload',
    callbackPath: '/callback',
    ports: [41999],
    extraAuthorizeParameters: {'code': 'true'},
  ),
};

const resetCreditsEndpoint =
    'https://chatgpt.com/backend-api/wham/rate-limit-reset-credits';
