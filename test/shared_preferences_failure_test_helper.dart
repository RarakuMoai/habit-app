// Test-only legacy SharedPreferences platform wrapper.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// 讓指定 key 的第一個 platform write 失敗，其餘行為交給 delegate。
///
/// SharedPreferences legacy API 會先更新 Dart cache，再等待這個 platform Future；
/// 因此這個 fake 能重現「cache 看似成功、native store 其實沒寫」的失敗窗口。
class FailFirstWriteStore extends SharedPreferencesStorePlatform {
  FailFirstWriteStore(
    this.delegate,
    this.key, {
    this.throwSynchronously = false,
    this.failFirstRecoveryReload = false,
  });

  final SharedPreferencesStorePlatform delegate;
  final String key;
  final bool throwSynchronously;
  final bool failFirstRecoveryReload;
  bool didFail = false;
  bool didRecoveryReloadFail = false;

  @override
  Future<bool> clear() => delegate.clear();

  @override
  Future<Map<String, Object>> getAll() {
    if (failFirstRecoveryReload && didFail && !didRecoveryReloadFail) {
      didRecoveryReloadFail = true;
      return Future<Map<String, Object>>.error(
        StateError('Recovery reload failed'),
      );
    }
    return delegate.getAll();
  }

  @override
  Future<bool> remove(String key) => delegate.remove(key);

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (!didFail && key == this.key) {
      didFail = true;
      if (throwSynchronously) {
        throw StateError('Synchronous write failure for $key');
      }
      return Future<bool>.value(false);
    }
    return delegate.setValue(valueType, key, value);
  }
}

FailFirstWriteStore installFailFirstWriteStore(
  String key, {
  bool throwSynchronously = false,
  bool failFirstRecoveryReload = false,
}) {
  final store = FailFirstWriteStore(
    SharedPreferencesStorePlatform.instance,
    key,
    throwSynchronously: throwSynchronously,
    failFirstRecoveryReload: failFirstRecoveryReload,
  );
  SharedPreferencesStorePlatform.instance = store;
  return store;
}
