import 'package:flutter/foundation.dart';

import 'bgm_playlist.dart';
import 'bgm_service.dart';
import 'wardrobe_store.dart';

/// Route ownership for the title screen and first meeting. Claim the scope
/// before scheduling delayed audio; a newer route always owns the next cue.
class EntryAudio {
  EntryAudio({required EntryAudioBackend backend}) : _backend = backend;

  static final EntryAudio _native = EntryAudio(
    backend: _NativeEntryAudioBackend(),
  );
  @visibleForTesting
  static EntryAudio? debugInstance;
  static EntryAudio get instance => debugInstance ?? _native;
  static const introAsset = 'sounds/bgm_onboarding.m4a';

  final EntryAudioBackend _backend;
  final List<EntryAudioScope> _scopes = [];
  int _revision = 0;
  String? _returnAsset;

  bool get hasEntry => _scopes.isNotEmpty;

  EntryAudioScope open() {
    if (_scopes.isEmpty) {
      _returnAsset ??= _backend.loadedAsset ?? _backend.selectedAsset;
    }
    final scope = EntryAudioScope._(this);
    _scopes.add(scope);
    _revision++;
    return scope;
  }

  bool _owns(EntryAudioScope scope) =>
      !scope._closed && _scopes.isNotEmpty && identical(_scopes.last, scope);

  Future<void> _intro(EntryAudioScope scope, bool deferFade) async {
    if (!_owns(scope)) return;
    final revision = ++_revision;
    await _apply(
      introAsset,
      entry: true,
      revision: revision,
      deferFade: deferFade,
    );
  }

  Future<void> _close(EntryAudioScope scope) async {
    if (scope._closed) return;
    final wasOwner = _owns(scope);
    scope._closed = true;
    _scopes.remove(scope);
    if (!wasOwner) return;
    final revision = ++_revision;
    final entry = _scopes.isNotEmpty;
    final asset = entry ? introAsset : _returnAsset ?? _backend.selectedAsset;
    try {
      await _apply(asset, entry: entry, revision: revision);
    } finally {
      if (revision == _revision && !hasEntry) _returnAsset = null;
    }
  }

  Future<void> _home(EntryAudioScope scope) async {
    if (!_owns(scope)) return;
    final revision = ++_revision;
    for (final old in _scopes) {
      old._closed = true;
    }
    _scopes.clear();
    _returnAsset = _backend.selectedAsset;
    try {
      await _apply(_returnAsset!, entry: false, revision: revision);
    } finally {
      if (revision == _revision && !hasEntry) _returnAsset = null;
    }
  }

  Future<void> _apply(
    String asset, {
    required bool entry,
    required int revision,
    bool deferFade = false,
  }) async {
    // Disable playlist advancement before awaiting native initialization. A
    // completed opening cue must never change the user's selected music.
    await _backend.setEntryActive(entry);
    if (revision != _revision) return;
    await _backend.prepare();
    if (revision != _revision) return;
    // play declares the newer intent; ensurePlaying deliberately refuses to
    // replace another route's track. Keep BgmService's AOT recovery untouched.
    await _backend.play(asset, deferFade: deferFade);
  }
}

class EntryAudioScope {
  EntryAudioScope._(this._owner);
  final EntryAudio _owner;
  bool _closed = false;

  /// Safe after an arbitrary delay: a closed or covered route cannot take over.
  Future<void> playIntro({bool deferFade = true}) =>
      _owner._intro(this, deferFade);

  /// The ordinary first-run destination uses the wardrobe selection.
  Future<void> enterHome() => _owner._home(this);

  /// Preview/replay restores the track playing before entry. Idempotent, and
  /// disposing an older route cannot interrupt the newer title/intro route.
  Future<void> close() => _owner._close(this);
}

@visibleForTesting
abstract class EntryAudioBackend {
  String? get loadedAsset;
  String get selectedAsset;
  Future<void> prepare();
  Future<void> play(String asset, {required bool deferFade});
  Future<void> setEntryActive(bool active);
}

class _NativeEntryAudioBackend implements EntryAudioBackend {
  @override
  String? get loadedAsset => BgmService.instance.loadedAsset;
  @override
  String get selectedAsset => WardrobeStore.currentTrackAsset;

  @override
  Future<void> prepare() async {
    await BgmService.instance.init();
    BgmPlaylist.init();
  }

  @override
  Future<void> play(String asset, {required bool deferFade}) =>
      BgmService.instance.play(asset, deferFade: deferFade);

  @override
  Future<void> setEntryActive(bool active) =>
      BgmPlaylist.setEntryActive(active);
}
