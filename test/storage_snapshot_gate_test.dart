import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations_en.dart';
import 'package:habit_app/utils/backup_archive.dart';
import 'package:habit_app/utils/coin_service.dart';
import 'package:habit_app/utils/logical_day_coordinator.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/storage_snapshot_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _HoldWriteStore extends SharedPreferencesStorePlatform {
  _HoldWriteStore(this.delegate, this.key);
  final SharedPreferencesStorePlatform delegate;
  final String key;
  final reached = Completer<void>();
  final release = Completer<void>();
  @override
  Future<bool> clear() => delegate.clear();
  @override
  Future<Map<String, Object>> getAll() => delegate.getAll();
  @override
  Future<bool> remove(String key) => delegate.remove(key);
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == this.key && !reached.isCompleted) {
      reached.complete();
      await release.future;
    }
    return delegate.setValue(type, key, value);
  }
}

Future<void> _turn() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'snapshot waits for outer mutation and its nested write started after the request',
    () async {
      final release = Completer<void>();
      final events = <String>[];
      final writing = StorageSnapshotGate.write(() async {
        events.add('outer-start');
        await release.future;
        await StorageSnapshotGate.write(() async => events.add('nested-write'));
        events.add('outer-end');
      });
      final reading = StorageSnapshotGate.snapshot(
        () async => events.add('snapshot'),
      );
      await _turn();
      expect(events, ['outer-start']);
      release.complete();
      await Future.wait([writing, reading]).timeout(const Duration(seconds: 2));
      expect(events, ['outer-start', 'nested-write', 'outer-end', 'snapshot']);
    },
  );

  test(
    'exclusive snapshot admits owner work but delays new external writes',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final events = <String>[];
      final reading = StorageSnapshotGate.snapshot(() async {
        events.add('snapshot-start');
        await StorageSnapshotGate.snapshot(
          () async => events.add('nested-read'),
        );
        await StorageSnapshotGate.write(() async => events.add('owned-write'));
        entered.complete();
        await release.future;
        events.add('snapshot-end');
      });
      await entered.future;
      final writing = StorageSnapshotGate.write(
        () async => events.add('external-write'),
      );
      await _turn();
      expect(events, ['snapshot-start', 'nested-read', 'owned-write']);
      release.complete();
      await Future.wait([reading, writing]).timeout(const Duration(seconds: 2));
      expect(events.last, 'external-write');
      expect(
        events.indexOf('snapshot-end'),
        lessThan(events.indexOf('external-write')),
      );
    },
  );

  test(
    'unawaited owner write remains protected after snapshot callback returns',
    () async {
      final release = Completer<void>();
      final started = Completer<void>();
      var snapshotFinished = false;
      var writeFinished = false;
      final snapshot = StorageSnapshotGate.snapshot(() async {
        unawaited(
          StorageSnapshotGate.write(() async {
            started.complete();
            await release.future;
          }),
        );
      }).then((_) => snapshotFinished = true);
      await started.future;
      final writer = StorageSnapshotGate.write(
        () async => writeFinished = true,
      );
      await _turn();
      expect(snapshotFinished, isFalse);
      expect(writeFinished, isFalse);
      release.complete();
      await Future.wait([snapshot, writer]).timeout(const Duration(seconds: 2));
      expect(snapshotFinished, isTrue);
      expect(writeFinished, isTrue);
    },
  );

  test(
    'unawaited nested snapshot also keeps its owner until the read finishes',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var changed = false;
      final reading = StorageSnapshotGate.snapshot(() async {
        unawaited(
          StorageSnapshotGate.snapshot(() async {
            started.complete();
            await release.future;
          }),
        );
      });
      await started.future;
      final writing = StorageSnapshotGate.write(() async => changed = true);
      await _turn();
      expect(changed, isFalse);
      release.complete();
      await Future.wait([reading, writing]).timeout(const Duration(seconds: 2));
      expect(changed, isTrue);
    },
  );

  test(
    'writer and snapshot failures release waiters without swallowing caller errors',
    () async {
      await expectLater(
        StorageSnapshotGate.write<void>(
          () async => throw StateError('write failed'),
        ),
        throwsStateError,
      );
      expect(await StorageSnapshotGate.snapshot(() async => 42), 42);
      final started = Completer<void>();
      final release = Completer<void>();
      final snapshot = StorageSnapshotGate.snapshot<void>(() async {
        started.complete();
        await release.future;
        throw StateError('snapshot failed');
      });
      final expected = expectLater(snapshot, throwsStateError);
      await started.future;
      final writing = StorageSnapshotGate.write(() async => 7);
      release.complete();
      await expected;
      expect(await writing, 7);
      expect(await StorageSnapshotGate.snapshot(() async => 9), 9);
    },
  );

  test(
    'snapshot requested inside its own writer fails promptly instead of deadlocking',
    () async {
      await expectLater(
        StorageSnapshotGate.write(
          () => StorageSnapshotGate.snapshot(() async => 0),
        ).timeout(const Duration(seconds: 2)),
        throwsStateError,
      );
      expect(await StorageSnapshotGate.snapshot(() async => 1), 1);
    },
  );

  test(
    'expired inherited snapshot zone cannot bypass a later exclusive snapshot',
    () async {
      final later = Completer<void>();
      late Future<void> inherited;
      var changed = false;
      await StorageSnapshotGate.snapshot(() async {
        inherited = later.future.then(
          (_) => StorageSnapshotGate.write(() async => changed = true),
        );
      });
      final entered = Completer<void>();
      final release = Completer<void>();
      final snapshot = StorageSnapshotGate.snapshot(() async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      later.complete();
      await _turn();
      expect(changed, isFalse);
      release.complete();
      await Future.wait([
        snapshot,
        inherited,
      ]).timeout(const Duration(seconds: 2));
      expect(changed, isTrue);
    },
  );

  test(
    'snapshot outside the logical-day coordinator waits queued writes without lock inversion',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final release = Completer<void>();
      final entered = Completer<void>();
      final writing = LogicalDayCoordinator.instance.synchronizeStorage(
        () async {
          entered.complete();
          await release.future;
          await CoinService.debugAdd(25, 'snapshot test');
        },
      );
      await entered.future;
      var captured = false;
      final reading = StorageSnapshotGate.snapshot(
        () => LogicalDayCoordinator.instance.synchronizeStorage(() async {
          final archive = await BackupArchive.create(prefs);
          captured = true;
          return archive;
        }),
      );
      await _turn();
      expect(captured, isFalse);
      release.complete();
      await writing;
      final archive = await reading.timeout(const Duration(seconds: 2));
      expect(archive.values[PrefsKeys.coinBalance], 25);
      expect(
        (jsonDecode(archive.values[PrefsKeys.coinLedger] as String) as List)
            .single['amt'],
        25,
      );
    },
  );

  test(
    'direct backup requested during the UI snapshot cannot invert backup-lock order',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(PrefsKeys.coinBalance, 33);
      final entered = Completer<void>();
      final continueUi = Completer<void>();
      final ui = StorageSnapshotGate.snapshot(() async {
        entered.complete();
        await continueUi.future;
        return LogicalDayCoordinator.instance.synchronizeStorage(
          () => BackupArchive.create(prefs),
        );
      });
      await entered.future;
      // This call must wait outside BackupStorageLock, leaving the UI owner free
      // to enter its own nested archive creation after the pause.
      final direct = BackupArchive.create(prefs);
      await _turn();
      continueUi.complete();
      final results = await Future.wait([
        ui,
        direct,
      ]).timeout(const Duration(seconds: 2));
      expect(results.map((archive) => archive.values[PrefsKeys.coinBalance]), [
        33,
        33,
      ]);
    },
  );

  test(
    'real daily login midway through level persistence cannot export half its ledger',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final held = _HoldWriteStore(
        SharedPreferencesStorePlatform.instance,
        'flutter.${PrefsKeys.coinLoginLevel}',
      );
      SharedPreferencesStorePlatform.instance = held;
      final writing = CoinService.claimDailyLogin(
        now: DateTime(2026, 9, 11),
        l10n: AppLocalizationsEn(),
      );
      await held.reached.future;
      var exported = false;
      final reading = BackupArchive.create(prefs).then((archive) {
        exported = true;
        return archive;
      });
      await _turn();
      expect(exported, isFalse);
      held.release.complete();
      final reward = await writing;
      final archive = await reading.timeout(const Duration(seconds: 2));
      expect(reward, isNotNull);
      expect(archive.values[PrefsKeys.coinLoginLevel], 1);
      expect(archive.values[PrefsKeys.coinLoginStreak], 1);
      expect(archive.values[PrefsKeys.coinLastLoginDate], '2026-09-11');
      expect(
        archive.values[PrefsKeys.coinClaim('dailyLogin', '2026-09-11')],
        true,
      );
      expect(archive.values[PrefsKeys.coinBalance], reward!.totalAmount);
      final ledger =
          jsonDecode(archive.values[PrefsKeys.coinLedger] as String) as List;
      expect(ledger.single['amt'], reward.totalAmount);
    },
  );
}
