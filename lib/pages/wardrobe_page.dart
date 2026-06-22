import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/audio_settings_service.dart';
import '../utils/bgm_service.dart';
import '../utils/coin_service.dart';
import '../utils/mascot.dart';
import '../utils/sfx_service.dart';
import '../utils/wardrobe_catalog.dart';
import '../utils/wardrobe_store.dart';
import '../widgets/mascot_app_bar.dart';
import '../widgets/mascot_page_shell.dart';
import '../widgets/mascot_scene.dart';

enum _WardrobeSection { outfits, music }

// 試聽控制器：暫時切到試聽曲，離開頁面 / 停止時還原成原本的目前曲。
// 衣櫃在 IndexedStack 裡不會 dispose，所以切頁時由 main.dart 的 _onTabTapped
// 呼叫 restore()；dispose 再保險一次。
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
    // 一律走 play()：它同步把 _intendedAsset 切成這首，且「已在播同一首」會自動
    // no-op（不會打斷正在當背景音樂的目前曲）。不能用 ensurePlaying：剛試聽過別首
    // 時 BgmService 的 intent 還停在別首，ensurePlaying 會判定「別人有不同 intent」
    // 而 bail，造成按了目前曲（= restoreAsset）的試聽卻仍放著別首歌。
    await BgmService.instance.play(asset);
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
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    unawaited(WardrobePreviewController.restore());
    super.dispose();
  }

  Future<void> _load() async {
    await WardrobeStore.load();
    if (!mounted) return;
    setState(() => _loaded = true);
  }

  // ── 造型 ───────────────────────────────────────────────
  Future<void> _wearOutfit(OutfitSpec outfit) async {
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
    await WardrobeStore.setOutfit(outfit.id);
    MascotPersona.set(MascotEmotion.happy.assetPath, '嗯...這套很好看。', force: true);
  }

  Future<void> _buyOutfit(OutfitSpec outfit) async {
    if (!await _confirmPurchase(
      outfit.name,
      outfit.unlockType,
      outfit.coinPrice,
    )) {
      return;
    }
    final result = await WardrobeStore.purchaseOutfit(outfit.id);
    if (!mounted) return;
    if (result == PurchaseResult.success) {
      playFeedback(SfxCue.success);
      await WardrobeStore.setOutfit(outfit.id);
      MascotPersona.set(
        MascotEmotion.happy.assetPath,
        '謝謝你...我很喜歡。',
        force: true,
      );
      _toast('已解鎖並換上 ${outfit.name}');
    } else {
      _reportPurchaseFail(result);
    }
  }

  // ── 音樂 ───────────────────────────────────────────────
  Future<void> _previewTrack(MusicTrackSpec track) async {
    if (WardrobePreviewController.previewingTrackId.value == track.id) {
      await WardrobePreviewController.restore();
      return;
    }
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
    await WardrobePreviewController.preview(
      trackId: track.id,
      asset: track.assetPath,
      restoreAsset: WardrobeStore.currentTrackAsset,
    );
  }

  Future<void> _addTrack(MusicTrackSpec track) async {
    playHaptic(HapticLevel.selection);
    await WardrobeStore.addTrack(track.id);
  }

  Future<void> _setCurrentTrack(MusicTrackSpec track) async {
    playHaptic(HapticLevel.selection);
    final changed = await WardrobeStore.setCurrentTrack(track.id);
    _applyCurrentTrackChange(changed);
  }

  Future<void> _removeTrack(MusicTrackSpec track) async {
    playHaptic(HapticLevel.selection);
    final changed = await WardrobeStore.removeTrack(track.id);
    _applyCurrentTrackChange(changed);
  }

  Future<void> _reorderPlaylist(int oldIndex, int newIndex) async {
    playHaptic(HapticLevel.selection);
    // ReorderableListView 的 newIndex 是「移除前」的位置，往後移要 -1。
    if (newIndex > oldIndex) newIndex -= 1;
    await WardrobeStore.reorder(oldIndex, newIndex);
  }

  // 循環模式輪切：單曲循環 → 列表循環 → 隨機 → …
  Future<void> _cyclePlayMode() async {
    playHaptic(HapticLevel.selection);
    const order = [PlayMode.loopOne, PlayMode.loopAll, PlayMode.shuffle];
    final cur = WardrobeStore.playMode.value;
    await WardrobeStore.setPlayMode(
      order[(order.indexOf(cur) + 1) % order.length],
    );
  }

  // 暫停 / 繼續：複用全域 BGM 靜音（本就是淡出＋pause/resume），不另開狀態。
  Future<void> _togglePause() async {
    playHaptic(HapticLevel.selection);
    await BgmService.instance.setMuted(!AudioSettingsService.musicMuted.value);
  }

  // 目前曲改變時：清掉試聽狀態並直接切到新的目前曲。
  // 兩個 play 不阻塞，靠 BgmService 既有的 intent/requestId 並發互讓收斂到新曲，
  // 避免試聽中先把舊曲淡入數秒才換歌。
  void _applyCurrentTrackChange(bool changed) {
    if (!mounted || !changed) return;
    unawaited(WardrobePreviewController.restore());
    unawaited(BgmService.instance.play(WardrobeStore.currentTrackAsset));
  }

  Future<void> _buyTrack(MusicTrackSpec track) async {
    if (!await _confirmPurchase(
      track.title,
      track.unlockType,
      track.coinPrice,
    )) {
      return;
    }
    final result = await WardrobeStore.purchaseTrack(track.id);
    if (!mounted) return;
    if (result == PurchaseResult.success) {
      playFeedback(SfxCue.success);
      _toast('已解鎖 ${track.title}');
    } else {
      _reportPurchaseFail(result);
    }
  }

  Future<void> _openTrackDetail(MusicTrackSpec track) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _TrackDetailSheet(
        track: track,
        owned: WardrobeStore.ownedTracks.value.contains(track.id),
        inPlaylist: WardrobeStore.playlist.value.contains(track.id),
        isCurrent: WardrobeStore.currentTrack.id == track.id,
        onPreview: () => _previewTrack(track),
        onBuy: () async {
          Navigator.pop(sheetContext);
          await _buyTrack(track);
        },
        onAddToPlaylist: () async {
          await _addTrack(track);
          if (sheetContext.mounted) Navigator.pop(sheetContext);
        },
        onSetCurrent: () async {
          await _setCurrentTrack(track);
          if (sheetContext.mounted) Navigator.pop(sheetContext);
        },
      ),
    );
  }

  // ── 購買共用 ───────────────────────────────────────────
  Future<bool> _confirmPurchase(String name, UnlockType type, int price) async {
    if (type == UnlockType.subscriberCoin && !WardrobeStore.isSubscriber) {
      _toast('這個項目需要訂閱才能解鎖');
      return false;
    }
    final balance = CoinService.notifier.value;
    final affordable = balance >= price;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('解鎖項目'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('要花 $price 金幣解鎖「$name」嗎？'),
            const SizedBox(height: 8),
            Text(
              affordable ? '目前金幣：$balance' : '目前金幣：$balance（不足）',
              style: TextStyle(
                color: affordable ? AppInk.soft : Colors.red.shade600,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text('取消', style: TextStyle(color: Colors.grey.shade600)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: kWardrobeAccent,
              minimumSize: const Size(0, 46),
            ),
            onPressed: affordable ? () => Navigator.pop(dialogCtx, true) : null,
            icon: const Icon(Icons.lock_open_rounded, size: 18),
            label: const Text('解鎖'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _reportPurchaseFail(PurchaseResult result) {
    playFeedback(SfxCue.cancel);
    _toast(switch (result) {
      PurchaseResult.needCoins => '金幣不足，先去完成習慣賺金幣吧',
      PurchaseResult.needSubscription => '這個項目需要訂閱才能解鎖',
      _ => '無法解鎖',
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFFFFF8F8),
      appBar: const MascotAppBar(accent: kWardrobeAccent),
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
              accent: kWardrobeAccent,
              scene: const PersonaScene(accent: kWardrobeAccent),
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  WardrobeStore.selectedOutfit,
                  WardrobeStore.ownedOutfits,
                  WardrobeStore.playlist,
                  WardrobeStore.currentTrackId,
                  WardrobeStore.playMode,
                  WardrobeStore.ownedTracks,
                  CoinService.notifier,
                ]),
                builder: (context, _) => ListView(
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
          ),
        ],
      ),
    );
  }

  Widget _buildOutfitSection() {
    final owned = WardrobeStore.ownedOutfits.value;
    final selectedId = WardrobeStore.selectedOutfit.value;
    return Column(
      key: const ValueKey('outfits'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WardrobeHeader(
          icon: Icons.checkroom_rounded,
          title: '兔咪造型',
          subtitle: '目前穿著：${outfitById(selectedId).name}',
          trailing: '${owned.length}/${outfitCatalog.length}',
          color: kWardrobeAccent,
        ),
        const SizedBox(height: 12),
        for (final outfit in outfitCatalog)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _OutfitCard(
              outfit: outfit,
              owned: owned.contains(outfit.id),
              selected: selectedId == outfit.id,
              onWear: () => _wearOutfit(outfit),
              onBuy: () => _buyOutfit(outfit),
            ),
          ),
      ],
    );
  }

  Widget _buildMusicSection() {
    final playlistIds = WardrobeStore.playlist.value;
    final ownedTracks = WardrobeStore.ownedTracks.value;
    final playlistTracks = playlistIds.map(trackById).toList();
    final current = WardrobeStore.currentTrack;
    return Column(
      key: const ValueKey('music'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MusicSummaryCard(
          currentTrack: current,
          playlistCount: playlistTracks.length,
          onTogglePause: _togglePause,
          onStopPreview: WardrobePreviewController.restore,
        ),
        const SizedBox(height: 12),
        _PlaylistCard(
          tracks: playlistTracks,
          currentId: current.id,
          playMode: WardrobeStore.playMode.value,
          onCyclePlayMode: _cyclePlayMode,
          onRemove: _removeTrack,
          onSetCurrent: _setCurrentTrack,
          onReorder: _reorderPlaylist,
          onDetail: _openTrackDetail,
        ),
        const SizedBox(height: 16),
        _WardrobeHeader(
          icon: Icons.library_music_rounded,
          title: '曲庫',
          subtitle: '依心情挑選',
          trailing: '${ownedTracks.length}/${trackCatalog.length}',
          color: kMusicAccent,
        ),
        _buildMoodGroup(MusicMood.relax),
        _buildMoodGroup(MusicMood.focus),
      ],
    );
  }

  Widget _buildMoodGroup(MusicMood mood) {
    final tracks = tracksOfMood(mood);
    return _MoodSection(
      mood: mood,
      previewTracks: tracks.take(3).toList(),
      tiles: [
        for (final track in tracks)
          _TrackGridCard(
            track: track,
            owned: WardrobeStore.ownedTracks.value.contains(track.id),
            inPlaylist: WardrobeStore.playlist.value.contains(track.id),
            isCurrent: WardrobeStore.currentTrack.id == track.id,
            onPreview: () => _previewTrack(track),
            onDetail: () => _openTrackDetail(track),
            onAddToPlaylist: () => _addTrack(track),
            onBuy: () => _buyTrack(track),
          ),
      ],
    );
  }
}

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
        ? kWardrobeAccent
        : kMusicAccent;
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
  final OutfitSpec outfit;
  final bool owned;
  final bool selected;
  final VoidCallback onWear;
  final VoidCallback onBuy;

  const _OutfitCard({
    required this.outfit,
    required this.owned,
    required this.selected,
    required this.onWear,
    required this.onBuy,
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
              ? kWardrobeAccent.withValues(alpha: 0.36)
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
                  kWardrobeAccent.withValues(alpha: 0.12),
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
                      const _SoftPill(text: '穿著中', color: kWardrobeAccent),
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
                      : unlockLabel(outfit.unlockType, outfit.coinPrice),
                  icon: selected
                      ? Icons.check_rounded
                      : owned
                      ? Icons.checkroom_rounded
                      : Icons.lock_open_rounded,
                  color: kWardrobeAccent,
                  enabled: !selected,
                  onTap: owned ? onWear : onBuy,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 「現在播放」常駐卡：永遠反映「實際出聲的是哪一首」。
// 試聽中 → 顯示試聽曲 +「試聽中」+ 停止鈕；否則 → 顯示目前曲 +「現在播放」+
// 暫停/繼續鈕（綁全域 BGM 靜音）。把「臨時試聽」與「常駐播放」在視覺上分清楚。
class _MusicSummaryCard extends StatelessWidget {
  final MusicTrackSpec currentTrack;
  final int playlistCount;
  final Future<void> Function() onTogglePause;
  final Future<void> Function() onStopPreview;

  const _MusicSummaryCard({
    required this.currentTrack,
    required this.playlistCount,
    required this.onTogglePause,
    required this.onStopPreview,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: WardrobePreviewController.previewingTrackId,
      builder: (_, previewingId, _) {
        final previewing = previewingId != null;
        final track = previewing ? trackById(previewingId) : currentTrack;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: previewing
                  ? [
                      const Color(0xFFE0894F).withValues(alpha: 0.16),
                      const Color(0xFFFFF6EE),
                    ]
                  : [
                      kMusicAccent.withValues(alpha: 0.14),
                      const Color(0xFFF4F7FF),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppCardStyle.radius),
            border: Border.all(
              color: (previewing ? const Color(0xFFE0894F) : kMusicAccent)
                  .withValues(alpha: 0.16),
            ),
          ),
          child: Row(
            children: [
              _TrackCover(track: track, size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          previewing
                              ? Icons.headphones_rounded
                              : Icons.graphic_eq_rounded,
                          size: 15,
                          color: previewing
                              ? const Color(0xFFE0894F)
                              : kMusicAccent,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          previewing ? '試聽中（暫時）' : '現在播放',
                          style: TextStyle(
                            color: previewing
                                ? const Color(0xFFB9763B)
                                : AppInk.soft,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.title,
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
              const SizedBox(width: 8),
              if (previewing)
                _RoundIconButton(
                  icon: Icons.stop_rounded,
                  color: const Color(0xFFE0894F),
                  tooltip: '停止試聽',
                  onTap: () => unawaited(onStopPreview()),
                )
              else
                ValueListenableBuilder<bool>(
                  valueListenable: AudioSettingsService.musicMuted,
                  builder: (_, muted, _) => _RoundIconButton(
                    icon: muted
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                    color: kMusicAccent,
                    tooltip: muted ? '繼續播放' : '暫停',
                    onTap: () => unawaited(onTogglePause()),
                  ),
                ),
              const SizedBox(width: 6),
              _SoftPill(text: '$playlistCount 首', color: kMusicAccent),
            ],
          ),
        );
      },
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final List<MusicTrackSpec> tracks;
  final String currentId;
  final PlayMode playMode;
  final VoidCallback onCyclePlayMode;
  final ValueChanged<MusicTrackSpec> onRemove;
  final ValueChanged<MusicTrackSpec> onSetCurrent;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<MusicTrackSpec> onDetail;

  const _PlaylistCard({
    required this.tracks,
    required this.currentId,
    required this.playMode,
    required this.onCyclePlayMode,
    required this.onRemove,
    required this.onSetCurrent,
    required this.onReorder,
    required this.onDetail,
  });

  @override
  Widget build(BuildContext context) {
    final reorderable = tracks.length > 1;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppCardStyle.radius),
        border: AppCardStyle.hairline,
        boxShadow: AppShadows.flat,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: kMusicAccent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.queue_music_rounded,
                  color: kMusicAccent,
                  size: 17,
                ),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  '播放清單',
                  style: TextStyle(
                    color: AppInk.strong,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _PlayModeButton(mode: playMode, onTap: onCyclePlayMode),
            ],
          ),
          const SizedBox(height: 4),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            padding: EdgeInsets.zero,
            itemCount: tracks.length,
            onReorder: onReorder,
            itemBuilder: (_, i) => _PlaylistRow(
              key: ValueKey(tracks[i].id),
              index: i,
              track: tracks[i],
              isCurrent: tracks[i].id == currentId,
              removable: reorderable,
              reorderable: reorderable,
              onRemove: () => onRemove(tracks[i]),
              onSetCurrent: () => onSetCurrent(tracks[i]),
              onDetail: () => onDetail(tracks[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  final int index;
  final MusicTrackSpec track;
  final bool isCurrent;
  final bool removable;
  final bool reorderable;
  final VoidCallback onRemove;
  final VoidCallback onSetCurrent;
  final VoidCallback onDetail;

  const _PlaylistRow({
    super.key,
    required this.index,
    required this.track,
    required this.isCurrent,
    required this.removable,
    required this.reorderable,
    required this.onRemove,
    required this.onSetCurrent,
    required this.onDetail,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isCurrent
          ? kMusicAccent.withValues(alpha: 0.07)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onDetail,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              if (reorderable)
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 20,
                      color: AppInk.iconFaint,
                    ),
                  ),
                )
              else
                const SizedBox(width: 8),
              const SizedBox(width: 6),
              _TrackCover(track: track, size: 34),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppInk.strong,
                    fontSize: 13.5,
                    fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w800,
                  ),
                ),
              ),
              if (isCurrent)
                const _SoftPill(text: '播放中', color: kMusicAccent)
              else
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onSetCurrent,
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  color: kMusicAccent,
                  tooltip: '設為目前播放',
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: removable ? onRemove : null,
                icon: const Icon(Icons.close_rounded, size: 18),
                color: AppInk.iconFaint,
                tooltip: '從清單移除',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 循環模式切換鈕：顯示目前模式（圖示＋字），點一下輪切到下一個模式。
class _PlayModeButton extends StatelessWidget {
  final PlayMode mode;
  final VoidCallback onTap;

  const _PlayModeButton({required this.mode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final icon = switch (mode) {
      PlayMode.loopOne => Icons.repeat_one_rounded,
      PlayMode.loopAll => Icons.repeat_rounded,
      PlayMode.shuffle => Icons.shuffle_rounded,
    };
    return Material(
      color: kMusicAccent.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: kMusicAccent),
              const SizedBox(width: 5),
              Text(
                playModeLabel(mode),
                style: const TextStyle(
                  color: kMusicAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 圓形圖示鈕（現在播放卡的暫停 / 停止試聽用）。
class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _RoundIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: 0.14),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 22, color: color),
          ),
        ),
      ),
    );
  }
}

// 曲庫的可收合心情分區（悠閒感／專注感）。標題列可點收合，內容是
// 一排兩格的方形專輯牆。收合狀態存在自己的 State，IndexedStack/反應式
// 重建都會保留（位置穩定）。
class _MoodSection extends StatefulWidget {
  final MusicMood mood;
  final List<MusicTrackSpec> previewTracks;
  final List<Widget> tiles;

  const _MoodSection({
    required this.mood,
    required this.previewTracks,
    required this.tiles,
  });

  @override
  State<_MoodSection> createState() => _MoodSectionState();
}

class _MoodSectionState extends State<_MoodSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final relax = widget.mood == MusicMood.relax;
    final color = relax ? const Color(0xFF5A88D8) : const Color(0xFFE0894F);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              playHaptic(HapticLevel.selection);
              setState(() => _expanded = !_expanded);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: _expanded ? 0.12 : 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.14)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      relax ? Icons.spa_rounded : Icons.bolt_rounded,
                      size: 18,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          moodLabel(widget.mood),
                          style: const TextStyle(
                            color: AppInk.strong,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          _moodCaption(widget.mood),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppInk.soft,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SoftPill(text: '${widget.tiles.length} 首', color: color),
                  const SizedBox(width: 7),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 21,
                        color: color.withValues(alpha: 0.82),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedCrossFade(
          firstChild: _TrackGrid(tiles: widget.tiles),
          secondChild: _CollapsedTrackPreview(
            tracks: widget.previewTracks,
            color: color,
          ),
          crossFadeState: _expanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 220),
          sizeCurve: Curves.easeInOutCubic,
        ),
      ],
    );
  }
}

String _moodCaption(MusicMood mood) => switch (mood) {
  MusicMood.relax => '慢一點、軟一點',
  MusicMood.focus => '穩定節奏、進入狀態',
};

class _CollapsedTrackPreview extends StatelessWidget {
  final List<MusicTrackSpec> tracks;
  final Color color;

  const _CollapsedTrackPreview({required this.tracks, required this.color});

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox(width: double.infinity);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.09)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < tracks.length; i++) ...[
            _TrackCover(track: tracks[i], size: 30),
            if (i != tracks.length - 1) const SizedBox(width: 6),
          ],
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              tracks.map((track) => track.title).join(' / '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppInk.soft,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 一排兩格的專輯牆。每格結構一致（方形封面＋單行曲名／作者＋固定高按鈕列），
// 同寬即同高，不必 IntrinsicHeight 也能對齊。
class _TrackGrid extends StatelessWidget {
  final List<Widget> tiles;

  const _TrackGrid({required this.tiles});

  @override
  Widget build(BuildContext context) {
    const gap = 11.0;
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      final hasNext = i + 1 < tiles.length;
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: i + 2 < tiles.length ? gap : 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: gap),
              Expanded(child: hasNext ? tiles[i + 1] : const SizedBox()),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

// 專輯小卡：方形封面（點 → 詳情＝創作者資訊）＋曲名／作者＋試聽／加入清單。
class _TrackGridCard extends StatelessWidget {
  final MusicTrackSpec track;
  final bool owned;
  final bool inPlaylist;
  final bool isCurrent;
  final VoidCallback onPreview;
  final VoidCallback onDetail;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onBuy;

  const _TrackGridCard({
    required this.track,
    required this.owned,
    required this.inPlaylist,
    required this.isCurrent,
    required this.onPreview,
    required this.onDetail,
    required this.onAddToPlaylist,
    required this.onBuy,
  });

  // 試聽鈕：試聽中→停止；（沒在試聽且）這首正是目前曲→「播放中」停用；其餘→試聽。
  Widget _previewButton(bool previewing, String? previewingId) {
    if (previewing) {
      return _PrimaryMiniButton(
        label: '停止',
        icon: Icons.stop_rounded,
        color: kMusicAccent,
        onTap: onPreview,
      );
    }
    if (previewingId == null && isCurrent) {
      return _PrimaryMiniButton(
        label: '播放中',
        icon: Icons.graphic_eq_rounded,
        color: kMusicAccent,
        enabled: false,
        onTap: () {},
      );
    }
    return _PrimaryMiniButton(
      label: '試聽',
      icon: Icons.play_arrow_rounded,
      color: kMusicAccent,
      onTap: onPreview,
    );
  }

  Widget _actionButton() {
    return _PrimaryMiniButton(
      label: owned
          ? (inPlaylist ? '已加入' : '加入')
          : unlockLabel(track.unlockType, track.coinPrice),
      icon: owned
          ? (inPlaylist ? Icons.check_rounded : Icons.playlist_add_rounded)
          : Icons.lock_open_rounded,
      color: kMusicAccent,
      enabled: !owned || !inPlaylist,
      onTap: owned ? onAddToPlaylist : onBuy,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: WardrobePreviewController.previewingTrackId,
      builder: (_, previewingId, _) {
        final previewing = previewingId == track.id;
        return Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppCardStyle.radius),
            border: Border.all(
              color: previewing
                  ? kMusicAccent.withValues(alpha: 0.42)
                  : const Color(0x0A46342B),
              width: previewing ? 1.4 : 1,
            ),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onDetail,
                behavior: HitTestBehavior.opaque,
                child: _SquareCover(
                  track: track,
                  isCurrent: isCurrent,
                  previewing: previewing,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppInk.strong,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                track.artistName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppInk.soft,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _previewButton(previewing, previewingId)),
                  const SizedBox(width: 6),
                  Expanded(child: _actionButton()),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// 方形 CD 封面（BoxFit.cover 把 16:9 原圖置中裁成方形）。目前正在當背景音樂
// 的那首，右下角顯示律動標記。
class _SquareCover extends StatelessWidget {
  final MusicTrackSpec track;
  final bool isCurrent;
  final bool previewing;

  const _SquareCover({
    required this.track,
    required this.isCurrent,
    required this.previewing,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _coverImage(),
            if (isCurrent && !previewing)
              const Positioned(right: 6, bottom: 6, child: _NowPlayingBadge()),
          ],
        ),
      ),
    );
  }

  Widget _coverImage() {
    final cover = track.coverAsset;
    if (cover != null) {
      return Image.asset(
        cover,
        fit: BoxFit.cover,
        // 原圖 1280×720，方格只顯示中等尺寸；限制解碼寬度省記憶體。
        cacheWidth: 400,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            track.color.withValues(alpha: 0.78),
            const Color(0xFFE7F0FF),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.music_note_rounded, color: Colors.white, size: 34),
      ),
    );
  }
}

class _NowPlayingBadge extends StatelessWidget {
  const _NowPlayingBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: kMusicAccent,
        borderRadius: BorderRadius.circular(99),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.graphic_eq_rounded, size: 12, color: Colors.white),
          SizedBox(width: 3),
          Text(
            '播放中',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackDetailSheet extends StatelessWidget {
  final MusicTrackSpec track;
  final bool owned;
  final bool inPlaylist;
  final bool isCurrent;
  final VoidCallback onPreview;
  final VoidCallback onBuy;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onSetCurrent;

  const _TrackDetailSheet({
    required this.track,
    required this.owned,
    required this.inPlaylist,
    required this.isCurrent,
    required this.onPreview,
    required this.onBuy,
    required this.onAddToPlaylist,
    required this.onSetCurrent,
  });

  // 第二顆按鈕：未擁有→購買；已擁有未加入→加入；已加入非目前→設為目前；
  // 已是目前→停用顯示「目前播放中」。
  _PrimaryMiniButton _actionButton() {
    if (!owned) {
      return _PrimaryMiniButton(
        label: unlockLabel(track.unlockType, track.coinPrice),
        icon: Icons.lock_open_rounded,
        color: kMusicAccent,
        onTap: onBuy,
      );
    }
    if (!inPlaylist) {
      return _PrimaryMiniButton(
        label: '加入清單',
        icon: Icons.playlist_add_rounded,
        color: kMusicAccent,
        onTap: onAddToPlaylist,
      );
    }
    if (!isCurrent) {
      return _PrimaryMiniButton(
        label: '設為目前播放',
        icon: Icons.play_arrow_rounded,
        color: kMusicAccent,
        onTap: onSetCurrent,
      );
    }
    return _PrimaryMiniButton(
      label: '目前播放中',
      icon: Icons.graphic_eq_rounded,
      color: kMusicAccent,
      enabled: false,
      onTap: () {},
    );
  }

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
                onTap: track.sourceUrl.startsWith('http')
                    ? () => _openExternal(context, track.sourceUrl)
                    : null,
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
                  // 這首是不是正在出聲：試聽中的這首，或（沒在試聽時）目前曲。
                  final activeNow =
                      previewing || (previewingId == null && isCurrent);
                  return Column(
                    children: [
                      // 已購買且正在播放這首才顯示可拉的進度條
                      if (owned && activeNow) ...[
                        _TrackProgressBar(assetPath: track.assetPath),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: _PrimaryMiniButton(
                              label: previewing
                                  ? '停止試聽'
                                  : activeNow
                                  ? '播放中'
                                  : '試聽全曲',
                              icon: previewing
                                  ? Icons.stop_rounded
                                  : activeNow
                                  ? Icons.graphic_eq_rounded
                                  : Icons.play_arrow_rounded,
                              color: kMusicAccent,
                              // 「播放中」（目前曲、非試聽）停用，其餘可按
                              enabled: previewing || !activeNow,
                              onTap: onPreview,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: _actionButton()),
                        ],
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
  final VoidCallback? onTap;

  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final link = onTap != null;
    final valueArea = link
        ? Row(
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kMusicAccent,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    decoration: TextDecoration.underline,
                    decorationColor: kMusicAccent,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.open_in_new_rounded,
                size: 14,
                color: kMusicAccent,
              ),
            ],
          )
        : Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppInk.strong,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          );
    final row = Row(
      children: [
        Icon(icon, size: 17, color: kMusicAccent),
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
        Expanded(child: valueArea),
      ],
    );
    if (!link) {
      return Padding(padding: const EdgeInsets.only(bottom: 7), child: row);
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: row,
      ),
    );
  }
}

// 試聽進度條：綁 BgmService 的播放進度，可拖曳 seek。
// 只在「播放器目前確實載入這首」時可操作；否則顯示停用的 0:00 狀態。
class _TrackProgressBar extends StatefulWidget {
  final String assetPath;

  const _TrackProgressBar({required this.assetPath});

  @override
  State<_TrackProgressBar> createState() => _TrackProgressBarState();
}

class _TrackProgressBarState extends State<_TrackProgressBar> {
  double? _dragMs; // 拖曳中暫存，避免 stream 把滑桿拉回去

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final bgm = BgmService.instance;
    return StreamBuilder<Duration>(
      stream: bgm.positionStream,
      builder: (context, snapshot) {
        final onThisTrack = bgm.loadedAsset == widget.assetPath;
        final duration = onThisTrack
            ? (bgm.duration ?? Duration.zero)
            : Duration.zero;
        final totalMs = duration.inMilliseconds;
        final live = (snapshot.data ?? bgm.position).inMilliseconds;
        final posMs = onThisTrack
            ? live.clamp(0, totalMs == 0 ? 0 : totalMs)
            : 0;
        final maxMs = totalMs == 0 ? 1.0 : totalMs.toDouble();
        final value = (_dragMs ?? posMs.toDouble()).clamp(0.0, maxMs);
        final seekable = onThisTrack && totalMs > 0;
        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 13),
                activeTrackColor: kMusicAccent,
                inactiveTrackColor: kMusicAccent.withValues(alpha: 0.18),
                thumbColor: kMusicAccent,
              ),
              child: Slider(
                value: value,
                max: maxMs,
                onChanged: seekable ? (v) => setState(() => _dragMs = v) : null,
                onChangeEnd: seekable
                    ? (v) {
                        bgm.seek(Duration(milliseconds: v.round()));
                        setState(() => _dragMs = null);
                      }
                    : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _fmt(Duration(milliseconds: value.round())),
                    style: const TextStyle(
                      color: AppInk.soft,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _fmt(duration),
                    style: const TextStyle(
                      color: AppInk.soft,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// 確認後用瀏覽器開啟外部連結（離開 App）。
Future<void> _openExternal(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: const Text('開啟外部連結'),
      content: Text('將離開 App，用瀏覽器開啟：\n$url'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, false),
          child: Text('取消', style: TextStyle(color: Colors.grey.shade600)),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: kMusicAccent),
          onPressed: () => Navigator.pop(dialogCtx, true),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: const Text('開啟'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('open external link failed: $e');
  }
}

class _TrackCover extends StatelessWidget {
  final MusicTrackSpec track;
  final double size;

  const _TrackCover({required this.track, required this.size});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.25);
    final cover = track.coverAsset;
    if (cover != null) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.asset(
          cover,
          width: size,
          height: size,
          fit: BoxFit.cover,
          // 封面原圖 1280×720，但只顯示小尺寸；限制解碼寬度省記憶體（3x 供高解析螢幕）。
          cacheWidth: (size * 3).round(),
          errorBuilder: (_, _, _) => _fallback(radius),
        ),
      );
    }
    return _fallback(radius);
  }

  Widget _fallback(BorderRadius radius) {
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
        borderRadius: radius,
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
