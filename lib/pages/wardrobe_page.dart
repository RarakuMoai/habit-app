import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/audio_settings_service.dart';
import '../utils/bgm_service.dart';
import '../utils/coin_service.dart';
import '../utils/mascot.dart';
import '../utils/sfx_service.dart';
import '../utils/story_catalog.dart';
import '../utils/story_store.dart';
import '../utils/wardrobe_catalog.dart';
import '../utils/wardrobe_store.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/mascot_app_bar.dart';
import '../widgets/mascot_page_shell.dart';
import '../widgets/mascot_scene.dart';
import '../widgets/reorder_jiggle.dart';
import 'home/room_metrics.dart';
import 'memory_book_reader.dart';

enum _WardrobeSection { outfits, music, memories }

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

class _WardrobePageState extends State<WardrobePage>
    with SingleTickerProviderStateMixin {
  _WardrobeSection _section = _WardrobeSection.outfits;
  bool _loaded = false;

  // 播放清單「拖曳排序模式」：長按或 …→移動 進入，整列 Q 版抖動，底部出完成 bar。
  // 與習慣頁同一套互動（_Jiggle + Delayed/Immediate 拖曳辨識器）。
  bool _playlistEditMode = false;
  String? _selectedPlaylistTrackId;
  late final AnimationController _jiggleCtrl;

  @override
  void initState() {
    super.initState();
    _jiggleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _load();
  }

  @override
  void dispose() {
    _jiggleCtrl.dispose();
    unawaited(WardrobePreviewController.restore());
    super.dispose();
  }

  void _startMovingTracks() {
    if (_playlistEditMode) return;
    setState(() => _playlistEditMode = true);
    _jiggleCtrl.repeat();
    playFeedback(SfxCue.tap);
  }

  void _finishMovingTracks() {
    if (!_playlistEditMode) return;
    setState(() => _playlistEditMode = false);
    _jiggleCtrl
      ..stop()
      ..value = 0;
    playFeedback(SfxCue.tap);
  }

  Future<void> _load() async {
    await WardrobeStore.load();
    await StoryStore.load();
    if (!mounted) return;
    setState(() {
      _loaded = true;
    });
  }

  // ── 回憶 ───────────────────────────────────────────────
  Future<void> _openMemory(int index) async {
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MemoryBookReader(
          entries: StoryStore.unlocked.value,
          initialIndex: index,
        ),
      ),
    );
    if (mounted) setState(() {}); // 回來刷新（已讀狀態）
  }

  // ── 造型 ───────────────────────────────────────────────
  Future<void> _wearOutfit(OutfitSpec outfit) async {
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
    await WardrobeStore.setOutfit(outfit.id);
    MascotPersona.setForContext(
      MascotEmotion.smile.assetPath,
      MascotContext.headPet,
      speech: '嗯...這套很好看。',
      force: true,
    );
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
      playFeedback(SfxCue.unlock);
      await WardrobeStore.setOutfit(outfit.id);
      MascotPersona.setForContext(
        MascotEmotion.popHappy.assetPath,
        MascotContext.allDone,
        speech: '謝謝你...我很喜歡。',
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
    if (_selectedPlaylistTrackId == track.id) {
      _selectedPlaylistTrackId = null;
    }
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

  void _selectPlaylistTrack(MusicTrackSpec track) {
    if (_selectedPlaylistTrackId == track.id) return;
    playHaptic(HapticLevel.selection);
    setState(() => _selectedPlaylistTrackId = track.id);
  }

  // 明確按播放鈕才切歌／暫停／續播；點清單列本身只做選取。
  Future<void> _togglePlaylistTrackPlayback(MusicTrackSpec track) async {
    playHaptic(HapticLevel.selection);
    setState(() => _selectedPlaylistTrackId = track.id);
    final muted = AudioSettingsService.musicMuted.value;
    if (WardrobeStore.currentTrackId.value == track.id) {
      await BgmService.instance.setMuted(!muted);
      return;
    }
    final changed = await WardrobeStore.setCurrentTrack(track.id);
    if (muted) await BgmService.instance.setMuted(false);
    _applyCurrentTrackChange(changed);
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
      playFeedback(SfxCue.unlock);
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
            Text('要使用 $price 足跡幣解鎖「$name」嗎？'),
            const SizedBox(height: 8),
            Text(
              affordable ? '目前足跡幣：$balance' : '目前足跡幣：$balance（不足）',
              style: TextStyle(
                color: affordable ? AppInk.soft : Colors.red.shade600,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          dialogCancelAction(
            dialogCtx,
            onPressed: () => Navigator.pop(dialogCtx, false),
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
      PurchaseResult.needCoins => '足跡幣不足，每天回來看看兔咪就能慢慢累積',
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
            height: roomSceneHeight(MediaQuery.of(context).size.width),
            child: const MascotSceneBackground(
              'assets/scenes/wardrobe/wardrobe_bg.webp',
            ),
          ),
          SafeArea(
            child: MascotPageShell(
              accent: kWardrobeAccent,
              sceneHeight: sceneRegionHeightAnchored(
                MediaQuery.of(context).size.width,
                MediaQuery.of(context).padding.top,
              ),
              scene: const PersonaScene(accent: kWardrobeAccent),
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  WardrobeStore.selectedOutfit,
                  WardrobeStore.ownedOutfits,
                  WardrobeStore.playlist,
                  WardrobeStore.currentTrackId,
                  WardrobeStore.playMode,
                  WardrobeStore.ownedTracks,
                  AudioSettingsService.musicMuted,
                  CoinService.notifier,
                  StoryStore.unlocked,
                  StoryStore.unread,
                ]),
                builder: (context, _) => ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    _SectionSwitch(
                      value: _section,
                      hasUnreadMemories: StoryStore.hasUnread,
                      onChanged: (value) {
                        playHaptic(HapticLevel.selection);
                        setState(() => _section = value);
                      },
                    ),
                    const SizedBox(height: 14),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: switch (_section) {
                        _WardrobeSection.outfits => _buildOutfitSection(),
                        _WardrobeSection.music => _buildMusicSection(),
                        _WardrobeSection.memories => _buildMemorySection(),
                      },
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
    final muted = AudioSettingsService.musicMuted.value;
    final selectedId = playlistIds.contains(_selectedPlaylistTrackId)
        ? _selectedPlaylistTrackId
        : null;
    // 清單剩一首就沒得排序：自動退出拖曳模式，避免卡在抖動狀態。
    if (_playlistEditMode && playlistTracks.length <= 1) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _finishMovingTracks(),
      );
    }
    return Column(
      key: const ValueKey('music'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MusicSummaryCard(
          currentTrack: current,
          playlistCount: playlistTracks.length,
          muted: muted,
          onTogglePause: _togglePause,
          onStopPreview: WardrobePreviewController.restore,
          onOpenDetail: _openTrackDetail,
        ),
        const SizedBox(height: 12),
        _PlaylistCard(
          tracks: playlistTracks,
          currentId: current.id,
          selectedId: selectedId ?? current.id,
          muted: muted,
          playMode: WardrobeStore.playMode.value,
          editMode: _playlistEditMode,
          jiggle: _jiggleCtrl,
          onCyclePlayMode: _cyclePlayMode,
          onSelect: _selectPlaylistTrack,
          onTogglePlay: _togglePlaylistTrackPlayback,
          onDetail: _openTrackDetail,
          onRemove: _removeTrack,
          onReorder: _reorderPlaylist,
          onStartMove: _startMovingTracks,
          onFinishMove: _finishMovingTracks,
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
            removable: WardrobeStore.playlist.value.length > 1,
            onPreview: () => _previewTrack(track),
            onDetail: () => _openTrackDetail(track),
            onAddToPlaylist: () => _addTrack(track),
            onRemoveFromPlaylist: () => _removeTrack(track),
            onBuy: () => _buyTrack(track),
          ),
      ],
    );
  }

  Widget _buildMemorySection() {
    final entries = StoryStore.unlocked.value;
    final unlockById = {for (final entry in entries) entry.id: entry};
    return Column(
      key: const ValueKey('memories'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WardrobeHeader(
          icon: Icons.auto_stories_rounded,
          title: '回憶本',
          subtitle: '兔咪替你收好的每一個小小時刻',
          trailing: '${entries.length}/${storyCatalog.length}',
          color: kMemoryAccent,
        ),
        const SizedBox(height: 12),
        if (entries.isEmpty) ...[
          const _MemoryEmpty(),
          const SizedBox(height: 18),
        ],
        const _MemoryShelfLabel(),
        const SizedBox(height: 10),
        for (var i = 0; i < storyCatalog.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == storyCatalog.length - 1 ? 0 : 12,
            ),
            child: _MemoryCard(
              event: storyCatalog[i],
              unlock: unlockById[storyCatalog[i].id],
              unread: StoryStore.unread.value.contains(storyCatalog[i].id),
              onTap: unlockById[storyCatalog[i].id] == null
                  ? null
                  : () => _openMemory(
                      entries.indexWhere((e) => e.id == storyCatalog[i].id),
                    ),
            ),
          ),
      ],
    );
  }
}

class _MemoryShelfLabel extends StatelessWidget {
  const _MemoryShelfLabel();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '回憶收藏',
          style: TextStyle(
            color: AppInk.strong.withValues(alpha: 0.9),
            fontSize: 13.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 1,
            color: kMemoryAccent.withValues(alpha: 0.14),
          ),
        ),
      ],
    );
  }
}

// 回憶本的一則：未解鎖也保留書脊位置，讓收藏進度與下一段故事都看得見。
class _MemoryCard extends StatelessWidget {
  final StoryEventSpec event;
  final StoryUnlock? unlock;
  final bool unread;
  final VoidCallback? onTap;

  const _MemoryCard({
    required this.event,
    required this.unlock,
    required this.unread,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppCardStyle.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppCardStyle.radius),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: unlock == null ? const Color(0xFFFFFCF8) : Colors.white,
            borderRadius: BorderRadius.circular(AppCardStyle.radius),
            border: Border.all(color: const Color(0x0A46342B)),
            boxShadow: AppShadows.card,
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 76,
                  height: 76,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        event.cover,
                        fit: BoxFit.cover,
                        color: unlock == null ? const Color(0xFFD8CDC2) : null,
                        colorBlendMode: unlock == null
                            ? BlendMode.saturation
                            : null,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: kMemoryAccent.withValues(alpha: 0.10),
                          child: Icon(
                            Icons.auto_stories_rounded,
                            color: kMemoryAccent.withValues(alpha: 0.6),
                            size: 28,
                          ),
                        ),
                      ),
                      if (unlock == null)
                        ColoredBox(
                          color: const Color(0xB8F7EEE4),
                          child: Center(
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.82),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.lock_outline_rounded,
                                size: 16,
                                color: kMemoryAccent.withValues(alpha: 0.72),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
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
                            event.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: kMemoryAccent.withValues(alpha: 0.92),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.7,
                            ),
                          ),
                        ),
                        if (unread)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE8C7),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: const Text(
                              '新回憶',
                              style: TextStyle(
                                color: Color(0xFF9B653A),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      unlock == null ? '尚未寫下的一頁' : event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppInk.strong,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      unlock == null
                          ? event.unlockHint
                          : _memoryDate(unlock!.date),
                      maxLines: unlock == null ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: unlock == null
                            ? AppInk.soft.withValues(alpha: 0.76)
                            : kMemoryAccent.withValues(alpha: 0.9),
                        fontSize: 11.5,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (unlock != null) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppInk.iconFaint,
                  size: 22,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MemoryEmpty extends StatelessWidget {
  const _MemoryEmpty();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppCardStyle.radius),
        border: AppCardStyle.hairline,
        boxShadow: AppShadows.flat,
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: kMemoryAccent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.auto_stories_rounded,
              color: kMemoryAccent.withValues(alpha: 0.7),
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '第一頁，正在等你',
            style: TextStyle(
              color: AppInk.strong,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '不用特地完成什麼大事。\n你每次開始、完成或再次回來，兔咪都會記得。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppInk.soft,
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

String _memoryDate(DateTime d) =>
    '${d.year} / ${d.month.toString().padLeft(2, '0')} / '
    '${d.day.toString().padLeft(2, '0')}';

class _SectionSwitch extends StatelessWidget {
  final _WardrobeSection value;
  final bool hasUnreadMemories;
  final ValueChanged<_WardrobeSection> onChanged;

  const _SectionSwitch({
    required this.value,
    required this.hasUnreadMemories,
    required this.onChanged,
  });

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
          _sectionButton(
            section: _WardrobeSection.memories,
            icon: Icons.auto_stories_rounded,
            label: '回憶',
            showDot: hasUnreadMemories,
          ),
        ],
      ),
    );
  }

  Widget _sectionButton({
    required _WardrobeSection section,
    required IconData icon,
    required String label,
    bool showDot = false,
  }) {
    final selected = value == section;
    final color = switch (section) {
      _WardrobeSection.outfits => kWardrobeAccent,
      _WardrobeSection.music => kMusicAccent,
      _WardrobeSection.memories => kMemoryAccent,
    };
    return Expanded(
      // 每顆按鈕各自包一層透明 Material，把點擊 ink（漣漪/highlight）關在自己
      // 的圓角範圍內。少了這層，三顆 InkWell 會共用上層遠處的 Material，
      // ink 會畫到隔壁去（點「回憶」連「音樂盒」也跟著亮）。
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
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
                if (showDot) ...[
                  const SizedBox(width: 5),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
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
  final bool muted;
  final Future<void> Function() onTogglePause;
  final Future<void> Function() onStopPreview;
  final ValueChanged<MusicTrackSpec> onOpenDetail;

  const _MusicSummaryCard({
    required this.currentTrack,
    required this.playlistCount,
    required this.muted,
    required this.onTogglePause,
    required this.onStopPreview,
    required this.onOpenDetail,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: WardrobePreviewController.previewingTrackId,
      builder: (_, previewingId, _) {
        final previewing = previewingId != null;
        final track = previewing ? trackById(previewingId) : currentTrack;
        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppCardStyle.radius),
          child: InkWell(
            onTap: () => onOpenDetail(track),
            borderRadius: BorderRadius.circular(AppCardStyle.radius),
            child: Container(
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
                    _RoundIconButton(
                      icon: muted
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      color: kMusicAccent,
                      tooltip: muted ? '繼續播放' : '暫停',
                      onTap: () => unawaited(onTogglePause()),
                    ),
                  const SizedBox(width: 6),
                  _SoftPill(text: '$playlistCount 首', color: kMusicAccent),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final List<MusicTrackSpec> tracks;
  final String currentId;
  final String selectedId;
  final bool muted;
  final PlayMode playMode;
  final bool editMode;
  final Animation<double> jiggle;
  final VoidCallback onCyclePlayMode;
  final ValueChanged<MusicTrackSpec> onSelect;
  final ValueChanged<MusicTrackSpec> onTogglePlay;
  final ValueChanged<MusicTrackSpec> onDetail;
  final ValueChanged<MusicTrackSpec> onRemove;
  final void Function(int oldIndex, int newIndex) onReorder;
  final VoidCallback onStartMove;
  final VoidCallback onFinishMove;

  const _PlaylistCard({
    required this.tracks,
    required this.currentId,
    required this.selectedId,
    required this.muted,
    required this.playMode,
    required this.editMode,
    required this.jiggle,
    required this.onCyclePlayMode,
    required this.onSelect,
    required this.onTogglePlay,
    required this.onDetail,
    required this.onRemove,
    required this.onReorder,
    required this.onStartMove,
    required this.onFinishMove,
  });

  @override
  Widget build(BuildContext context) {
    final canModify = tracks.length > 1;
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
            // 長按拖曳剛啟動時切進「拖曳模式」（抖動）；本幀後再翻，避免啟動當下重建。
            onReorderStart: (_) {
              if (!editMode) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => onStartMove(),
                );
              }
            },
            proxyDecorator: (child, index, animation) =>
                Material(color: Colors.transparent, child: child),
            itemBuilder: (_, i) {
              final track = tracks[i];
              final row = ReorderJiggle(
                animation: jiggle,
                enabled: editMode && canModify,
                seed: track.id.hashCode,
                child: Slidable(
                  key: ValueKey('sl_${track.id}'),
                  // 拖曳模式中 / 只剩一首時不給左滑刪除。
                  enabled: !editMode && canModify,
                  endActionPane: ActionPane(
                    motion: const BehindMotion(),
                    extentRatio: 0.26,
                    children: [
                      SlidableAction(
                        onPressed: (_) => onRemove(track),
                        backgroundColor: Colors.red.shade400,
                        foregroundColor: Colors.white,
                        icon: Icons.delete_outline_rounded,
                        label: '移除',
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ],
                  ),
                  child: _PlaylistRow(
                    key: ValueKey('playlist-row-${track.id}'),
                    track: track,
                    isCurrent: track.id == currentId,
                    isSelected: track.id == selectedId,
                    muted: muted,
                    editMode: editMode,
                    removable: canModify,
                    onTap: editMode ? null : () => onSelect(track),
                    onPlayTap: () => onTogglePlay(track),
                    onMove: onStartMove,
                    onRemove: () => onRemove(track),
                    onDetail: () => onDetail(track),
                  ),
                ),
              );
              // 只有一首時不掛拖曳辨識器（不能排序），但仍要 keyed 給 ReorderableListView。
              return canModify
                  ? ReorderHoldDragListener(
                      key: ValueKey('pl_${track.id}'),
                      index: i,
                      immediate: editMode,
                      child: row,
                    )
                  : KeyedSubtree(key: ValueKey('pl_${track.id}'), child: row);
            },
          ),
          if (editMode) ...[
            const SizedBox(height: 8),
            _MoveDoneButton(onTap: onFinishMove),
          ],
        ],
      ),
    );
  }
}

// 播放清單的一列：點＝輕量臨時標記（編輯模式中停用）；右側播放鈕才切歌/暫停。
// 移除走左滑或「…」。排序模式只用整列抖動表意，不插入圖示、不改列的幾何。
enum _PlaylistRowAction { move, remove, detail }

class _PlaylistRow extends StatelessWidget {
  final MusicTrackSpec track;
  final bool isCurrent;
  final bool isSelected;
  final bool muted;
  final bool editMode;
  final bool removable;
  final VoidCallback? onTap;
  final VoidCallback onPlayTap;
  final VoidCallback onMove;
  final VoidCallback onRemove;
  final VoidCallback onDetail;

  const _PlaylistRow({
    super.key,
    required this.track,
    required this.isCurrent,
    required this.isSelected,
    required this.muted,
    required this.editMode,
    required this.removable,
    required this.onTap,
    required this.onPlayTap,
    required this.onMove,
    required this.onRemove,
    required this.onDetail,
  });

  @override
  Widget build(BuildContext context) {
    final playing = isCurrent && !muted;
    final selectedOnly = isSelected && !isCurrent;
    final rowColor = isCurrent
        ? const Color(0xFFEFF3FC)
        : selectedOnly
        // 臨時標記只留近乎白色的淡染；它方便截圖辨認，不應搶過播放狀態。
        ? Color.alphaBlend(kMusicAccent.withValues(alpha: 0.025), Colors.white)
        : Colors.white;
    final borderColor = isCurrent
        ? kMusicAccent.withValues(alpha: 0.20)
        : Colors.transparent;
    final titleColor = selectedOnly
        ? Color.lerp(AppInk.strong, kMusicAccent, 0.18)!
        : AppInk.strong;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      // 不透明底色：左滑時才不會透出底下的移除動作。
      decoration: BoxDecoration(
        color: rowColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              children: [
                _TrackCover(track: track, size: 34),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 13.5,
                      fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // 排序時保留原本兩顆操作鈕的版位，讓封面、標題與整列寬度
                // 完全不跳動；只把操作藏起來，避免拖曳途中誤播或開選單。
                IgnorePointer(
                  ignoring: editMode,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: editMode ? 0 : 1,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _PlaylistPlayButton(
                          playing: playing,
                          muted: muted,
                          onTap: onPlayTap,
                        ),
                        _PlaylistMoreButton(
                          removable: removable,
                          onMove: onMove,
                          onRemove: onRemove,
                          onDetail: onDetail,
                        ),
                      ],
                    ),
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

class _PlaylistMoreButton extends StatelessWidget {
  final bool removable;
  final VoidCallback onMove;
  final VoidCallback onRemove;
  final VoidCallback onDetail;

  const _PlaylistMoreButton({
    required this.removable,
    required this.onMove,
    required this.onRemove,
    required this.onDetail,
  });

  void _handle(_PlaylistRowAction action) {
    switch (action) {
      case _PlaylistRowAction.move:
        onMove();
      case _PlaylistRowAction.remove:
        onRemove();
      case _PlaylistRowAction.detail:
        onDetail();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_PlaylistRowAction>(
      tooltip: '更多',
      padding: EdgeInsets.zero,
      icon: const Icon(
        Icons.more_horiz_rounded,
        size: 22,
        color: AppInk.iconFaint,
      ),
      onSelected: _handle,
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _PlaylistRowAction.move,
          enabled: removable,
          child: _PlaylistMenuItem(
            icon: Icons.open_with_rounded,
            label: '移動',
            enabled: removable,
          ),
        ),
        PopupMenuItem(
          value: _PlaylistRowAction.remove,
          enabled: removable,
          child: _PlaylistMenuItem(
            icon: Icons.delete_outline_rounded,
            label: '移除',
            enabled: removable,
            danger: true,
          ),
        ),
        const PopupMenuItem(
          value: _PlaylistRowAction.detail,
          child: _PlaylistMenuItem(
            icon: Icons.info_outline_rounded,
            label: '詳細資訊',
          ),
        ),
      ],
    );
  }
}

class _PlaylistMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final bool danger;

  const _PlaylistMenuItem({
    required this.icon,
    required this.label,
    this.enabled = true,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? Colors.red.shade400 : kMusicAccent;
    final contentColor = enabled ? color : AppInk.iconFaint;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 19, color: contentColor),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: contentColor,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _PlaylistPlayButton extends StatelessWidget {
  final bool playing;
  final bool muted;
  final VoidCallback onTap;

  const _PlaylistPlayButton({
    required this.playing,
    required this.muted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = playing ? Icons.pause_rounded : Icons.play_arrow_rounded;
    final tooltip = playing ? '暫停' : (muted ? '播放並解除靜音' : '播放');
    return Tooltip(
      message: tooltip,
      child: Material(
        color: kMusicAccent.withValues(alpha: playing ? 0.16 : 0.10),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 22, color: kMusicAccent),
          ),
        ),
      ),
    );
  }
}

// 拖曳排序模式的「完成排序」綠色 bar（沿用習慣頁的綠＝完成語彙）。
class _MoveDoneButton extends StatelessWidget {
  final VoidCallback onTap;

  const _MoveDoneButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green.shade500, Colors.green.shade600],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_rounded, size: 18, color: Colors.white),
              SizedBox(width: 8),
              Text(
                '完成排序',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
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
  final bool removable;
  final VoidCallback onPreview;
  final VoidCallback onDetail;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onRemoveFromPlaylist;
  final VoidCallback onBuy;

  const _TrackGridCard({
    required this.track,
    required this.owned,
    required this.inPlaylist,
    required this.isCurrent,
    required this.removable,
    required this.onPreview,
    required this.onDetail,
    required this.onAddToPlaylist,
    required this.onRemoveFromPlaylist,
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
    if (!owned) {
      return _PrimaryMiniButton(
        label: unlockLabel(track.unlockType, track.coinPrice),
        icon: Icons.lock_open_rounded,
        color: kMusicAccent,
        onTap: onBuy,
      );
    }
    if (inPlaylist) {
      // 已在清單 → 可移除（清單只剩一首時停用，防沒歌）。
      return _PrimaryMiniButton(
        label: removable ? '移除' : '已加入',
        icon: removable ? Icons.playlist_remove_rounded : Icons.check_rounded,
        color: kMusicAccent,
        enabled: removable,
        onTap: onRemoveFromPlaylist,
      );
    }
    return _PrimaryMiniButton(
      label: '加入',
      icon: Icons.playlist_add_rounded,
      color: kMusicAccent,
      onTap: onAddToPlaylist,
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

  // 這首正載入在播放器時顯示真實時長；否則退回 catalog 的 durationLabel。
  String _durationText() {
    final d = BgmService.instance.duration;
    if (BgmService.instance.loadedAsset == track.assetPath && d != null) {
      final m = d.inMinutes;
      final s = d.inSeconds % 60;
      return '$m:${s.toString().padLeft(2, '0')}';
    }
    return track.durationLabel;
  }

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
              const SizedBox(height: 12),
              // 全圖 16:9 hero（不裁切）＋ 右上關閉鈕。標題/作者另用 app 文字（可翻譯），
              // 不依賴燒進圖裡的字。
              Stack(
                children: [
                  _DetailHeroCover(track: track),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.30),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.pop(context),
                        child: const Padding(
                          padding: EdgeInsets.all(5),
                          child: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _DetailChip(label: moodLabel(track.mood), color: track.color),
                  for (final tag in track.tags)
                    _DetailChip(label: tag, color: kMusicAccent),
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
                value: _durationText(),
              ),
              const SizedBox(height: 10),
              _AttributionNote(track: track),
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
        dialogCancelAction(
          dialogCtx,
          onPressed: () => Navigator.pop(dialogCtx, false),
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

// 詳細資訊頂部的 16:9 全圖 hero（封面原圖就是 16:9，不裁切）。
class _DetailHeroCover extends StatelessWidget {
  final MusicTrackSpec track;

  const _DetailHeroCover({required this.track});

  @override
  Widget build(BuildContext context) {
    final cover = track.coverAsset;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: cover != null
            ? Image.asset(
                cover,
                fit: BoxFit.cover,
                cacheWidth: 1280,
                errorBuilder: (_, _, _) => _fallback(),
              )
            : _fallback(),
      ),
    );
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
        child: Icon(Icons.music_note_rounded, color: Colors.white, size: 48),
      ),
    );
  }
}

// 詳細資訊的心情 / 標籤小 chip。
class _DetailChip extends StatelessWidget {
  final String label;
  final Color color;

  const _DetailChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// 創作者授權／感謝：縮小的次要說明，放在動作鈕上方。
class _AttributionNote extends StatelessWidget {
  final MusicTrackSpec track;

  const _AttributionNote({required this.track});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF7F2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${track.licenseNote}\n${track.attributionText}',
        style: const TextStyle(
          color: AppInk.faint,
          fontSize: 11,
          height: 1.35,
          fontWeight: FontWeight.w600,
        ),
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
