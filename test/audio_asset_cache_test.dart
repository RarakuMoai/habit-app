import 'dart:io';

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

  test('全新安裝的 cache 根目錄不存在時視為已清空，只記錄一次', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var calls = 0;
    Future<void> missingCache() async {
      calls++;
      throw const PathNotFoundException(
        '/tmp/just_audio_cache/',
        OSError('No such file or directory', 2),
        'Directory listing failed',
      );
    }

    expect(
      await AudioAssetCache.ensureCurrent(prefs, clearCache: missingCache),
      isTrue,
    );
    expect(
      await AudioAssetCache.ensureCurrent(prefs, clearCache: missingCache),
      isFalse,
    );
    expect(calls, 1);
    expect(
      prefs.getInt(PrefsKeys.audioAssetCacheVersion),
      AudioAssetCache.currentVersion,
    );
  });

  test('其他路徑缺失與權限錯誤仍保留失敗供下次重試', () async {
    for (final error in [
      const PathNotFoundException(
        '/tmp/just_audio_cache/audio.wav',
        OSError('No such file or directory', 2),
        'File missing',
      ),
      const FileSystemException(
        'Permission denied',
        '/tmp/just_audio_cache/',
        OSError('Permission denied', 13),
      ),
    ]) {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await expectLater(
        AudioAssetCache.ensureCurrent(
          prefs,
          clearCache: () async => throw error,
        ),
        throwsA(same(error)),
      );
      expect(prefs.getInt(PrefsKeys.audioAssetCacheVersion), isNull);
    }
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
