import 'package:flutter/foundation.dart';

/// 目前顯示中的即時小遊戲。
///
/// 小遊戲可能掛在 root overlay，而 AppBar 留在原頁面；用這個極小的協調層
/// 讓足跡、聲音與設定在開啟前能先凍結遊戲，不必讓每個兔咪頁面彼此傳 callback。
abstract final class MiniGameSession {
  static Object? _owner;
  static VoidCallback? _pause;

  static void register({required Object owner, required VoidCallback onPause}) {
    _owner = owner;
    _pause = onPause;
  }

  static void unregister(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _pause = null;
  }

  static void pauseActive() => _pause?.call();

  @visibleForTesting
  static bool get hasActiveGame => _pause != null;
}
