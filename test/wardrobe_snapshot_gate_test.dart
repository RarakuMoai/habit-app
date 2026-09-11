import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/backup_archive.dart';
import 'package:habit_app/utils/coin_service.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/wardrobe_catalog.dart';
import 'package:habit_app/utils/wardrobe_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared_preferences_delay_test_helper.dart';

Future<void> _waitUntilDelayed(DelayFirstWriteStore store) async {
  for (var i = 0; i < 100 && !store.didDelay; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(store.didDelay, isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.coinBalance: 500,
      PrefsKeys.bgmOwnedTracks: [defaultTrack.id],
      PrefsKeys.bgmPlaylist: [defaultTrack.id],
      PrefsKeys.bgmSelectedTrack: defaultTrack.id,
    });
    CoinService.notifier.value = 500;
    WardrobeStore.reset();
  });

  test(
    'backup waits for purchase ownership after the coins are deducted',
    () async {
      await WardrobeStore.load();
      final prefs = await SharedPreferences.getInstance();
      final track = trackById('bgm_aquamarine');
      final store = installDelayFirstWriteStore(
        'flutter.${PrefsKeys.bgmOwnedTracks}',
      );
      addTearDown(store.restore);

      final purchase = WardrobeStore.purchaseTrack(track.id, '購買音樂');
      await _waitUntilDelayed(store);
      expect(prefs.getInt(PrefsKeys.coinBalance), 500 - track.coinPrice);

      var captured = false;
      final backup = BackupArchive.create(prefs).then((archive) {
        captured = true;
        return archive;
      });
      await Future<void>.delayed(Duration.zero);
      expect(captured, isFalse);

      store.release();
      expect(await purchase, PurchaseResult.success);
      final archive = await backup;
      expect(archive.values[PrefsKeys.coinBalance], 500 - track.coinPrice);
      expect(archive.values[PrefsKeys.bgmOwnedTracks], contains(track.id));
      final ledger =
          jsonDecode(archive.values[PrefsKeys.coinLedger] as String) as List;
      expect(ledger.single['amt'], -track.coinPrice);
    },
  );

  test('backup never retains the removed current track pointer', () async {
    final prefs = await SharedPreferences.getInstance();
    const nextTrack = 'bgm_onboarding';
    await prefs.setStringList(PrefsKeys.bgmPlaylist, [
      defaultTrack.id,
      nextTrack,
    ]);
    await WardrobeStore.load();
    final store = installDelayFirstWriteStore(
      'flutter.${PrefsKeys.bgmSelectedTrack}',
    );
    addTearDown(store.restore);

    final removing = WardrobeStore.removeTrack(defaultTrack.id);
    await _waitUntilDelayed(store);
    var captured = false;
    final backup = BackupArchive.create(prefs).then((archive) {
      captured = true;
      return archive;
    });
    await Future<void>.delayed(Duration.zero);
    expect(captured, isFalse);

    store.release();
    expect(await removing, isTrue);
    final archive = await backup;
    expect(archive.values[PrefsKeys.bgmPlaylist], [nextTrack]);
    expect(archive.values[PrefsKeys.bgmSelectedTrack], nextTrack);
  });
}
