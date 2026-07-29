import 'dart:async';

import 'package:flutter/services.dart';

enum Q3BrowserEventType { cancelled, returned, failed }

class Q3BrowserEvent {
  const Q3BrowserEvent(this.type, {this.category});

  final Q3BrowserEventType type;
  final String? category;
}

class Q3BrowserBridge {
  Q3BrowserBridge() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static const MethodChannel _channel = MethodChannel(
    'com.nanvon.cctrace.mobile/q3_browser',
  );

  final StreamController<Q3BrowserEvent> _events =
      StreamController<Q3BrowserEvent>.broadcast(sync: true);

  Stream<Q3BrowserEvent> get events => _events.stream;

  Future<void> open(Uri authorizeUri) async {
    await _channel.invokeMethod<void>('open', <String, String>{
      'url': authorizeUri.toString(),
    });
  }

  Future<void> close() async {
    await _channel.invokeMethod<void>('close');
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (_events.isClosed) {
      return;
    }

    switch (call.method) {
      case 'browserCancelled':
        _events.add(const Q3BrowserEvent(Q3BrowserEventType.cancelled));
        break;
      case 'browserReturned':
        _events.add(const Q3BrowserEvent(Q3BrowserEventType.returned));
        break;
      case 'browserFailed':
        final arguments = call.arguments;
        final category = arguments is Map
            ? arguments['category'] as String?
            : null;
        _events.add(
          Q3BrowserEvent(Q3BrowserEventType.failed, category: category),
        );
        break;
    }
  }

  Future<void> dispose() async {
    await _channel.setMethodCallHandler(null);
    await _events.close();
  }
}
