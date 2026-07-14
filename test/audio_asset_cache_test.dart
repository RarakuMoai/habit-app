import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/audio_asset_cache.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('舊版或缺少版本時只清一次音訊快取', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var clearCalls = 0;

    final firstCleared = await AudioAssetCache.ensureCurrent(
      prefs,
      clearCache: () async {
        clearCalls++;
      },
    );
    final secondCleared = await AudioAssetCache.ensureCurrent(
      prefs,
      clearCache: () async {
        clearCalls++;
      },
    );

    expect(firstCleared, isTrue);
    expect(secondCleared, isFalse);
    expect(clearCalls, 1);
    expect(
      prefs.getInt(PrefsKeys.audioAssetCacheVersion),
      AudioAssetCache.currentVersion,
    );
  });

  test('已是目前版本時不清除快取', () async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.audioAssetCacheVersion: AudioAssetCache.currentVersion,
    });
    final prefs = await SharedPreferences.getInstance();
    var clearCalls = 0;

    final cleared = await AudioAssetCache.ensureCurrent(
      prefs,
      clearCache: () async {
        clearCalls++;
      },
    );

    expect(cleared, isFalse);
    expect(clearCalls, 0);
  });

  test('清除失敗時不推進版本，讓下次啟動重試', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await expectLater(
      AudioAssetCache.ensureCurrent(
        prefs,
        clearCache: () async => throw StateError('clear failed'),
      ),
      throwsStateError,
    );

    expect(prefs.getInt(PrefsKeys.audioAssetCacheVersion), isNull);
  });
}
