import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/bgm_service.dart';
import '../utils/mascot.dart';
import '../utils/prefs_keys.dart';
import '../utils/sfx_service.dart';
import '../widgets/mascot_app_bar.dart';
import '../widgets/mascot_page_shell.dart';
import '../widgets/mascot_scene.dart';

const Color _kWardrobeAccent = Color(0xFFB56CC7);
const Color _kMusicAccent = Color(0xFF5A88D8);

enum _WardrobeSection { outfits, music }

enum _UnlockType { free, coin, subscriberCoin }

class WardrobePreviewController {
  static final ValueNotifier<String?> previewingTrackId = ValueNotifier(null);
  static String? _restoreAsset;

  static bool get isPreviewing => previewingTrackId.value != null;

  static Future<void> preview({
    required String trackId,
    required String asset,
    required String restoreAsset,
  }) async {
    _restoreAsset = restoreAsset;
    previewingTrackId.value = trackId;
    if (asset == restoreAsset) {
      await BgmService.instance.ensurePlaying(asset);
    } else {
      await BgmService.instance.play(asset);
    }
  }

  static Future<void> restore() async {
    final restoreAsset = _restoreAsset;
    if (previewingTrackId.value == null || restoreAsset == null) return;
    previewingTrackId.value = null;
    _restoreAsset = null;
    await BgmService.instance.play(restoreAsset);
  }
}

class WardrobePage extends StatefulWidget {
  const WardrobePage({super.key});

  @override
  State<WardrobePage> createState() => _WardrobePageState();
}

class _WardrobePageState extends State<WardrobePage> {
  _WardrobeSection _section = _WardrobeSection.outfits;
  String _selectedOutfitId = _outfitCatalog.first.id;
  Set<String> _ownedOutfitIds = {_outfitCatalog.first.id};
  Set<String> _ownedTrackIds = {_trackCatalog.first.id};
  List<String> _playlistTrackIds = [_trackCatalog.first.id];
  bool _loaded = false;

  _OutfitSpec get _selectedOutfit => _outfitCatalog.firstWhere(
    (outfit) => outfit.id == _selectedOutfitId,
    orElse: () => _outfitCatalog.first,
  );

  _MusicTrackSpec get _currentTrack => _trackById(
    _playlistTrackIds.isEmpty
        ? _trackCatalog.first.id
        : _playlistTrackIds.first,
  );

  String get _effectivePlaybackAsset => _currentTrack.assetPath;

  @override
  void initState() {
    super.initState();
    WardrobePreviewController.previewingTrackId.addListener(_onPreviewChanged);
    _load();
  }

  @override
  void dispose() {
    WardrobePreviewController.previewingTrackId.removeListener(
      _onPreviewChanged,
    );
    unawaited(WardrobePreviewController.restore());
    super.dispose();
  }

  void _onPreviewChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final ownedOutfits =
        (prefs.getStringList(PrefsKeys.wardrobeOwnedOutfits) ??
                const <String>[])
            .toSet()
          ..add(_outfitCatalog.first.id);
    final ownedTracks =
        (prefs.getStringList(PrefsKeys.bgmOwnedTracks) ?? const <String>[])
            .toSet()
          ..add(_trackCatalog.first.id);
    final selectedOutfit = prefs.getString(PrefsKeys.wardrobeSelectedOutfit);
    final selectedTrack = prefs.getString(PrefsKeys.bgmSelectedTrack);
    final playlist = prefs.getStringList(PrefsKeys.bgmPlaylist);
    final fallbackTrack = _safeTrackId(selectedTrack, ownedTracks);
    if (!mounted) return;
    setState(() {
      _ownedOutfitIds = ownedOutfits;
      _ownedTrackIds = ownedTracks;
      _selectedOutfitId = _safeOutfitId(selectedOutfit, ownedOutfits);
      _playlistTrackIds = _safePlaylist(playlist, ownedTracks, fallbackTrack);
      _loaded = true;
    });
  }

  Future<void> _saveOutfit(String outfitId) async {
    if (!_ownedOutfitIds.contains(outfitId)) return;
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.wardrobeSelectedOutfit, outfitId);
    if (!mounted) return;
    setState(() => _selectedOutfitId = outfitId);
    MascotPersona.set(MascotEmotion.happy.assetPath, '嗯...這套很好看。', force: true);
  }

  Future<void> _savePlaylist(
    List<String> next, {
    required bool updatePlayback,
  }) async {
    final previousAsset = _effectivePlaybackAsset;
    playHaptic(HapticLevel.selection);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(PrefsKeys.bgmPlaylist, next);
    await prefs.setString(PrefsKeys.bgmSelectedTrack, next.first);
    if (!mounted) return;
    setState(() => _playlistTrackIds = next);
    if (updatePlayback && previousAsset != _effectivePlaybackAsset) {
      await WardrobePreviewController.restore();
      unawaited(BgmService.instance.play(_effectivePlaybackAsset));
    }
  }

  Future<void> _addPlaylistTrack(_MusicTrackSpec track) async {
    if (!_ownedTrackIds.contains(track.id) ||
        _playlistTrackIds.contains(track.id)) {
      return;
    }
    await _savePlaylist([
      ..._playlistTrackIds,
      track.id,
    ], updatePlayback: false);
  }

  Future<void> _removePlaylistTrack(_MusicTrackSpec track) async {
    if (!_playlistTrackIds.contains(track.id) ||
        _playlistTrackIds.length == 1) {
      return;
    }
    final removedCurrent = _playlistTrackIds.first == track.id;
    final next = _playlistTrackIds.where((id) => id != track.id).toList();
    await _savePlaylist(next, updatePlayback: removedCurrent);
  }

  Future<void> _previewTrack(_MusicTrackSpec track) async {
    if (WardrobePreviewController.previewingTrackId.value == track.id) {
      await WardrobePreviewController.restore();
      return;
    }
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
    await WardrobePreviewController.preview(
      trackId: track.id,
      asset: track.assetPath,
      restoreAsset: _effectivePlaybackAsset,
    );
  }

  Future<void> _openTrackDetail(_MusicTrackSpec track) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _TrackDetailSheet(
        track: track,
        owned: _ownedTrackIds.contains(track.id),
        inPlaylist: _playlistTrackIds.contains(track.id),
        onPreview: () => _previewTrack(track),
        onAddToPlaylist: () async {
          await _addPlaylistTrack(track);
          if (sheetContext.mounted) Navigator.pop(sheetContext);
        },
      ),
    );
  }

  String _safeOutfitId(String? id, Set<String> owned) {
    if (id != null && owned.contains(id) && _outfitExists(id)) return id;
    return _outfitCatalog.first.id;
  }

  String _safeTrackId(String? id, Set<String> owned) {
    if (id != null && owned.contains(id) && _trackExists(id)) return id;
    return _trackCatalog.first.id;
  }

  List<String> _safePlaylist(
    List<String>? ids,
    Set<String> owned,
    String fallbackTrackId,
  ) {
    final safe = (ids ?? const <String>[])
        .where((id) => owned.contains(id) && _trackExists(id))
        .toList();
    return safe.isEmpty ? [fallbackTrackId] : safe;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFFFFF8F8),
      appBar: const MascotAppBar(accent: _kWardrobeAccent),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.56,
            child: const MascotSceneBackground(
              'assets/scenes/home/home_bg.png',
            ),
          ),
          SafeArea(
            child: MascotPageShell(
              accent: _kWardrobeAccent,
              scene: const PersonaScene(accent: _kWardrobeAccent),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  _SectionSwitch(
                    value: _section,
                    onChanged: (value) {
                      playHaptic(HapticLevel.selection);
                      setState(() => _section = value);
                    },
                  ),
                  const SizedBox(height: 14),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _section == _WardrobeSection.outfits
                        ? _buildOutfitSection()
                        : _buildMusicSection(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutfitSection() {
    return Column(
      key: const ValueKey('outfits'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WardrobeHeader(
          icon: Icons.checkroom_rounded,
          title: '兔咪造型',
          subtitle: '目前穿著：${_selectedOutfit.name}',
          trailing: '${_ownedOutfitIds.length}/${_outfitCatalog.length}',
          color: _kWardrobeAccent,
        ),
        const SizedBox(height: 12),
        for (final outfit in _outfitCatalog)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _OutfitCard(
              outfit: outfit,
              owned: _ownedOutfitIds.contains(outfit.id),
              selected: _selectedOutfitId == outfit.id,
              onWear: () => _saveOutfit(outfit.id),
            ),
          ),
      ],
    );
  }

  Widget _buildMusicSection() {
    final playlistTracks = _playlistTrackIds.map(_trackById).toList();
    return Column(
      key: const ValueKey('music'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MusicSummaryCard(
          currentTrack: _currentTrack,
          playlistCount: playlistTracks.length,
        ),
        const SizedBox(height: 14),
        _WardrobeHeader(
          icon: Icons.queue_music_rounded,
          title: '循環表',
          subtitle: '目前播放：${_currentTrack.title}',
          trailing: '${playlistTracks.length} 首',
          color: _kMusicAccent,
        ),
        const SizedBox(height: 10),
        _PlaylistCard(
          tracks: playlistTracks,
          onRemove: _removePlaylistTrack,
          onDetail: _openTrackDetail,
        ),
        const SizedBox(height: 14),
        _WardrobeHeader(
          icon: Icons.library_music_rounded,
          title: '曲庫',
          subtitle: '創作者資訊與試聽',
          trailing: '${_ownedTrackIds.length}/${_trackCatalog.length}',
          color: _kMusicAccent,
        ),
        const SizedBox(height: 10),
        for (final track in _trackCatalog)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _TrackCard(
              track: track,
              owned: _ownedTrackIds.contains(track.id),
              inPlaylist: _playlistTrackIds.contains(track.id),
              onPreview: () => _previewTrack(track),
              onDetail: () => _openTrackDetail(track),
              onAddToPlaylist: () => _addPlaylistTrack(track),
            ),
          ),
      ],
    );
  }
}

class _OutfitSpec {
  final String id;
  final String name;
  final String subtitle;
  final String assetPath;
  final _UnlockType unlockType;
  final int coinPrice;

  const _OutfitSpec({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.assetPath,
    required this.unlockType,
    required this.coinPrice,
  });
}

class _MusicTrackSpec {
  final String id;
  final String title;
  final String artistName;
  final String channelName;
  final String sourceUrl;
  final String channelUrl;
  final String assetPath;
  final String durationLabel;
  final Color color;
  final List<String> tags;
  final _UnlockType unlockType;
  final int coinPrice;
  final String licenseNote;
  final String attributionText;

  const _MusicTrackSpec({
    required this.id,
    required this.title,
    required this.artistName,
    required this.channelName,
    required this.sourceUrl,
    required this.channelUrl,
    required this.assetPath,
    required this.durationLabel,
    required this.color,
    required this.tags,
    required this.unlockType,
    required this.coinPrice,
    required this.licenseNote,
    required this.attributionText,
  });
}

const List<_OutfitSpec> _outfitCatalog = [
  _OutfitSpec(
    id: 'tumi_original',
    name: '原始兔咪',
    subtitle: '最早陪你開始的樣子',
    assetPath: 'assets/mascot/core/tumi_neutral_front.png',
    unlockType: _UnlockType.free,
    coinPrice: 0,
  ),
];

const List<_MusicTrackSpec> _trackCatalog = [
  _MusicTrackSpec(
    id: 'bgm_main',
    title: '兔咪的房間',
    artistName: '待補創作者',
    channelName: 'YouTube 免費版權音樂',
    sourceUrl: '待補來源連結',
    channelUrl: '待補頻道連結',
    assetPath: 'sounds/bgm_main.m4a',
    durationLabel: '循環曲',
    color: _kMusicAccent,
    tags: ['預設', '安靜', '日常'],
    unlockType: _UnlockType.free,
    coinPrice: 0,
    licenseNote: '作者已聲明可自由使用；仍建議保留來源連結、下載日期與授權截圖。',
    attributionText: '目前不強制標註，但在音樂盒保留創作者資訊作為感謝。',
  ),
];

bool _outfitExists(String id) =>
    _outfitCatalog.any((outfit) => outfit.id == id);

bool _trackExists(String id) => _trackCatalog.any((track) => track.id == id);

_MusicTrackSpec _trackById(String id) => _trackCatalog.firstWhere(
  (track) => track.id == id,
  orElse: () => _trackCatalog.first,
);

String _unlockLabel(_UnlockType type, int coinPrice) => switch (type) {
  _UnlockType.free => '已擁有',
  _UnlockType.coin => '$coinPrice 金幣',
  _UnlockType.subscriberCoin => '訂閱後 $coinPrice 金幣',
};

class _SectionSwitch extends StatelessWidget {
  final _WardrobeSection value;
  final ValueChanged<_WardrobeSection> onChanged;

  const _SectionSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF7F2),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          _sectionButton(
            section: _WardrobeSection.outfits,
            icon: Icons.checkroom_rounded,
            label: '造型',
          ),
          _sectionButton(
            section: _WardrobeSection.music,
            icon: Icons.music_note_rounded,
            label: '音樂盒',
          ),
        ],
      ),
    );
  }

  Widget _sectionButton({
    required _WardrobeSection section,
    required IconData icon,
    required String label,
  }) {
    final selected = value == section;
    final color = section == _WardrobeSection.outfits
        ? _kWardrobeAccent
        : _kMusicAccent;
    return Expanded(
      child: InkWell(
        onTap: () => onChanged(section),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected ? AppShadows.flat : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: selected ? color : AppInk.soft),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: selected ? color : AppInk.soft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WardrobeHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;
  final Color color;

  const _WardrobeHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppInk.strong,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppInk.soft,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        _SoftPill(text: trailing, color: color),
      ],
    );
  }
}

class _OutfitCard extends StatelessWidget {
  final _OutfitSpec outfit;
  final bool owned;
  final bool selected;
  final VoidCallback onWear;

  const _OutfitCard({
    required this.outfit,
    required this.owned,
    required this.selected,
    required this.onWear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppCardStyle.radius),
        border: Border.all(
          color: selected
              ? _kWardrobeAccent.withValues(alpha: 0.36)
              : const Color(0x0A46342B),
          width: selected ? 1.4 : 1,
        ),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _kWardrobeAccent.withValues(alpha: 0.12),
                  const Color(0xFFFFF5FB),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Image.asset(outfit.assetPath, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        outfit.name,
                        style: const TextStyle(
                          color: AppInk.strong,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (selected)
                      const _SoftPill(text: '穿著中', color: _kWardrobeAccent),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  outfit.subtitle,
                  style: const TextStyle(
                    color: AppInk.soft,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                _PrimaryMiniButton(
                  label: selected
                      ? '已套用'
                      : owned
                      ? '套用'
                      : _unlockLabel(outfit.unlockType, outfit.coinPrice),
                  icon: selected
                      ? Icons.check_rounded
                      : Icons.checkroom_rounded,
                  color: _kWardrobeAccent,
                  enabled: owned && !selected,
                  onTap: onWear,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MusicSummaryCard extends StatelessWidget {
  final _MusicTrackSpec currentTrack;
  final int playlistCount;

  const _MusicSummaryCard({
    required this.currentTrack,
    required this.playlistCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _kMusicAccent.withValues(alpha: 0.14),
            const Color(0xFFF4F7FF),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppCardStyle.radius),
        border: Border.all(color: _kMusicAccent.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          _TrackCover(track: currentTrack, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '目前音樂',
                  style: TextStyle(
                    color: AppInk.soft,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  currentTrack.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppInk.strong,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          _SoftPill(text: '循環 $playlistCount 首', color: _kMusicAccent),
        ],
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final List<_MusicTrackSpec> tracks;
  final ValueChanged<_MusicTrackSpec> onRemove;
  final ValueChanged<_MusicTrackSpec> onDetail;

  const _PlaylistCard({
    required this.tracks,
    required this.onRemove,
    required this.onDetail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppCardStyle.radius),
        border: AppCardStyle.hairline,
        boxShadow: AppShadows.flat,
      ),
      child: Column(
        children: [
          for (var i = 0; i < tracks.length; i++)
            _PlaylistRow(
              index: i + 1,
              track: tracks[i],
              removable: tracks.length > 1,
              onRemove: () => onRemove(tracks[i]),
              onDetail: () => onDetail(tracks[i]),
            ),
        ],
      ),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  final int index;
  final _MusicTrackSpec track;
  final bool removable;
  final VoidCallback onRemove;
  final VoidCallback onDetail;

  const _PlaylistRow({
    required this.index,
    required this.track,
    required this.removable,
    required this.onRemove,
    required this.onDetail,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onDetail,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Text(
                '$index',
                style: AppType.digits(
                  fontSize: 15,
                  color: AppInk.faint,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 10),
              _TrackCover(track: track, size: 34),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppInk.strong,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: removable ? onRemove : null,
                icon: const Icon(Icons.close_rounded, size: 18),
                color: AppInk.iconFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackCard extends StatelessWidget {
  final _MusicTrackSpec track;
  final bool owned;
  final bool inPlaylist;
  final VoidCallback onPreview;
  final VoidCallback onDetail;
  final VoidCallback onAddToPlaylist;

  const _TrackCard({
    required this.track,
    required this.owned,
    required this.inPlaylist,
    required this.onPreview,
    required this.onDetail,
    required this.onAddToPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: WardrobePreviewController.previewingTrackId,
      builder: (_, previewingId, _) {
        final previewing = previewingId == track.id;
        return Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppCardStyle.radius),
            border: Border.all(
              color: previewing
                  ? _kMusicAccent.withValues(alpha: 0.42)
                  : const Color(0x0A46342B),
              width: previewing ? 1.4 : 1,
            ),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  _TrackCover(track: track, size: 54),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppInk.strong,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artistName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppInk.soft,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: [
                            for (final tag in track.tags)
                              _TinyTag(text: tag, color: track.color),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onDetail,
                    icon: const Icon(Icons.info_outline_rounded),
                    color: AppInk.iconFaint,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _PrimaryMiniButton(
                      label: previewing ? '停止試聽' : '試聽',
                      icon: previewing
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                      color: _kMusicAccent,
                      onTap: onPreview,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PrimaryMiniButton(
                      label: inPlaylist ? '已加入' : '加入循環',
                      icon: inPlaylist
                          ? Icons.check_rounded
                          : Icons.playlist_add_rounded,
                      color: _kMusicAccent,
                      enabled: owned && !inPlaylist,
                      onTap: onAddToPlaylist,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TrackDetailSheet extends StatelessWidget {
  final _MusicTrackSpec track;
  final bool owned;
  final bool inPlaylist;
  final VoidCallback onPreview;
  final VoidCallback onAddToPlaylist;

  const _TrackDetailSheet({
    required this.track,
    required this.owned,
    required this.inPlaylist,
    required this.onPreview,
    required this.onAddToPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8DDD4),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _TrackCover(track: track, size: 66),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          style: const TextStyle(
                            color: AppInk.strong,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artistName,
                          style: const TextStyle(
                            color: AppInk.soft,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    color: AppInk.iconFaint,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _InfoLine(
                icon: Icons.account_circle_rounded,
                label: '頻道',
                value: track.channelName,
              ),
              _InfoLine(
                icon: Icons.link_rounded,
                label: '來源',
                value: track.sourceUrl,
              ),
              _InfoLine(
                icon: Icons.schedule_rounded,
                label: '長度',
                value: track.durationLabel,
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF7F2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '創作者資訊',
                      style: TextStyle(
                        color: AppInk.strong,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      track.licenseNote,
                      style: const TextStyle(
                        color: AppInk.soft,
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      track.attributionText,
                      style: const TextStyle(
                        color: AppInk.faint,
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              ValueListenableBuilder<String?>(
                valueListenable: WardrobePreviewController.previewingTrackId,
                builder: (_, previewingId, _) {
                  final previewing = previewingId == track.id;
                  return Row(
                    children: [
                      Expanded(
                        child: _PrimaryMiniButton(
                          label: previewing ? '停止試聽' : '試聽全曲',
                          icon: previewing
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                          color: _kMusicAccent,
                          onTap: onPreview,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _PrimaryMiniButton(
                          label: inPlaylist ? '已加入循環' : '加入循環',
                          icon: inPlaylist
                              ? Icons.check_rounded
                              : Icons.playlist_add_rounded,
                          color: _kMusicAccent,
                          enabled: owned && !inPlaylist,
                          onTap: onAddToPlaylist,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Icon(icon, size: 17, color: _kMusicAccent),
          const SizedBox(width: 7),
          SizedBox(
            width: 40,
            child: Text(
              label,
              style: const TextStyle(
                color: AppInk.soft,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppInk.strong,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackCover extends StatelessWidget {
  final _MusicTrackSpec track;
  final double size;

  const _TrackCover({required this.track, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            track.color.withValues(alpha: 0.78),
            const Color(0xFFE7F0FF),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: Icon(
        Icons.music_note_rounded,
        color: Colors.white,
        size: size * 0.46,
      ),
    );
  }
}

class _PrimaryMiniButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _PrimaryMiniButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? color.withValues(alpha: 0.11) : const Color(0xFFF4EEE8),
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: enabled ? color : AppInk.faint),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: enabled ? color : AppInk.faint,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SoftPill extends StatelessWidget {
  final String text;
  final Color color;

  const _SoftPill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _TinyTag extends StatelessWidget {
  final String text;
  final Color color;

  const _TinyTag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
