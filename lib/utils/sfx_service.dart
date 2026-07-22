import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'app_audio_session.dart';
import 'audio_settings_service.dart';

enum SfxCue {
  tap('assets/sounds/sfx_tap.wav', 0.88),
  success('assets/sounds/sfx_success.wav', 0.95),
  complete('assets/sounds/sfx_complete.wav', 1.0),
  cancel('assets/sounds/sfx_cancel.wav', 0.9),
  // 衣櫃購買／回憶揭曉：溫暖木質起音＋短促星光尾音。
  unlock('assets/sounds/sfx_unlock.wav', 0.85),
  // 每日足跡幣：兔咪手前灑開 → 柔軟吸入 → POKA03 短促命中。
  footprintCoinScatter('assets/sounds/sfx_footprint_coin_scatter.wav', 0.62),
  footprintCoinAbsorb('assets/sounds/sfx_footprint_coin_absorb.wav', 0.72),
  footprintCoinReward('assets/sounds/sfx_footprint_coin_reward.wav', 0.50),
  // 兔咪語音（2026-07 新錄音組，取代舊 tumi_mi_*）。
  // 各檔原始響度不齊（RMS -20.8 ~ -28.3 dBFS），用音量係數拉齊到
  // 「輕聲陪伴」水準；歡呼是大事件慶祝，刻意比日常亮一點。
  tumiCheer('assets/sounds/tumi_voice_cheer.wav', 0.95),
  tumiConfirm('assets/sounds/tumi_voice_confirm.wav', 0.45),
  tumiHappy('assets/sounds/tumi_voice_happy.wav', 0.50),
  tumiQuestion('assets/sounds/tumi_voice_question.wav', 0.58),
  tumiSad('assets/sounds/tumi_voice_sad.wav', 0.85),
  // 兔咪直接互動的動作層：每次動作都回饋；角色語音仍由 MascotPersona CD 控制。
  // falling3 配合 1.1 秒集氣時序裁切淡出；jump12 裁掉尾端靜音。
  tumiCharge('assets/sounds/sfx_tumi_charge.wav', 0.62),
  tumiJump('assets/sounds/sfx_tumi_jump.wav', 0.72),
  // 只取 swish 最前方乾淨毛茸段，首尾交叉淡化成 0.64 秒無縫循環。
  tumiPet('assets/sounds/sfx_tumi_pet.wav', 0.78),
  // 菜園小蛇專屬：短音色各自對應遊戲語意，不借用棋鐘／骰子／一般 UI 聲。
  snakeStart('assets/sounds/sfx_snake_start.wav', 0.70),
  snakeCollect('assets/sounds/sfx_snake_collect.wav', 0.58),
  snakeBonus('assets/sounds/sfx_snake_bonus.wav', 0.72),
  snakePower('assets/sounds/sfx_snake_power.wav', 0.68),
  snakeSeed('assets/sounds/sfx_snake_seed.wav', 0.46),
  snakeHit('assets/sounds/sfx_snake_hit.wav', 0.68),
  snakeHunt('assets/sounds/sfx_snake_hunt.wav', 0.72),
  snakeWarning('assets/sounds/sfx_snake_warning.wav', 0.54),
  snakeGameOver('assets/sounds/sfx_snake_game_over.wav', 0.76),
  snakeRevive('assets/sounds/sfx_snake_revive.wav', 0.72),
  // 桌遊計時器專屬（ElevenLabs 生成、剪裁後 peak 對齊上面同類音效）
  gamePass('assets/sounds/sfx_game_pass.wav', 0.9), // 棋鐘喀噠：換人
  gameWarn('assets/sounds/sfx_game_warn.wav', 0.85), // 木質 tick：倒數警示
  gameFlag('assets/sounds/sfx_game_flag.wav', 1.0), // 沉鑼：超時/旗倒
  gameDice('assets/sounds/sfx_game_dice.wav', 0.9); // 骰子喀啦：擲骰/碰撞

  const SfxCue(this.assetPath, this.volume);
  final String assetPath;
  final double volume;
}

class SfxService {
  SfxService._();
  static final SfxService instance = SfxService._();

  final Map<SfxCue, AudioPlayer> _players = {};
  bool _initialized = false;
  Future<void>? _initializing;

  Future<void> init() async {
    if (_initialized) return;
    final pending = _initializing;
    if (pending != null) {
      await pending;
      return;
    }
    final operation = _initialize();
    _initializing = operation;
    try {
      await operation;
    } finally {
      if (identical(_initializing, operation)) _initializing = null;
    }
  }

  Future<void> _initialize() async {
    await AudioSettingsService.instance.init();
    await AppAudioSession.ensureConfigured();
    final loaded = <SfxCue, AudioPlayer>{};
    try {
      for (final cue in SfxCue.values) {
        final player = AudioPlayer();
        loaded[cue] = player;
        await player.setAudioSource(AudioSource.asset(cue.assetPath));
        await player.setVolume(cue.volume);
      }
    } catch (_) {
      for (final player in loaded.values) {
        await player.dispose();
      }
      rethrow;
    }
    _players.addAll(loaded);
    _initialized = true;
  }

  /// [volumeScale] 疊在 cue 預設音量上（0–1），碰撞聲隨力道縮放用。
  Future<void> play(SfxCue cue, {double volumeScale = 1}) =>
      _play(cue, volumeScale: volumeScale, loop: false);

  /// 持續動作音（目前用於摸毛）：呼叫 [stop] 前會無縫循環。
  Future<void> playLoop(SfxCue cue, {double volumeScale = 1}) =>
      _play(cue, volumeScale: volumeScale, loop: true);

  Future<void> _play(
    SfxCue cue, {
    required double volumeScale,
    required bool loop,
  }) async {
    if (AudioSettingsService.sfxMuted.value) return;
    try {
      if (!_initialized) await init();
      final player = _players[cue];
      if (player == null) return;
      await AppAudioSession.activate();
      await player.stop();
      await player.setLoopMode(loop ? LoopMode.one : LoopMode.off);
      await player.seek(Duration.zero);
      await player.setVolume(cue.volume * volumeScale.clamp(0.0, 1.0));
      await player.play();
    } catch (e) {
      debugPrint('SFX play failed: $e');
    }
  }

  /// 停掉仍在播放的單一動作音。若該音效正處於首次載入，會等載入完成後
  /// 立刻停止，避免「提早放開蓄力」卻讓 1.08 秒集氣音繼續播完。
  Future<void> stop(SfxCue cue) async {
    try {
      if (!_initialized) {
        final pending = _initializing;
        if (pending == null) return;
        await pending;
      }
      await _players[cue]?.stop();
    } catch (e) {
      debugPrint('SFX stop failed: $e');
    }
  }

  Future<void> dispose() async {
    final pending = _initializing;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // 初始化失敗時沒有可釋放的完整 player 集合，照常清理已知項目。
      }
    }
    for (final player in _players.values) {
      await player.dispose();
    }
    _players.clear();
    _initialized = false;
    _initializing = null;
  }
}
