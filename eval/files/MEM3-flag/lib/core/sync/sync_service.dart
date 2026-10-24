import 'package:flutter/foundation.dart';

/// Tells listeners when a sync ends. One instance lives for the whole app.
class SyncService {
  final List<VoidCallback> _listeners = <VoidCallback>[];

  void onSynced(VoidCallback listener) => _listeners.add(listener);

  void notifySynced() {
    for (final VoidCallback listener in _listeners) {
      listener();
    }
  }
}

final SyncService syncService = SyncService();
