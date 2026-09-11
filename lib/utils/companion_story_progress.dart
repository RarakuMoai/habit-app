import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'companion_story_catalog.dart';
import 'mascot.dart';
import 'prefs_keys.dart';

/// Locale-independent position, including only choices the reader actually made.
@immutable
class CompanionCursor {
  CompanionCursor({
    required this.episodeId,
    this.beatIndex = 0,
    this.lineIndex = 0,
    this.choiceId,
    this.replyIndex = 0,
    Map<String, String> choices = const {},
    Map<String, Object?> extra = const {},
  }) : choices = Map.unmodifiable(choices),
       _extra = _freezeMap(extra);

  final String episodeId;
  final int beatIndex;
  final int lineIndex;
  final String? choiceId;
  final int replyIndex;
  final Map<String, String> choices;
  final Map<String, Object?> _extra;

  Map<String, Object?> toJson() => {
    ..._extra,
    'episodeId': episodeId,
    'beatIndex': beatIndex,
    'lineIndex': lineIndex,
    'choiceId': choiceId,
    'replyIndex': replyIndex,
    'choices': choices,
  };

  factory CompanionCursor.fromJson(Map<String, dynamic> json) {
    final id = json['episodeId'];
    final beat = json['beatIndex'];
    final line = json['lineIndex'];
    final choice = json['choiceId'];
    final reply = json['replyIndex'];
    if (id is! String ||
        id.isEmpty ||
        beat is! int ||
        line is! int ||
        (choice != null && choice is! String) ||
        reply is! int) {
      throw const FormatException('Invalid companion cursor');
    }
    return CompanionCursor(
      episodeId: id,
      beatIndex: beat,
      lineIndex: line,
      choiceId: choice as String?,
      replyIndex: reply,
      choices: _stringMap(json['choices']),
      extra: _extras(json, const {
        'episodeId',
        'beatIndex',
        'lineIndex',
        'choiceId',
        'replyIndex',
        'choices',
      }),
    );
  }
}

/// Pure reader. It never writes progress, including when used for archive or
/// developer preview. At [atEnd], [text] is still the final visible line.
@immutable
class CompanionSession {
  CompanionSession(this.episode, [CompanionCursor? cursor])
    : cursor = _normalize(episode, cursor);

  final CompanionEpisode episode;
  final CompanionCursor cursor;

  CompanionBeat get _beat => episode.beats[cursor.beatIndex];
  CompanionChoice? get _selected {
    for (final choice in _beat.choices) {
      if (choice.id == cursor.choiceId) return choice;
    }
    return null;
  }

  CompanionText get text {
    final selected = _selected;
    if (selected != null && selected.replies.isNotEmpty) {
      return selected.replies[cursor.replyIndex];
    }
    return _beat.lines[cursor.lineIndex];
  }

  MascotEmotion get emotion => _selected?.emotion ?? _beat.emotion;

  List<CompanionChoice> get choices =>
      cursor.lineIndex == _beat.lines.length - 1 && _selected == null
      ? List.unmodifiable(_beat.choices)
      : const [];

  bool get atEnd {
    if (cursor.beatIndex != episode.beats.length - 1 || choices.isNotEmpty) {
      return false;
    }
    final selected = _selected;
    return selected == null
        ? cursor.lineIndex == _beat.lines.length - 1
        : cursor.replyIndex >= selected.replies.length - 1;
  }

  CompanionCursor advance() {
    if (atEnd || choices.isNotEmpty) return cursor;
    final selected = _selected;
    if (selected != null && cursor.replyIndex < selected.replies.length - 1) {
      return _position(reply: cursor.replyIndex + 1);
    }
    if (selected == null && cursor.lineIndex < _beat.lines.length - 1) {
      return _position(line: cursor.lineIndex + 1);
    }
    return CompanionCursor(
      episodeId: episode.id,
      beatIndex: cursor.beatIndex + 1,
      choices: cursor.choices,
      extra: cursor._extra,
    );
  }

  CompanionCursor choose(String id) {
    if (!choices.any((choice) => choice.id == id)) return cursor;
    return CompanionCursor(
      episodeId: episode.id,
      beatIndex: cursor.beatIndex,
      lineIndex: cursor.lineIndex,
      choiceId: id,
      choices: {...cursor.choices, _beat.id: id},
      extra: cursor._extra,
    );
  }

  CompanionCursor _position({int? line, int? reply}) => CompanionCursor(
    episodeId: episode.id,
    beatIndex: cursor.beatIndex,
    lineIndex: line ?? cursor.lineIndex,
    choiceId: cursor.choiceId,
    replyIndex: reply ?? cursor.replyIndex,
    choices: cursor.choices,
    extra: cursor._extra,
  );

  static CompanionCursor _normalize(
    CompanionEpisode episode,
    CompanionCursor? source,
  ) {
    if (episode.beats.isEmpty || episode.beats.any((b) => b.lines.isEmpty)) {
      throw ArgumentError.value(episode.id, 'episode', 'Missing story lines');
    }
    if (source == null || source.episodeId != episode.id) {
      return CompanionCursor(episodeId: episode.id);
    }
    // A revised script can shorten a beat. Restart that beat, never jump to an
    // unrelated response or synthesize a choice from translated display text.
    final beatIndex =
        source.beatIndex >= 0 && source.beatIndex < episode.beats.length
        ? source.beatIndex
        : 0;
    final beat = episode.beats[beatIndex];
    final lineIndex =
        source.lineIndex >= 0 && source.lineIndex < beat.lines.length
        ? source.lineIndex
        : 0;
    CompanionChoice? selected;
    if (beatIndex == source.beatIndex && lineIndex == beat.lines.length - 1) {
      for (final choice in beat.choices) {
        if (choice.id == source.choiceId) selected = choice;
      }
    }
    final replyIndex =
        selected != null &&
            source.replyIndex >= 0 &&
            source.replyIndex < selected.replies.length
        ? source.replyIndex
        : 0;
    return CompanionCursor(
      episodeId: episode.id,
      beatIndex: beatIndex,
      lineIndex: lineIndex,
      choiceId: selected?.id,
      replyIndex: replyIndex,
      choices: source.choices,
      extra: source._extra,
    );
  }
}

@immutable
class CompanionCompletion {
  CompanionCompletion({
    required this.firstCompletedAt,
    required this.skipped,
    required this.read,
    Map<String, String> choices = const {},
    Map<String, Object?> extra = const {},
  }) : choices = Map.unmodifiable(choices),
       _extra = _freezeMap(extra);

  /// Logical date supplied by the app, not a independently sampled calendar day.
  final String firstCompletedAt;

  /// Whether the first completion was skipped. Later reading only changes read.
  final bool skipped;
  final bool read;
  final Map<String, String> choices;
  final Map<String, Object?> _extra;

  Map<String, Object?> toJson() => {
    ..._extra,
    'firstCompletedAt': firstCompletedAt,
    'skipped': skipped,
    'read': read,
    'choices': choices,
  };

  factory CompanionCompletion.fromJson(Map<String, dynamic> json) {
    final date = json['firstCompletedAt'];
    final skipped = json['skipped'];
    final read = json['read'];
    if (date is! String ||
        !_validDay(date) ||
        skipped is! bool ||
        read is! bool) {
      throw const FormatException('Invalid companion completion');
    }
    return CompanionCompletion(
      firstCompletedAt: date,
      skipped: skipped,
      read: read,
      choices: _stringMap(json['choices']),
      extra: _extras(json, const {
        'firstCompletedAt',
        'skipped',
        'read',
        'choices',
      }),
    );
  }
}

@immutable
class CompanionProgressState {
  CompanionProgressState({
    this.days = 0,
    Map<String, CompanionCompletion> completed = const {},
    Set<String> creditedDayKeys = const {},
    this.active,
    Map<String, Object?> extra = const {},
  }) : completed = Map.unmodifiable(completed),
       creditedDayKeys = Set.unmodifiable(creditedDayKeys),
       _extra = _freezeMap(extra);

  final int days;
  final Map<String, CompanionCompletion> completed;
  final Set<String> creditedDayKeys;
  final CompanionCursor? active;
  final Map<String, Object?> _extra;

  Map<String, Object?> toJson() => {
    ..._extra,
    'version': 1,
    'days': days,
    'creditedDayKeys': creditedDayKeys.toList()..sort(),
    'completed': {
      for (final entry in completed.entries) entry.key: entry.value.toJson(),
    },
    'active': active?.toJson(),
  };

  factory CompanionProgressState.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported companion progress version');
    }
    final days = json['days'];
    final dates = json['creditedDayKeys'];
    final completed = json['completed'];
    final active = json['active'];
    if (days is! int ||
        days < 0 ||
        days > 90 ||
        dates is! List ||
        dates.any((d) => d is! String || !_validDay(d)) ||
        completed is! Map ||
        (active != null && active is! Map)) {
      throw const FormatException('Invalid companion progress');
    }
    return CompanionProgressState(
      days: days,
      creditedDayKeys: dates.cast<String>().toSet(),
      completed: {
        for (final entry in completed.entries)
          _nonEmptyString(entry.key): CompanionCompletion.fromJson(
            _jsonMap(entry.value),
          ),
      },
      active: active == null
          ? null
          : CompanionCursor.fromJson(_jsonMap(active)),
      extra: _extras(json, const {
        'version',
        'days',
        'creditedDayKeys',
        'completed',
        'active',
      }),
    );
  }
}

/// One atomic JSON document for companion days, archive and resumable choices.
/// All mutations are serialized and become visible only after a confirmed write.
class CompanionStoryProgress extends ChangeNotifier {
  CompanionStoryProgress({
    SharedPreferences? prefs,
    Future<bool> Function(String key, String value)? writeString,
  }) : _prefs = prefs,
       _writeString = writeString;

  static final instance = CompanionStoryProgress();
  SharedPreferences? _prefs;
  final Future<bool> Function(String key, String value)? _writeString;
  CompanionProgressState _state = CompanionProgressState();
  CompanionProgressState get state => _state;
  bool _loaded = false;
  bool get loaded => _loaded;
  String? _loadError;

  /// Non-null blocks writes so corrupt or newer saves cannot be overwritten.
  String? get loadError => _loadError;
  Future<void> _tail = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<bool> load() => _serial(_load);

  /// Drain pending story writes before replacing or erasing all preferences.
  Future<void> settleWrites() => _tail;

  /// Startup also runs after an in-app reset or snapshot restore.
  /// Never carry the previous storage generation into the rebuilt widget tree.
  Future<bool> reload() => _serial(() async {
    _prefs = null;
    _state = CompanionProgressState();
    _loaded = false;
    _loadError = null;
    return _load();
  });

  @visibleForTesting
  Future<void> resetForTesting() async {
    await settleWrites();
    _prefs = null;
    _state = CompanionProgressState();
    _loaded = false;
    _loadError = null;
    // Each widget test owns a new async zone. Start its empty queue there.
    _tail = SynchronousFuture<void>(null);
    notifyListeners();
  }

  Future<bool> _load() async {
    if (_loaded) return _loadError == null;
    try {
      final prefs = _prefs ??= await SharedPreferences.getInstance();
      // Legacy SharedPreferences mutates its cache before the native write can
      // fail. Read the platform before accepting a newly created store's state.
      await prefs.reload();
      final raw = prefs.getString(PrefsKeys.companionStoryProgress);
      final next = raw == null
          ? CompanionProgressState()
          : CompanionProgressState.fromJson(_jsonMap(jsonDecode(raw)));
      _state = next;
      _loadError = null;
    } catch (error) {
      _loadError = error.toString();
    }
    _loaded = true;
    notifyListeners();
    return _loadError == null;
  }

  CompanionEpisode? nextEpisode(String dayKey) {
    if (!_loaded || _loadError != null || !_validDay(dayKey)) return null;
    final active = _state.active;
    if (active != null) return companionEpisodeById(active.episodeId);
    if (_state.creditedDayKeys.contains(dayKey)) return null;
    for (final episode in companionEpisodes) {
      if (episode.day <= _state.days + 1 &&
          !_state.completed.containsKey(episode.id)) {
        return episode;
      }
    }
    // Sparse main-story milestones must not stop the daily relationship clock.
    final daily = [
      for (final id in const [
        'daily_02',
        'daily_03',
        'daily_05',
        'daily_06',
      ]) // units-ok: Dart iteration.
        ?companionEpisodeById(id),
    ];
    return daily.isEmpty
        ? null
        : daily[_state.creditedDayKeys.length % daily.length];
  }

  Future<bool> begin(String episodeId) => _serial(() async {
    if (!await _load()) return false;
    final episode = companionEpisodeById(episodeId);
    if (episode == null || episode.day > _state.days + 1) return false;
    final active = _state.active;
    if (active != null) return active.episodeId == episodeId;
    if (_state.completed.containsKey(episodeId) &&
        episode.kind == CompanionStoryKind.main) {
      return false;
    }
    return _persist(_replace(active: CompanionCursor(episodeId: episodeId)));
  });

  Future<bool> saveCursor(CompanionCursor cursor) => _serial(() async {
    if (!await _load() || _state.active?.episodeId != cursor.episodeId) {
      return false;
    }
    final episode = companionEpisodeById(cursor.episodeId);
    if (episode == null) return false;
    final normalized = CompanionSession(episode, cursor).cursor;
    return _persist(_replace(active: normalized));
  });

  Future<bool> finish(
    String episodeId, {
    required String dayKey,
    required bool skipped,
  }) => _serial(() async {
    if (!await _load() || !_validDay(dayKey)) return false;
    final episode = companionEpisodeById(episodeId);
    if (episode == null || episode.day > _state.days + 1) return false;
    final previous = _state.completed[episodeId];
    final active = _state.active;
    if (active?.episodeId != episodeId) {
      // The second queued tap can arrive after the first cleared its cursor.
      return active == null &&
          previous != null &&
          _state.creditedDayKeys.contains(dayKey);
    }
    if (!skipped && !CompanionSession(episode, active).atEnd) return false;
    final completion = CompanionCompletion(
      firstCompletedAt: previous?.firstCompletedAt ?? dayKey,
      skipped: previous?.skipped ?? skipped,
      read: (previous?.read ?? false) || !skipped,
      choices: {...?previous?.choices, ...active!.choices},
      extra: previous?._extra ?? const {},
    );
    final credited = _state.creditedDayKeys.contains(dayKey);
    return _persist(
      CompanionProgressState(
        days: !credited && _state.days < 90 ? _state.days + 1 : _state.days,
        completed: {..._state.completed, episodeId: completion},
        creditedDayKeys: {..._state.creditedDayKeys, dayKey},
        extra: _state._extra,
      ),
    );
  });

  /// The story-led first meeting is its own presentation of story_01. Commit it
  /// without manufacturing reader positions or answers. A setup retry on a
  /// later day must not turn the same first meeting into a second companionship.
  Future<bool> completeOnboarding({
    required String dayKey,
    required bool skipped,
  }) => _serial(() async {
    if (!await _load() || !_validDay(dayKey)) return false;
    const episodeId = 'story_01';
    if (companionEpisodeById(episodeId) == null) return false;
    final active = _state.active;
    if (active != null && active.episodeId != episodeId) return false;
    if (_state.completed.containsKey(episodeId)) return true;
    final credited = _state.creditedDayKeys.contains(dayKey);
    return _persist(
      CompanionProgressState(
        days: !credited && _state.days < 90 ? _state.days + 1 : _state.days,
        completed: {
          ..._state.completed,
          episodeId: CompanionCompletion(
            firstCompletedAt: dayKey,
            skipped: skipped,
            read: !skipped,
            choices: active?.choices ?? const {},
          ),
        },
        creditedDayKeys: {..._state.creditedDayKeys, dayKey},
        extra: _state._extra,
      ),
    );
  });

  /// Archive reading may clear unread status, but never grants a day or answer.
  /// Developer preview must not call this method.
  Future<bool> markRead(String episodeId) => _serial(() async {
    if (!await _load()) return false;
    final previous = _state.completed[episodeId];
    if (previous == null) return false;
    if (previous.read) return true;
    return _persist(
      _replace(
        completed: {
          ..._state.completed,
          episodeId: CompanionCompletion(
            firstCompletedAt: previous.firstCompletedAt,
            skipped: previous.skipped,
            read: true,
            choices: previous.choices,
            extra: previous._extra,
          ),
        },
        active: _state.active,
      ),
    );
  });

  CompanionProgressState _replace({
    Map<String, CompanionCompletion>? completed,
    CompanionCursor? active,
  }) => CompanionProgressState(
    days: _state.days,
    completed: completed ?? _state.completed,
    creditedDayKeys: _state.creditedDayKeys,
    active: active,
    extra: _state._extra,
  );

  Future<bool> _persist(CompanionProgressState next) async {
    if (_loadError != null) return false;
    final prefs = _prefs!;
    try {
      final raw = jsonEncode(next.toJson());
      final saved =
          await (_writeString?.call(PrefsKeys.companionStoryProgress, raw) ??
              prefs.setString(PrefsKeys.companionStoryProgress, raw));
      if (saved) {
        _state = next;
        notifyListeners();
        return true;
      }
    } catch (_) {
      // Caller keeps the visible reader position and can offer a retry.
    }
    try {
      await prefs.reload();
    } catch (_) {
      // Keep the last confirmed state. A subsequent attempt still writes the
      // complete document, without trusting SharedPreferences' optimistic cache.
    }
    return false;
  }
}

Map<String, dynamic> _jsonMap(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Expected a JSON object');
  }
  return Map<String, dynamic>.from(value);
}

Map<String, String> _stringMap(Object? value) {
  final json = _jsonMap(value);
  if (json.values.any((v) => v is! String)) {
    throw const FormatException('Invalid companion answer map');
  }
  return json.cast<String, String>();
}

Map<String, Object?> _extras(Map<String, dynamic> json, Set<String> known) => {
  for (final entry in json.entries)
    if (!known.contains(entry.key)) entry.key: entry.value,
};

String _nonEmptyString(Object? value) {
  if (value is! String || value.isEmpty) {
    throw const FormatException('Invalid companion episode ID');
  }
  return value;
}

bool _validDay(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final date = DateTime.tryParse(value);
  return date != null && date.toIso8601String().substring(0, 10) == value;
}

Map<String, Object?> _freezeMap(Map<String, Object?> source) =>
    Map.unmodifiable({
      for (final entry in source.entries) entry.key: _freezeValue(entry.value),
    });

Object? _freezeValue(Object? value) {
  if (value is Map<String, Object?>) return _freezeMap(value);
  if (value is List) return List<Object?>.unmodifiable(value.map(_freezeValue));
  return value;
}
