// 番茄鐘 / 運動兩個計時器互斥：同一時間只允許一個「實際倒數中」。
//
// 兩者都放在 timer_page 的 IndexedStack 裡常駐，各自有獨立 ticker、鎖屏
// 鏈式通知與音效。若同時倒數，鎖屏會跳兩串通知、節拍器與番茄提示音互相
// 蓋掉，使用者分不清。故開始（含暫停後 resume）時要先取得鎖；對方在跑就
// 擋下、提示先停。暫停 / 重設 / 完成都釋放。
//
// 暫停不算「在跑」（沒有 ticker / 通知 / 音效），所以暫停中的一方不阻擋另一
// 方開始；等它 resume 時會走同一個取得鎖的入口而被擋。
enum ActiveTimer { focus, exercise }

class TimerMutex {
  TimerMutex._();

  static ActiveTimer? _active;

  /// 目前實際倒數中的計時器；都沒在跑時為 null。
  static ActiveTimer? get active => _active;

  /// 嘗試開始 [who]。沒人在跑、或持有者就是自己 → 佔用並回 true；
  /// 另一個正在跑 → 回 false。
  static bool tryAcquire(ActiveTimer who) {
    if (_active == null || _active == who) {
      _active = who;
      return true;
    }
    return false;
  }

  /// 釋放 [who]。只有持有者能釋放，避免在對方持有時誤清。
  static void release(ActiveTimer who) {
    if (_active == who) _active = null;
  }
}
