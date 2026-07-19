import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/timer_mutex.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('pauseActive 暫停目前模式並釋放鎖', () async {
    SharedPreferences.setMockInitialValues({});
    var paused = 0;
    TimerMutex.register(ActiveTimer.focus, () {
      paused++;
      TimerMutex.release(ActiveTimer.focus);
    });
    addTearDown(() => TimerMutex.unregister(ActiveTimer.focus));

    TimerMutex.acquire(ActiveTimer.focus);
    expect(TimerMutex.active, ActiveTimer.focus);

    expect(TimerMutex.pauseActive(), ActiveTimer.focus);
    expect(paused, 1);
    expect(TimerMutex.active, isNull);

    // 讓 acquire 內的匿名統計非同步寫入完成，避免測試結束後殘留工作。
    await Future<void>.delayed(Duration.zero);
  });
}
