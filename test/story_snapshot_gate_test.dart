import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/storage_snapshot_gate.dart';
import 'package:habit_app/utils/story_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Test-only wrapper intercepts the native persistence boundary.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Pauses after the first native key changed, while the other two are old.
class _PauseFirstStoryWrite extends SharedPreferencesStorePlatform {
  _PauseFirstStoryWrite(this.delegate, {this.pauseRemove = false});
  final SharedPreferencesStorePlatform delegate;
  final bool pauseRemove;
  final entered = Completer<void>();
  final release = Completer<void>();
  bool _paused = false;

  Future<bool> _hold(String key, Future<bool> operation) async {
    final saved = await operation;
    if (key == 'flutter.${PrefsKeys.storyUnlocked}' && !_paused) {
      _paused = true;
      entered.complete();
      await release.future;
    }
    return saved;
  }

  @override
  Future<bool> clear() => delegate.clear();
  @override
  Future<Map<String, Object>> getAll() => delegate.getAll();
  @override
  Future<bool> remove(String key) =>
      pauseRemove ? _hold(key, delegate.remove(key)) : delegate.remove(key);
  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      pauseRemove
      ? delegate.setValue(valueType, key, value)
      : _hold(key, delegate.setValue(valueType, key, value));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await StoryStore.load();
  });

  Future<Map<String, Object?>> capture() =>
      StorageSnapshotGate.snapshot(() async {
        await prefs.reload();
        return {
          for (final key in [
            PrefsKeys.storyUnlocked,
            PrefsKeys.storyUnread,
            PrefsKeys.storyPendingReveal,
          ])
            key: prefs.get(key),
        };
      });

  _PauseFirstStoryWrite hold({bool remove = false}) {
    final store = _PauseFirstStoryWrite(
      SharedPreferencesStorePlatform.instance,
      pauseRemove: remove,
    );
    SharedPreferencesStorePlatform.instance = store;
    addTearDown(() {
      if (!store.release.isCompleted) store.release.complete();
    });
    return store;
  }

  test(
    'snapshot waits until unlock persists its full three-key state',
    () async {
      final store = hold();
      final unlocking = StoryStore.unlock('first_habit');
      await store.entered.future;
      var captured = false;
      final snapshot = capture().then((value) {
        captured = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      expect(captured, isFalse);

      store.release.complete();
      expect(await unlocking, isTrue);
      final values = await snapshot;
      final unlocked =
          jsonDecode(values[PrefsKeys.storyUnlocked]! as String) as List;
      expect(unlocked.single['id'], 'first_habit');
      expect(values[PrefsKeys.storyUnread], ['first_habit']);
      expect(values[PrefsKeys.storyPendingReveal], ['first_habit']);
    },
  );

  test('snapshot waits until clear removes all related story keys', () async {
    await StoryStore.unlock('first_habit');
    final store = hold(remove: true);
    final clearing = StoryStore.clear();
    await store.entered.future;
    var captured = false;
    final snapshot = capture().then((value) {
      captured = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);
    expect(captured, isFalse);

    store.release.complete();
    await clearing;
    expect((await snapshot).values, everyElement(isNull));
  });

  test('an active snapshot delays a newly started story persistence', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    final snapshot = StorageSnapshotGate.snapshot(() async {
      entered.complete();
      await release.future;
      await prefs.reload();
      return prefs.getString(PrefsKeys.storyUnlocked);
    });
    await entered.future;
    var unlocked = false;
    final unlocking = StoryStore.unlock('first_habit').then((value) {
      unlocked = value;
    });
    await Future<void>.delayed(Duration.zero);
    expect(unlocked, isFalse);
    expect(prefs.getString(PrefsKeys.storyUnlocked), isNull);

    release.complete();
    expect(await snapshot, isNull);
    await unlocking;
    expect(unlocked, isTrue);
    expect(prefs.getStringList(PrefsKeys.storyPendingReveal), ['first_habit']);
  });
}
