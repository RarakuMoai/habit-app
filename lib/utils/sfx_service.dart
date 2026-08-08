import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'app_audio_session.dart';
import 'audio_settings_service.dart';

enum SfxCue {
  tap('assets/sounds/sfx_tap.wav', 0.88),
  success('assets/sounds/sfx_success.wav', 0.95),
  complete('assets/sounds/sfx_complete.wav', 1.0),
  cancel('assets/sounds/sfx_cancel.wav', 0.9),
  // 衣櫃購買／回憶揭曉／骰子開盤：仙塵般的星光碎音（mixkit fairy arcade
  // sparkle，裁掉 0.86s 之後的靜音尾）。舊檔實際輸出只有 -39.7 dBFS，比其他
  // 音效整整輕 10dB，解鎖那一聲幾乎聽不到；換檔時一併把係數拉進 -28 dBFS 的
  // 常規區間。
  unlock('assets/sounds/sfx_unlock.wav', 0.44),
  // 鎖掙脫時的金屬碰撞。**不是單發音效**——六次撞擊分別對齊
  // `_shakeAngleAt` 的六次最大偏轉（55/166/277/388/498/609ms），
  // 撞擊聲要落在看得到的轉向瞬間才會讀成「鎖在掙脫」。要改疏密就重跑
  // `docs/pending_assets.md` 記錄的生成方式，不要在播放端做重複排程。
  lockRattle('assets/sounds/sfx_lock_rattle.wav', 0.62),
  // 每日足跡幣：Mixkit 揭曉樂句 → 紙面蓋章 → 柔和吸入 → 逐枚入袋。
  // intro 裁掉原檔前 50ms 空白；stamp 是使用者挑選的原檔裁成單一撞擊；
  // tick 由原始 MP3 四聲道輪替連奏。
  loginStreakIntro('assets/sounds/sfx_login_streak_intro.wav', 0.64),
  footprintStamp('assets/sounds/sfx_footprint_stamp_impact.wav', 0.82),
  footprintCoinAbsorb('assets/sounds/sfx_footprint_coin_absorb.wav', 0.80),
  footprintCoinTick('assets/sounds/sfx_footprint_coin_tick.mp3', 0.52),
  // 喝水頁：短泡泡回應每次加水；魔法藥水音只在跨過今日目標時慶祝。
  waterAdd('assets/sounds/sfx_water_add.wav', 0.78),
  waterGoal('assets/sounds/sfx_water_goal.wav', 0.62),
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
  // 菜園小蛇 V2：暖木質起音＋柔和掌機三角波。高頻動作刻意短且小聲，
  // 升級／復活才保留旋律尾韻；特殊能力各有獨立語意，不再共用泛用音效。
  snakeStart('assets/sounds/sfx_snake_start.wav', 0.62),
  snakeCollect('assets/sounds/sfx_snake_collect.wav', 0.42),
  snakeBonus('assets/sounds/sfx_snake_bonus.wav', 0.62),
  snakePower('assets/sounds/sfx_snake_power.wav', 0.58),
  snakeSeed('assets/sounds/sfx_snake_seed.wav', 0.35),
  snakeHit('assets/sounds/sfx_snake_hit.wav', 0.55),
  snakeHunt('assets/sounds/sfx_snake_hunt.wav', 0.64),
  snakeWarning('assets/sounds/sfx_snake_warning.wav', 0.42),
  snakeGameOver('assets/sounds/sfx_snake_game_over.wav', 0.65),
  snakeRevive('assets/sounds/sfx_snake_revive.wav', 0.62),
  snakeMagnetSpawn('assets/sounds/sfx_snake_magnet_spawn.wav', 0.42),
  snakeMagnetVacuum('assets/sounds/sfx_snake_magnet_vacuum.wav', 0.62),
  snakeLaserCharge('assets/sounds/sfx_snake_laser_charge.wav', 0.50),
  snakeLaserShot('assets/sounds/sfx_snake_laser_shot.wav', 0.42),
  snakeMoleRise('assets/sounds/sfx_snake_mole_rise.wav', 0.48),
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

  // 一般 cue 只需要一個 player；逐枚入袋聲用四聲道輪替，快速連奏時不會
  // stop/seek 掉上一枚仍在衰減的尾音。
  final Map<SfxCue, List<AudioPlayer>> _players = {};
  final Map<SfxCue, int> _cursors = {};
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
    final loaded = <SfxCue, List<AudioPlayer>>{};
    try {
      for (final cue in SfxCue.values) {
        final voiceCount = cue == SfxCue.footprintCoinTick ? 4 : 1;
        final voices = <AudioPlayer>[];
        loaded[cue] = voices;
        for (var i = 0; i < voiceCount; i++) {
          final player = AudioPlayer();
          voices.add(player);
          await player.setAudioSource(AudioSource.asset(cue.assetPath));
          await player.setVolume(cue.volume);
        }
      }
    } catch (_) {
      for (final voices in loaded.values) {
        for (final player in voices) {
          await player.dispose();
        }
      }
      rethrow;
    }
    _players.addAll(loaded);
    for (final cue in loaded.keys) {
      _cursors[cue] = 0;
    }
    _initialized = true;
  }

  /// [volumeScale] 疊在 cue 預設音量上（0–1），碰撞聲隨力道縮放用。
  Future<void> play(SfxCue cue, {double volumeScale = 1, double speed = 1}) =>
      _play(cue, volumeScale: volumeScale, speed: speed, pitch: 1, loop: false);

  /// 可重疊的短音效。足跡幣逐枚入袋時用輪替聲道保留前一枚尾音；
  /// [pitch] 做極小音高變化，避免九枚聽起來像機械複製。
  Future<void> playPolyphonic(
    SfxCue cue, {
    double volumeScale = 1,
    double pitch = 1,
  }) => _play(
    cue,
    volumeScale: volumeScale,
    speed: 1,
    pitch: pitch,
    loop: false,
    polyphonic: true,
  );

  /// 持續動作音（目前用於摸毛）：呼叫 [stop] 前會無縫循環。
  Future<void> playLoop(SfxCue cue, {double volumeScale = 1}) =>
      _play(cue, volumeScale: volumeScale, speed: 1, pitch: 1, loop: true);

  Future<void> _play(
    SfxCue cue, {
    required double volumeScale,
    required double speed,
    required double pitch,
    required bool loop,
    bool polyphonic = false,
  }) async {
    if (AudioSettingsService.sfxMuted.value) return;
    try {
      if (!_initialized) await init();
      final voices = _players[cue];
      if (voices == null || voices.isEmpty) return;
      final cursor = polyphonic ? (_cursors[cue] ?? 0) : 0;
      final player = voices[cursor % voices.length];
      if (polyphonic) _cursors[cue] = (cursor + 1) % voices.length;
      // 逐枚金幣的落點間隔很短；session 在 init 與前一段吸入聲都已啟用，
      // 不 await 平台 setActive，避免九次呼叫把節奏拖散。
      if (polyphonic) {
        unawaited(AppAudioSession.activate());
      } else {
        await AppAudioSession.activate();
      }
      await player.stop();
      await player.setLoopMode(loop ? LoopMode.one : LoopMode.off);
      await player.seek(Duration.zero);
      await player.setSpeed(speed.clamp(0.5, 2.0).toDouble());
      await player.setPitch(pitch.clamp(0.5, 2.0).toDouble());
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
      for (final player in _players[cue] ?? const <AudioPlayer>[]) {
        await player.stop();
      }
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
    for (final voices in _players.values) {
      for (final player in voices) {
        await player.dispose();
      }
    }
    _players.clear();
    _cursors.clear();
    _initialized = false;
    _initializing = null;
  }
}
