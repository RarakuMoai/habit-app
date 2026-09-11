import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/main.dart';
import 'package:habit_app/utils/app_restart.dart';
import 'package:habit_app/utils/backup_archive.dart';
import 'package:habit_app/utils/backup_restore.dart';
import 'package:habit_app/utils/logical_day_coordinator.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Fail below the real legacy preferences cache so its optimistic remove stays
/// visible while the durable platform store still contains the restore journal.
class _InterruptedCommitStore extends SharedPreferencesStorePlatform {
  _InterruptedCommitStore(this.delegate);

  final SharedPreferencesStorePlatform delegate;
  int commitAttempts = 0;
  int failedReads = 0;
  bool failNextRead = false;
  bool failAllReads = false;

  @override
  Future<bool> clear() => delegate.clear();

  @override
  Future<Map<String, Object>> getAll() {
    if (failAllReads || failNextRead) {
      failNextRead = false;
      failedReads++;
      return Future.error(StateError('Native preferences read unavailable'));
    }
    return delegate.getAll();
  }

  @override
  Future<bool> remove(String key) {
    if (key == 'flutter.${PrefsKeys.backupRestoreJournal}') {
      commitAttempts++;
      failNextRead = true;
      return Future.value(false);
    }
    return delegate.remove(key);
  }

  @override
  Future<bool> setValue(String type, String key, Object value) =>
      delegate.setValue(type, key, value);
}

Future<void> _pumpStartup(WidgetTester tester) async {
  // Startup awaits endOfFrame before draining the old storage coordinator.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // The real startup awaits the orientation platform channel before storage.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });
  tearDown(() async {
    await LogicalDayCoordinator.resetForRestore();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets(
    'root retry discovers native journal after commit and recovery reload fail',
    (tester) async {
      SharedPreferences.setMockInitialValues({PrefsKeys.coinBalance: 123});
      final archive = await BackupArchive.create(
        await SharedPreferences.getInstance(),
      );
      SharedPreferences.setMockInitialValues({PrefsKeys.coinBalance: 1});
      final prefs = await SharedPreferences.getInstance();
      await BackupRestore(prefs: prefs).stage(archive);
      final native = SharedPreferencesStorePlatform.instance;
      final store = _InterruptedCommitStore(native);
      SharedPreferencesStorePlatform.instance = store;

      await tester.pumpWidget(const RootRestart(child: MyApp()));
      await _pumpStartup(tester);
      expect(find.byKey(const ValueKey('startup-error')), findsOneWidget);
      expect(store.commitAttempts, 1);
      expect(store.failedReads, 1);
      expect(prefs.containsKey(PrefsKeys.backupRestoreJournal), isFalse);
      expect(
        (await native.getAll())['flutter.${PrefsKeys.backupRestoreJournal}'],
        archive.encode(),
      );
      expect(prefs.getInt(PrefsKeys.coinBalance), 123);

      // This must rerun restoration even though the same prefs instance has no
      // journal in its cache. A second failed commit must still hold the gate.
      await tester.tap(find.byType(FilledButton));
      await _pumpStartup(tester);
      expect(store.commitAttempts, 2);
      expect(store.failedReads, 2);
      expect(find.byKey(const ValueKey('startup-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('app-entry')), findsNothing);
      expect(
        (await native.getAll())['flutter.${PrefsKeys.backupRestoreJournal}'],
        archive.encode(),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('failed initial native reload cannot start readers or writers', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({PrefsKeys.coinBalance: 7});
    await SharedPreferences.getInstance();
    final native = SharedPreferencesStorePlatform.instance;
    final before = await native.getAll();
    final store = _InterruptedCommitStore(native)..failAllReads = true;
    SharedPreferencesStorePlatform.instance = store;

    await tester.pumpWidget(const RootRestart(child: MyApp()));
    await _pumpStartup(tester);
    expect(find.byKey(const ValueKey('startup-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-entry')), findsNothing);
    expect(store.failedReads, 1);
    expect(await native.getAll(), before);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
