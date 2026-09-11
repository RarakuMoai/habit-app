import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../pages/companion_dialogue_page.dart';
import '../pages/memory_book_reader.dart';
import '../utils/app_style.dart';
import '../utils/companion_story_catalog.dart';
import '../utils/companion_story_preview.dart';
import '../utils/companion_story_progress.dart';
import '../utils/mascot.dart';
import '../utils/story_catalog.dart';
import '../utils/story_store.dart';
import 'app_waiting.dart';

/// The developer shortcut uses the same collection as the wardrobe.
class CompanionMemoryReviewPage extends StatelessWidget {
  const CompanionMemoryReviewPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppSurfaces.canvas,
    appBar: AppBar(title: Text(AppLocalizations.of(context).wdMemoryBook)),
    body: const SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: CompanionMemoryCollection(),
      ),
    ),
  );
}

/// No internal scroll view: the real wardrobe panel owns the available height.
class CompanionMemoryCollection extends StatefulWidget {
  const CompanionMemoryCollection({super.key});

  @override
  State<CompanionMemoryCollection> createState() =>
      _CompanionMemoryCollectionState();
}

class _CompanionMemoryCollectionState extends State<CompanionMemoryCollection> {
  final _store = CompanionStoryProgress.instance;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_store.loaded) await _store.load();
    // App startup already loads legacy memories. Preview must never migrate them.
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _openEpisode(CompanionEpisode episode) async {
    final preview = CompanionStoryPreview.active;
    if (!preview && !_store.state.completed.containsKey(episode.id)) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CompanionDialoguePage(
          episode: episode,
          preview: preview,
          replay: !preview,
          onFinish: preview ? null : (_) => _store.markRead(episode.id),
        ),
      ),
    );
  }

  Future<void> _openSpecial(StoryEventSpec event) async {
    final preview = CompanionStoryPreview.active;
    final entries = preview
        ? [
            for (final spec in storyCatalog)
              StoryUnlock(spec.id, DateTime(2000)),
          ]
        : StoryStore.unlocked.value;
    final index = entries.indexWhere((entry) => entry.id == event.id);
    if (index < 0) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MemoryBookReader(
          entries: entries,
          initialIndex: index,
          preview: preview,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    if (!_ready) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: AppLoadingBar(),
        ),
      );
    }
    return ListenableBuilder(
      listenable: Listenable.merge([
        _store,
        CompanionStoryPreview.enabled,
        StoryStore.unlocked,
        StoryStore.unread,
      ]),
      builder: (context, _) {
        final preview = CompanionStoryPreview.active;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.csMemoryTitle,
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w800,
                color: AppInk.strong,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l.csMemorySubtitle,
              style: const TextStyle(height: 1.5, color: AppInk.soft),
            ),
            if (preview)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: _CollectionNotice(
                  text: l.csPreviewNotice,
                  icon: Icons.science_outlined,
                ),
              ),
            if (_store.loadError != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: _CollectionNotice(
                  text: l.csProgressError,
                  icon: Icons.info_outline_rounded,
                ),
              ),
            for (final kind in CompanionStoryKind.values) ...[
              _CollectionHeading(
                title: kind == CompanionStoryKind.main
                    ? l.csMainStories
                    : l.csDailyStories,
              ),
              for (final episode in companionEpisodes.where(
                (item) => item.kind == kind,
              ))
                Builder(
                  builder: (context) {
                    final record = _store.state.completed[episode.id];
                    final available = preview || record != null;
                    final active = _store.state.active?.episodeId == episode.id;
                    return _CollectionRow(
                      key: ValueKey('memory-${episode.id}'),
                      number: episode.id.split('_').last,
                      title: available
                          ? episode.title.resolve(language)
                          : l.csLocked,
                      subtitle: preview
                          ? '${episode.id} · ${record == null ? l.csPreviewState : l.csReplay}'
                          : record != null
                          ? '${record.firstCompletedAt} · ${record.read ? l.csRead : l.csUnread}'
                          : active
                          ? l.csResume
                          : l.csLockedHint,
                      locked: !available,
                      unread: !preview && record != null && !record.read,
                      onTap: available ? () => _openEpisode(episode) : null,
                    );
                  },
                ),
            ],
            _CollectionHeading(title: l.csSpecialStories),
            for (final event in storyCatalog)
              Builder(
                builder: (context) {
                  final matches = StoryStore.unlocked.value.where(
                    (entry) => entry.id == event.id,
                  );
                  final unlock = matches.isEmpty ? null : matches.first;
                  final available = preview || unlock != null;
                  return _CollectionRow(
                    key: ValueKey('memory-${event.id}'),
                    title: available ? event.title : l.csLocked,
                    subtitle: preview
                        ? l.csPreviewNotice
                        : unlock == null
                        ? MascotName.fill(event.unlockHint)
                        : '${unlock.date.year}-${unlock.date.month.toString().padLeft(2, '0')}-${unlock.date.day.toString().padLeft(2, '0')}',
                    cover: event.cover,
                    locked: !available,
                    unread:
                        !preview && StoryStore.unread.value.contains(event.id),
                    onTap: available ? () => _openSpecial(event) : null,
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

class _CollectionHeading extends StatelessWidget {
  const _CollectionHeading({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 28, 0, 10),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: AppInk.strong,
      ),
    ),
  );
}

class _CollectionNotice extends StatelessWidget {
  const _CollectionNotice({required this.text, required this.icon});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF3EBDE),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppInk.soft, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(height: 1.5, color: AppInk.strong),
          ),
        ),
      ],
    ),
  );
}

class _CollectionRow extends StatelessWidget {
  const _CollectionRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.locked,
    required this.unread,
    this.number,
    this.cover,
    this.onTap,
  });
  final String title, subtitle;
  final String? number, cover;
  final bool locked, unread;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: locked ? const Color(0x66FFFFFF) : const Color(0xFFFDF9F2),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 54,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0E8DC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: locked
                    ? const Icon(
                        Icons.lock_outline_rounded,
                        color: AppInk.iconFaint,
                        size: 19,
                      )
                    : cover != null
                    ? Image.asset(cover!, fit: BoxFit.cover)
                    : Center(
                        child: Text(
                          number ?? '',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF917451),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                        color: locked ? AppInk.soft : AppInk.strong,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: AppInk.soft,
                      ),
                    ),
                  ],
                ),
              ),
              if (unread)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Semantics(
                    label: AppLocalizations.of(context).csUnread,
                    child: const Icon(
                      Icons.circle,
                      size: 7,
                      color: Color(0xFFBB8560),
                    ),
                  ),
                ),
              if (!locked)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: AppInk.iconFaint,
                    size: 20,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
