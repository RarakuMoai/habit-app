import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// legacy SharedPreferences 寫入失敗且 cache recovery 也失敗。
///
/// legacy API 會先改 Dart cache 再呼叫 platform store；在成功 reload 以前，任何
/// 後續 read-modify-write 都不能相信該 cache。
class PreferenceCachePoisoned implements Exception {
  const PreferenceCachePoisoned(this.key, this.writeError, this.reloadError);

  final String key;
  final Object writeError;
  final Object reloadError;

  @override
  String toString() =>
      'SharedPreferences cache for $key could not be recovered after '
      '$writeError (reload failed: $reloadError)';
}

/// SharedPreferences legacy cache 的 checked-write 與跨重試 recovery gate。
abstract final class PreferenceWriteGuard {
  static bool _cachePoisoned = false;
  static String? _poisonedKey;
  static Object? _poisonedBy;
  static int _poisonEpoch = 0;
  static Future<void>? _recoveryInFlight;
  static int? _recoveryEpoch;

  /// 在任何依賴 cache 的 read-modify-write 前呼叫。
  ///
  /// 前一輪若連 reload 都失敗，這裡會先重試 recovery；成功以前不得讀 cache。
  static Future<void> ensureHealthy(SharedPreferences prefs) async {
    while (_cachePoisoned) {
      final recovery = _recoveryInFlight ??= Future<void>.sync(prefs.reload);
      final recoveryEpoch = _recoveryEpoch ??= _poisonEpoch;
      try {
        await recovery;
        // 舊 recovery 的其他 waiter 可能較晚恢復；期間若已有另一筆 write 又
        // poison cache，舊 waiter 絕不能把較新的 poison 清掉。
        if (_poisonEpoch == recoveryEpoch) {
          _cachePoisoned = false;
          _poisonedKey = null;
          _poisonedBy = null;
        }
      } catch (error, stackTrace) {
        Error.throwWithStackTrace(
          PreferenceCachePoisoned(
            _poisonedKey ?? 'unknown',
            _poisonedBy ?? StateError('Unknown write failure'),
            error,
          ),
          stackTrace,
        );
      } finally {
        if (identical(_recoveryInFlight, recovery)) {
          _recoveryInFlight = null;
          _recoveryEpoch = null;
        }
      }
    }
  }

  /// 執行一筆 checked write；operation 必須用 closure 傳入，才能攔到 platform
  /// method 在建立 Future 當下同步丟出的例外。
  static Future<void> write(
    SharedPreferences prefs,
    Future<bool> Function() operation,
    String key,
  ) async {
    await ensureHealthy(prefs);

    Object failure;
    StackTrace failureStack;
    try {
      if (await operation()) return;
      failure = StateError('Failed to write $key');
      failureStack = StackTrace.current;
    } catch (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
    }

    _cachePoisoned = true;
    _poisonEpoch++;
    _poisonedKey = key;
    _poisonedBy = failure;
    await ensureHealthy(prefs);
    Error.throwWithStackTrace(failure, failureStack);
  }

  @visibleForTesting
  static void debugReset() {
    _cachePoisoned = false;
    _poisonedKey = null;
    _poisonedBy = null;
    _poisonEpoch++;
    _recoveryInFlight = null;
    _recoveryEpoch = null;
  }
}
