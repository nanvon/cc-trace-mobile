import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'browser_bridge.dart';
import 'loopback_server.dart';
import 'pkce.dart';
import 'q3_provider.dart';

enum Q3Phase {
  idle,
  binding,
  browserOpen,
  callbackAccepted,
  cancelled,
  timeout,
  failed,
}

enum Q3RunKind { provider, synthetic }

enum Q3PortMode { normal, occupyCodexPrimary, occupyCodexAll }

enum Q3SyntheticScenario {
  duplicate,
  wrongStateThenValid,
  missingCodeThenValid,
  cancelThenLateCallback,
  successThenBrowserReturn,
}

extension Q3PhaseLabel on Q3Phase {
  String get label {
    return switch (this) {
      Q3Phase.idle => 'idle',
      Q3Phase.binding => 'binding',
      Q3Phase.browserOpen => 'browser open',
      Q3Phase.callbackAccepted => 'callback accepted',
      Q3Phase.cancelled => 'cancelled',
      Q3Phase.timeout => 'timeout',
      Q3Phase.failed => 'failed',
    };
  }
}

class Q3Controller extends ChangeNotifier {
  Q3Controller() {
    _browserSubscription = _browserBridge.events.listen(_onBrowserEvent);
  }

  static const Duration _attemptTimeout = Duration(minutes: 5);
  static const Duration _duplicateGrace = Duration(seconds: 1);

  final OAuthBrowserBridge _browserBridge = OAuthBrowserBridge();
  late final StreamSubscription<OAuthBrowserEvent> _browserSubscription;

  Q3Provider provider = Q3Provider.codex;
  Q3Phase phase = Q3Phase.idle;
  Q3RunKind runKind = Q3RunKind.provider;
  Q3PortMode portMode = Q3PortMode.normal;
  int? port;
  bool? stateMatches;
  bool? codePresent;
  int callbackCount = 0;
  int duplicateCount = 0;
  int lateEventCount = 0;
  Duration elapsed = Duration.zero;
  String? errorCategory;

  int _generation = 0;
  bool _terminal = false;
  bool _browserOpened = false;
  bool _acceptBrowserEvents = false;
  bool _disposed = false;
  String? _expectedState;
  DateTime? _startedAt;
  Q3LoopbackServer? _server;
  StreamSubscription<Q3CallbackEvent>? _callbackSubscription;
  final List<HttpServer> _portOccupiers = <HttpServer>[];
  Timer? _timeoutTimer;
  Timer? _elapsedTimer;
  Timer? _terminalCleanupTimer;

  bool get isActive => phase == Q3Phase.binding || phase == Q3Phase.browserOpen;

  bool get canInjectSyntheticCallback =>
      phase == Q3Phase.browserOpen && _server != null && _expectedState != null;

  void selectProvider(Q3Provider value) {
    if (isActive || provider == value) {
      return;
    }
    provider = value;
    notifyListeners();
  }

  Future<void> startProvider({
    Q3PortMode selectedPortMode = Q3PortMode.normal,
  }) {
    return _start(
      selectedRunKind: Q3RunKind.provider,
      selectedPortMode: selectedPortMode,
    );
  }

  Future<void> startSynthetic() {
    return _start(
      selectedRunKind: Q3RunKind.synthetic,
      selectedPortMode: Q3PortMode.normal,
    );
  }

  Future<void> _start({
    required Q3RunKind selectedRunKind,
    required Q3PortMode selectedPortMode,
  }) async {
    final generation = ++_generation;
    _acceptBrowserEvents = false;
    await _cleanupAttempt(closeBrowser: true);

    if (_disposed || generation != _generation) {
      return;
    }

    _resetPublicState(
      selectedRunKind: selectedRunKind,
      selectedPortMode: selectedPortMode,
    );
    _terminal = false;
    _startedAt = DateTime.now();
    phase = Q3Phase.binding;
    _startElapsedTimer(generation);
    notifyListeners();

    final config = provider.config;
    try {
      await _preparePortOccupiers(config, selectedPortMode);
      final material = createQ3AuthorizeMaterial();
      final server = await Q3LoopbackServer.bind(
        config: config,
        expectedState: material.state,
      );

      if (_disposed || generation != _generation) {
        await server.close();
        return;
      }

      _server = server;
      _expectedState = material.state;
      port = server.port;
      _callbackSubscription = server.events.listen(
        (event) => _onLoopbackEvent(generation, event),
      );
      _timeoutTimer = Timer(
        _attemptTimeout,
        () => unawaited(_markTimeout(generation)),
      );

      if (selectedRunKind == Q3RunKind.provider) {
        final authorizeUri = config.buildAuthorizeUri(
          port: server.port,
          state: material.state,
          codeChallenge: material.codeChallenge,
        );
        await _browserBridge.open(authorizeUri);
        if (_disposed || generation != _generation) {
          return;
        }
        _browserOpened = true;
      }

      _acceptBrowserEvents = true;
      phase = Q3Phase.browserOpen;
      notifyListeners();
    } on PlatformException catch (error) {
      if (generation == _generation) {
        await _markFailed(generation, _platformErrorCategory(error.code));
      }
    } on SocketException {
      if (generation == _generation) {
        await _markFailed(generation, 'port unavailable');
      }
    } on Object {
      if (generation == _generation) {
        await _markFailed(generation, 'setup failed');
      }
    }
  }

  Future<void> _preparePortOccupiers(
    Q3ProviderConfig config,
    Q3PortMode selectedPortMode,
  ) async {
    if (selectedPortMode == Q3PortMode.normal) {
      return;
    }
    if (config.provider != Q3Provider.codex) {
      throw StateError('Port fallback injection only applies to Codex.');
    }

    final ports = switch (selectedPortMode) {
      Q3PortMode.normal => const <int>[],
      Q3PortMode.occupyCodexPrimary => <int>[config.ports.first],
      Q3PortMode.occupyCodexAll => config.ports,
    };

    for (final occupiedPort in ports) {
      final occupier = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        occupiedPort,
        shared: false,
      );
      _portOccupiers.add(occupier);
    }
  }

  void _onLoopbackEvent(int generation, Q3CallbackEvent event) {
    if (_disposed || generation != _generation) {
      return;
    }

    callbackCount += 1;
    if (_terminal) {
      if (phase == Q3Phase.callbackAccepted &&
          event.kind == Q3CallbackKind.accepted) {
        duplicateCount += 1;
      } else {
        lateEventCount += 1;
      }
      notifyListeners();
      return;
    }

    stateMatches = event.stateMatches;
    codePresent = event.codePresent;

    switch (event.kind) {
      case Q3CallbackKind.accepted:
        unawaited(
          _enterTerminal(
            generation,
            Q3Phase.callbackAccepted,
            category: null,
            keepServerForDuplicateGrace: true,
          ),
        );
        break;
      case Q3CallbackKind.providerError:
        unawaited(
          _enterTerminal(
            generation,
            Q3Phase.cancelled,
            category: 'authorization not completed',
          ),
        );
        break;
      case Q3CallbackKind.stateMismatch:
        errorCategory = 'state mismatch';
        notifyListeners();
        break;
      case Q3CallbackKind.missingState:
        errorCategory = 'state missing';
        notifyListeners();
        break;
      case Q3CallbackKind.missingCode:
        errorCategory = 'code missing';
        notifyListeners();
        break;
      case Q3CallbackKind.invalidMethod:
        errorCategory = 'invalid method';
        notifyListeners();
        break;
      case Q3CallbackKind.invalidPath:
        errorCategory = 'invalid path';
        notifyListeners();
        break;
      case Q3CallbackKind.serverError:
        unawaited(
          _enterTerminal(
            generation,
            Q3Phase.failed,
            category: 'callback server failed',
          ),
        );
        break;
    }
  }

  void _onBrowserEvent(OAuthBrowserEvent event) {
    if (_disposed || !_acceptBrowserEvents) {
      return;
    }

    final generation = _generation;
    if (_terminal) {
      lateEventCount += 1;
      notifyListeners();
      return;
    }

    switch (event.type) {
      case OAuthBrowserEventType.cancelled:
        _browserOpened = false;
        unawaited(
          _enterTerminal(
            generation,
            Q3Phase.cancelled,
            category: 'browser cancelled',
          ),
        );
        break;
      case OAuthBrowserEventType.returned:
        _browserOpened = false;
        // Android Custom Tabs may resume this Activity before the browser
        // completes its localhost navigation. The lifecycle event is
        // diagnostic only; callback, explicit cancellation, or timeout
        // decides this attempt.
        break;
      case OAuthBrowserEventType.failed:
        _browserOpened = false;
        unawaited(
          _enterTerminal(
            generation,
            Q3Phase.failed,
            category: event.category ?? 'browser failed',
          ),
        );
        break;
    }
  }

  Future<void> cancelCurrent() async {
    if (phase != Q3Phase.browserOpen) {
      return;
    }
    await _enterTerminal(
      _generation,
      Q3Phase.cancelled,
      category: 'cancelled by user',
    );
  }

  Future<void> runSyntheticScenario(Q3SyntheticScenario scenario) async {
    await startSynthetic();
    if (!canInjectSyntheticCallback) {
      return;
    }

    switch (scenario) {
      case Q3SyntheticScenario.duplicate:
        await _sendSyntheticCallback();
        await _sendSyntheticCallback(allowAfterAccepted: true);
        break;
      case Q3SyntheticScenario.wrongStateThenValid:
        await _sendSyntheticCallback(stateOverride: 'q3-invalid-state');
        await _sendSyntheticCallback();
        break;
      case Q3SyntheticScenario.missingCodeThenValid:
        await _sendSyntheticCallback(includeCode: false);
        await _sendSyntheticCallback();
        break;
      case Q3SyntheticScenario.cancelThenLateCallback:
        final generation = _generation;
        await cancelCurrent();
        _onLoopbackEvent(
          generation,
          const Q3CallbackEvent(
            kind: Q3CallbackKind.accepted,
            stateMatches: true,
            codePresent: true,
          ),
        );
        break;
      case Q3SyntheticScenario.successThenBrowserReturn:
        await _sendSyntheticCallback();
        _onBrowserEvent(
          const OAuthBrowserEvent(OAuthBrowserEventType.returned),
        );
        break;
    }
  }

  Future<void> _sendSyntheticCallback({
    String? stateOverride,
    bool includeCode = true,
    bool allowAfterAccepted = false,
  }) async {
    final activeServer = _server;
    final expectedState = _expectedState;
    final acceptedGrace =
        allowAfterAccepted && _terminal && phase == Q3Phase.callbackAccepted;
    if (activeServer == null ||
        expectedState == null ||
        (_terminal && !acceptedGrace)) {
      return;
    }

    final queryParameters = <String, String>{
      'state': stateOverride ?? expectedState,
      if (includeCode) 'code': 'q3-synthetic',
    };
    final uri = Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: activeServer.port,
      path: provider.config.callbackPath,
      queryParameters: queryParameters,
    );

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      await response.drain<void>();
    } on Object {
      if (!_terminal) {
        errorCategory = 'synthetic callback failed';
        notifyListeners();
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _markTimeout(int generation) {
    return _enterTerminal(
      generation,
      Q3Phase.timeout,
      category: 'callback timeout',
    );
  }

  Future<void> _markFailed(int generation, String category) {
    return _enterTerminal(generation, Q3Phase.failed, category: category);
  }

  Future<void> _enterTerminal(
    int generation,
    Q3Phase terminalPhase, {
    required String? category,
    bool keepServerForDuplicateGrace = false,
  }) async {
    if (_disposed || generation != _generation) {
      return;
    }
    if (_terminal) {
      lateEventCount += 1;
      notifyListeners();
      return;
    }

    _terminal = true;
    phase = terminalPhase;
    errorCategory = category;
    _freezeElapsed();
    _timeoutTimer?.cancel();
    notifyListeners();

    if (_browserOpened) {
      unawaited(_closeBrowserSafely());
    }

    if (keepServerForDuplicateGrace) {
      _terminalCleanupTimer?.cancel();
      _terminalCleanupTimer = Timer(
        _duplicateGrace,
        () => unawaited(_cleanupNetworkResources()),
      );
    } else {
      await _cleanupNetworkResources();
    }
  }

  Future<void> _closeBrowserSafely() async {
    try {
      await _browserBridge.close();
    } on Object {
      // The terminal result is already decided; browser cleanup cannot replace it.
    }
  }

  Future<void> _cleanupNetworkResources() async {
    final callbackSubscription = _callbackSubscription;
    final server = _server;
    final occupiers = List<HttpServer>.of(_portOccupiers);

    _callbackSubscription = null;
    _server = null;
    _expectedState = null;
    _portOccupiers.clear();

    await callbackSubscription?.cancel();
    await server?.close();
    for (final occupier in occupiers) {
      await occupier.close(force: true);
    }
  }

  Future<void> _cleanupAttempt({required bool closeBrowser}) async {
    _timeoutTimer?.cancel();
    _elapsedTimer?.cancel();
    _terminalCleanupTimer?.cancel();
    _timeoutTimer = null;
    _elapsedTimer = null;
    _terminalCleanupTimer = null;

    if (closeBrowser && _browserOpened) {
      await _closeBrowserSafely();
    }
    _browserOpened = false;
    await _cleanupNetworkResources();
  }

  void _resetPublicState({
    required Q3RunKind selectedRunKind,
    required Q3PortMode selectedPortMode,
  }) {
    runKind = selectedRunKind;
    portMode = selectedPortMode;
    phase = Q3Phase.idle;
    port = null;
    stateMatches = null;
    codePresent = null;
    callbackCount = 0;
    duplicateCount = 0;
    lateEventCount = 0;
    elapsed = Duration.zero;
    errorCategory = null;
  }

  void _startElapsedTimer(int generation) {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || generation != _generation || _terminal) {
        return;
      }
      _updateElapsed();
      notifyListeners();
    });
  }

  void _updateElapsed() {
    final startedAt = _startedAt;
    if (startedAt != null) {
      elapsed = DateTime.now().difference(startedAt);
    }
  }

  void _freezeElapsed() {
    _updateElapsed();
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  String _platformErrorCategory(String code) {
    return switch (code) {
      'NO_CUSTOM_TAB' => 'custom tabs unavailable',
      'INVALID_ARGUMENT' => 'invalid browser request',
      'BROWSER_OPEN_FAILED' => 'browser open failed',
      'SESSION_START_FAILED' => 'browser session start failed',
      _ => 'browser bridge failed',
    };
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    _acceptBrowserEvents = false;
    unawaited(_disposeResources());
    super.dispose();
  }

  Future<void> _disposeResources() async {
    await _browserSubscription.cancel();
    await _cleanupAttempt(closeBrowser: true);
    await _browserBridge.dispose();
  }
}
