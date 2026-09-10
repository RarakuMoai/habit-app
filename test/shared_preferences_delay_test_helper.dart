import 'dart:async';

// Test-only wrapper of the legacy SharedPreferences platform store.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Holds the first native write of [key] while unrelated writes remain usable.
/// The legacy Dart cache is updated before this Future, matching production.
class DelayFirstWriteStore extends SharedPreferencesStorePlatform {
  DelayFirstWriteStore(this.delegate, this.key);

  final SharedPreferencesStorePlatform delegate;
  final String key;
  final _release = Completer<void>();
  bool didDelay = false;

  void release() {
    if (!_release.isCompleted) _release.complete();
  }

  void restore() {
    release();
    if (identical(SharedPreferencesStorePlatform.instance, this)) {
      SharedPreferencesStorePlatform.instance = delegate;
    }
  }

  @override
  Future<bool> clear() => delegate.clear();

  @override
  Future<Map<String, Object>> getAll() => delegate.getAll();

  @override
  Future<bool> remove(String key) => delegate.remove(key);

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (!didDelay && key == this.key) {
      didDelay = true;
      await _release.future;
    }
    return delegate.setValue(valueType, key, value);
  }
}

DelayFirstWriteStore installDelayFirstWriteStore(String key) {
  final store = DelayFirstWriteStore(
    SharedPreferencesStorePlatform.instance,
    key,
  );
  SharedPreferencesStorePlatform.instance = store;
  return store;
}
