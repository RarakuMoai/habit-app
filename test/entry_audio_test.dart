import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/entry_audio.dart';

class _Audio extends EntryAudioBackend {
  @override
  String? loadedAsset = 'sounds/previous.m4a';
  @override
  String selectedAsset = 'sounds/chosen.m4a';
  bool entryActive = false;
  Completer<void>? prepareGate;
  final played = <({String asset, bool deferred})>[];

  @override
  Future<void> prepare() async => await prepareGate?.future;
  @override
  Future<void> setEntryActive(bool active) async => entryActive = active;
  @override
  Future<void> play(String asset, {required bool deferFade}) async {
    loadedAsset = asset;
    played.add((asset: asset, deferred: deferFade));
  }
}

void main() {
  late _Audio backend;
  late EntryAudio audio;
  setUp(() {
    backend = _Audio();
    audio = EntryAudio(backend: backend);
  });

  test(
    'preview uses opening music and restores prior music without changing selection',
    () async {
      final scope = audio.open();
      await scope.playIntro();
      expect(backend.loadedAsset, EntryAudio.introAsset);
      expect(backend.entryActive, isTrue);
      expect(backend.played.single.deferred, isTrue);
      expect(backend.selectedAsset, 'sounds/chosen.m4a');
      await scope.close();
      expect(backend.loadedAsset, 'sounds/previous.m4a');
      expect(backend.entryActive, isFalse);
      expect(backend.selectedAsset, 'sounds/chosen.m4a');
    },
  );

  test(
    'normal completion uses current wardrobe selection and later dispose is inert',
    () async {
      final scope = audio.open();
      await scope.playIntro();
      backend.selectedAsset = 'sounds/new-choice.m4a';
      await scope.enterHome();
      final count = backend.played.length;
      await scope.close();
      await scope.playIntro();
      expect(backend.loadedAsset, 'sounds/new-choice.m4a');
      expect(backend.entryActive, isFalse);
      expect(backend.played, hasLength(count));
      expect(audio.hasEntry, isFalse);
    },
  );

  test(
    'delayed title cue and title disposal cannot interrupt onboarding',
    () async {
      final title = audio.open();
      final intro = audio.open();
      await intro.playIntro();
      await title.playIntro();
      await title.close();
      expect(backend.played, hasLength(1));
      expect(backend.entryActive, isTrue);
      await intro.enterHome();
      expect(backend.loadedAsset, 'sounds/chosen.m4a');
    },
  );

  test(
    'nested entry close returns to parent then original background',
    () async {
      final title = audio.open();
      await title.playIntro();
      final intro = audio.open();
      await intro.playIntro();
      await intro.close();
      expect(backend.loadedAsset, EntryAudio.introAsset);
      expect(backend.entryActive, isTrue);
      await title.close();
      expect(backend.loadedAsset, 'sounds/previous.m4a');
      expect(backend.entryActive, isFalse);
    },
  );

  test(
    'late native initialization cannot restore opening music after entering home',
    () async {
      final gate = Completer<void>();
      backend.prepareGate = gate;
      final scope = audio.open();
      final start = scope.playIntro();
      await Future<void>.delayed(Duration.zero);
      final finish = scope.enterHome();
      gate.complete();
      await Future.wait([start, finish]);
      expect(backend.played.map((p) => p.asset), ['sounds/chosen.m4a']);
      expect(backend.entryActive, isFalse);
    },
  );

  test(
    'reopening while restore is pending keeps the real return track',
    () async {
      final first = audio.open();
      await first.playIntro();
      backend.prepareGate = Completer<void>();
      final closing = first.close();
      await Future<void>.delayed(Duration.zero);
      final second = audio.open();
      final opening = second.playIntro();
      backend.prepareGate!.complete();
      await Future.wait([closing, opening]);
      expect(backend.loadedAsset, EntryAudio.introAsset);
      await second.close();
      expect(backend.loadedAsset, 'sounds/previous.m4a');
    },
  );

  test(
    'entry opened during pending home transition restores the selected home track',
    () async {
      final title = audio.open();
      await title.playIntro();
      backend.prepareGate = Completer<void>();
      final home = title.enterHome();
      await Future<void>.delayed(Duration.zero);
      final preview = audio.open();
      final opening = preview.playIntro();
      backend.prepareGate!.complete();
      await Future.wait([home, opening]);
      await preview.close();
      expect(backend.loadedAsset, 'sounds/chosen.m4a');
    },
  );

  test(
    'entry with no loaded source falls back to wardrobe selection',
    () async {
      backend.loadedAsset = null;
      final scope = audio.open();
      await scope.playIntro();
      await scope.close();
      expect(backend.loadedAsset, 'sounds/chosen.m4a');
    },
  );
}
