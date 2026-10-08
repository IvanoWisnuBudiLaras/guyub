import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Reports network-route availability as a sync trigger, never as authorization.
abstract interface class NetworkConnectivityBoundary {
  Stream<bool> get onlineChanges;
}

/// Connectivity Plus adapter with an initial status and distinct changes.
final class ConnectivityPlusBoundary implements NetworkConnectivityBoundary {
  ConnectivityPlusBoundary({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  late final Stream<bool> onlineChanges = _createOnlineChanges();

  Stream<bool> _createOnlineChanges() {
    late final StreamController<bool> controller;
    StreamSubscription<List<ConnectivityResult>>? subscription;
    var receivedEvent = false;

    controller = StreamController<bool>.broadcast(
      onListen: () {
        receivedEvent = false;
        subscription = _connectivity.onConnectivityChanged.listen((results) {
          receivedEvent = true;
          controller.add(_hasNetworkRoute(results));
        }, onError: controller.addError);
        unawaited(_emitInitialStatus(controller, () => receivedEvent));
      },
      onCancel: () async {
        if (!controller.hasListener) await subscription?.cancel();
      },
    );
    return controller.stream.distinct();
  }

  Future<void> _emitInitialStatus(
    StreamController<bool> controller,
    bool Function() receivedEvent,
  ) async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (!receivedEvent()) controller.add(_hasNetworkRoute(results));
    } catch (error, stackTrace) {
      if (!receivedEvent()) controller.addError(error, stackTrace);
    }
  }

  static bool _hasNetworkRoute(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);
}
