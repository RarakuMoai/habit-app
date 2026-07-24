import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    MascotPanelPrefs.openValue.value = 1.0;
    MascotPanelPrefs.hintSeenValue.value = false;
  });

  test('冷啟動不恢復舊面板狀態，固定收小功能卡露出兔咪', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      // 舊版曾記住功能卡展開；新版冷啟動應忽略。
      'mascot_panel_expanded': false,
      PrefsKeys.mascotPanelHintSeen: true,
    });
    MascotPanelPrefs.openValue.value = 0.0;

    await MascotPanelPrefs.load();

    expect(MascotPanelPrefs.openValue.value, 1.0);
    expect(MascotPanelPrefs.hintSeen, isTrue);
  });

  test('每日獎勵會立即收小功能卡並送出同步要求', () {
    MascotPanelPrefs.openValue.value = 0.0;
    final previousRequest = MascotPanelPrefs.settleRequest.value;

    MascotPanelPrefs.revealMascotForDailyReward();

    expect(MascotPanelPrefs.openValue.value, 1.0);
    expect(MascotPanelPrefs.settleRequest.value?.target, 1.0);
    expect(
      MascotPanelPrefs.settleRequest.value?.id,
      isNot(previousRequest?.id),
    );
  });
}
