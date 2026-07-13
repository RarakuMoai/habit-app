// 兔咪場景共用元件：把首頁那組「兔咪 + 對話框 + 互動動畫」抽成可共用 widget，
// 讓其他頁面（番茄鐘、喝水、體重、家庭）能套用同樣的呈現。
//
// 主要對外 API：
//   - [MascotScene]：兔咪 + 對話框組合，直接餵給 [MascotPageShell] 的 scene。
//   - [MascotStage]：純兔咪 widget（含 idle 呼吸、tap reaction 動畫）。
//   - [MascotSpeechBubble]：對話框 widget。
//
// 內部維持原本動作參數表（_motionForAsset）與星星 reaction painter
// （_MascotSparklePainter）。頭頂情緒泡泡的規格與繪製在
// widgets/mascot_bubbles.dart（宣告式註冊表，新增泡泡改那邊）。

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/mascot.dart';
import '../utils/wardrobe_catalog.dart';
import '../utils/wardrobe_store.dart';
import 'mascot_bubbles.dart';

class MascotIdleScope extends InheritedWidget {
  final bool paused;

  const MascotIdleScope({
    super.key,
    required this.paused,
    required super.child,
  });

  static bool pausedOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<MascotIdleScope>()
            ?.paused ??
        false;
  }

  @override
  bool updateShouldNotify(covariant MascotIdleScope oldWidget) =>
      oldWidget.paused != paused;
}

/// 從 [MascotPersona.current] 自動讀情緒 + 台詞 的場景；
/// 切頁不會重建兔咪狀態，只有互動會推新狀態。
class PersonaScene extends StatelessWidget {
  final Color accent;
  final int reactionTick;
  final VoidCallback? onTap;
  final VoidCallback? onHeadPet;
  final VoidCallback? onEnergize;

  /// 閒置凍結：true 時兔咪暫停呼吸與眨眼，讓畫面完全靜止省電；
  /// 一有互動由上層轉回 false 即恢復。
  final bool paused;

  const PersonaScene({
    super.key,
    required this.accent,
    this.reactionTick = 0,
    this.onTap,
    this.onHeadPet,
    this.onEnergize,
    this.paused = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectivePaused = paused || MascotIdleScope.pausedOf(context);

    void handleHeadPet() {
      final callback = onHeadPet;
      if (callback != null) {
        callback();
      } else {
        MascotPersona.interact(MascotContext.headPet);
      }
    }

    void handleEnergize() {
      final callback = onEnergize;
      if (callback != null) {
        callback();
      } else {
        MascotPersona.interact(MascotContext.energize);
      }
    }

    return ValueListenableBuilder<MascotState>(
      valueListenable: MascotPersona.current,
      builder: (_, state, _) => ValueListenableBuilder<String>(
        valueListenable: WardrobeStore.selectedOutfit,
        builder: (_, outfitId, _) => MascotScene(
          // 依目前造型把 core 兔咪換成對應皮膚版本；原始造型為 identity。
          asset: skinnedMascotAsset(
            state.assetPath,
            outfitById(outfitId).skinKey,
          ),
          accent: accent,
          speech: state.speech,
          bubble: state.bubble,
          bubbleTick: state.bubbleTick,
          reactionTick: reactionTick,
          onTap: onTap,
          onHeadPet: handleHeadPet,
          onEnergize: handleEnergize,
          paused: effectivePaused,
        ),
      ),
    );
  }
}

class MascotScene extends StatelessWidget {
  /// 兔咪 PNG 路徑（一般用 [MascotEmotion.assetPath]）。
  final String asset;

  /// 主色，影響對話框邊框與點擊時星星顏色。
  final Color accent;

  /// 要顯示的台詞；null / 空字串 = 這次不冒文字泡泡（只留頭頂符號）。
  final String? speech;

  /// 頭頂情緒泡泡；null = 這次不冒。換成新值（或非 null）時冒一下後淡出。
  final EmotionBubble? bubble;

  /// 泡泡事件序號；同一種泡泡連續觸發時也用它重播動畫。
  final int bubbleTick;

  /// 每次 +1 觸發一次「驚喜」反應動畫（往上跳 + 星星）。
  /// 不需要的話傳 0 即可。
  final int reactionTick;

  /// 點擊兔咪的 callback；不需互動可省略。
  final VoidCallback? onTap;

  /// 摸到兔咪頭時的 callback；不需特殊副作用可省略。
  final VoidCallback? onHeadPet;

  /// 充電互動（長按蓄力放開）爆發時的 callback；不需互動可省略。
  final VoidCallback? onEnergize;

  /// 閒置凍結：暫停兔咪呼吸與眨眼（見 [PersonaScene.paused]）。
  final bool paused;

  const MascotScene({
    super.key,
    required this.asset,
    required this.accent,
    required this.speech,
    this.bubble,
    this.bubbleTick = 0,
    this.reactionTick = 0,
    this.onTap,
    this.onHeadPet,
    this.onEnergize,
    this.paused = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (speech != null && speech!.isNotEmpty)
          Positioned(
            top: 50,
            left: 28,
            right: 28,
            child: MascotSpeechBubble(text: speech!, accent: accent),
          ),
        Align(
          alignment: const Alignment(0, 0.92),
          child: MascotStage(
            asset: asset,
            accent: accent,
            bubble: bubble,
            bubbleTick: bubbleTick,
            reactionTick: reactionTick,
            onTap: onTap ?? () {},
            onHeadPet: onHeadPet,
            onEnergize: onEnergize,
            paused: paused,
          ),
        ),
      ],
    );
  }
}

class MascotSpeechBubble extends StatefulWidget {
  final String text;
  final Color accent;

  /// 顯示多久後開始淡出（換新台詞會重新計時）
  final Duration visibleDuration;

  /// 淡出動畫長度
  final Duration fadeDuration;

  const MascotSpeechBubble({
    super.key,
    required this.text,
    required this.accent,
    this.visibleDuration = const Duration(seconds: 7),
    this.fadeDuration = const Duration(milliseconds: 600),
  });

  @override
  State<MascotSpeechBubble> createState() => _MascotSpeechBubbleState();
}

class _MascotSpeechBubbleState extends State<MascotSpeechBubble> {
  bool _visible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void didUpdateWidget(covariant MascotSpeechBubble old) {
    super.didUpdateWidget(old);
    // 換新台詞 → 立刻可見 + 重新計時
    if (old.text != widget.text) {
      setState(() => _visible = true);
      _scheduleHide();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(widget.visibleDuration, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !_visible,
      child: AnimatedOpacity(
        opacity: _visible ? 1.0 : 0.0,
        duration: widget.fadeDuration,
        curve: Curves.easeOut,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: CustomPaint(
              painter: _SpeechBubblePainter(
                color: Colors.white,
                borderColor: widget.accent.withValues(alpha: 0.25),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    widget.text,
                    key: ValueKey(widget.text),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppInk.strong,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MascotStage extends StatefulWidget {
  final String asset;
  final Color accent;

  /// 頭頂情緒泡泡；變化（或從 null 變成非 null）時冒一下後淡出。
  final EmotionBubble? bubble;
  final int bubbleTick;
  final int reactionTick;
  final VoidCallback onTap;
  final VoidCallback? onHeadPet;

  /// 充電互動：長按蓄力、放開（或蓄滿）爆發的那一刻呼叫。
  final VoidCallback? onEnergize;

  /// 閒置凍結：暫停呼吸與眨眼（見 [PersonaScene.paused]）。
  final bool paused;

  const MascotStage({
    super.key,
    required this.asset,
    required this.accent,
    this.bubble,
    this.bubbleTick = 0,
    required this.reactionTick,
    required this.onTap,
    this.onHeadPet,
    this.onEnergize,
    this.paused = false,
  });

  @override
  State<MascotStage> createState() => _MascotStageState();
}

class _MascotStageState extends State<MascotStage>
    with TickerProviderStateMixin {
  late final AnimationController _reactionCtrl;
  late final AnimationController _petCtrl;
  late final AnimationController _breathCtrl;
  late final Animation<double> _breath;

  // 頭頂情緒泡泡：一次性演出，時長與動態依泡泡種類而異。
  // 觸發見 didUpdateWidget / _playBubble；規格與繪製見 mascot_bubbles.dart。
  late final AnimationController _bubbleCtrl;
  EmotionBubble? _bubbleShown; // 動畫期間正在畫的泡泡（即使 widget 換新值也畫到淡出）

  // 眨眼：閉眼差分換圖。只有 MascotEmotion.blinkAssetForPath 有對應圖的
  // 情緒會眨；其他情緒 timer 照走但跳過，等換回有差分的圖自然恢復。
  final math.Random _rng = math.Random();
  Timer? _blinkTimer;
  bool _eyesClosed = false;

  // ── 摸頭（頭上搓動）──
  // 完全由手指驅動、沒有自己的節奏：身體朝手指方向輕靠（彈簧平滑）、
  // 被摸時像承受手掌重量微微下沉；每搓一段距離從指尖冒一顆小愛心＋
  // 輕觸覺；摸夠久瞇眼享受。放開手才通知 persona（換 smile／愛心泡泡
  // ／語音），變成「回味」的時刻。
  bool _isPetting = false;
  double _petLean = 0; // 目前傾靠量 -1..1（朝手指，彈簧收斂）
  double _petLeanTarget = 0;
  double _petPress = 0; // 承重下沉量 0..1（進入漸入、放開漸出）
  double _lastPetX = 0; // 上次手指 x，累積搓動距離用
  double _strokeAccum = 0; // 距離累積，每滿一段冒一顆愛心
  double _petTotalStroke = 0; // 本次總搓動量（放開時判斷算不算一次摸頭）
  double _petClock = 0; // 摸頭驅動器的幀時鐘（愛心壽命/摸多久都用它，測試可確定）
  double _petStartClock = 0;
  bool _petEyesClosed = false; // 摸夠久 → 瞇眼享受（有對應差分才真的換臉）
  Timer? _petBlissTimer;
  final List<_PetHeart> _hearts = [];

  // 充電互動：長按蓄力（_chargeCtrl 0→1，蓄滿自動爆發）→ 放開時
  // 依蓄力量播爆發演出（_burstCtrl，跳高與星星量 ∝ _burstPower）。
  late final AnimationController _chargeCtrl;
  late final AnimationController _burstCtrl;
  bool _isCharging = false;
  double _burstPower = 0;
  Offset _chargeOrigin = Offset.zero;
  int _chargeTickStep = 0; // 蓄力觸覺已震到第幾檔（跨檔位才震，避免連發）

  @override
  void initState() {
    super.initState();
    // 點擊反應：迷你小跳（蹲→跳→落地回彈），細節在 build 內程序式計算，
    // 與充電爆發共用同一套「有重量的身體」語彙。
    _reactionCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 640),
    );

    // 摸頭逐幀驅動器：只負責讓畫面每幀重建＋收斂彈簧與愛心壽命，
    // 沒有自己的節奏（節奏完全來自手指）。
    _petCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_petFrame);

    // 蓄力：長按接受（~0.5s）後再蓄 1.1 秒滿；蓄滿兔咪「憋不住」自動爆發。
    _chargeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _chargeCtrl.addListener(_onChargeTick);
    _chargeCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) _releaseCharge();
    });
    _burstCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    );

    // idle 呼吸：以腳底為錨點的細微縱向縮放，一吸一吐 ~2.6 秒
    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
    if (!widget.paused) _breathCtrl.repeat(reverse: true);
    _breath = CurvedAnimation(parent: _breathCtrl, curve: Curves.easeInOut);

    _bubbleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2100),
    );
    // 進場若已帶泡泡（例如直接落在某情緒），冒一次。
    _bubbleShown = widget.bubble;
    if (widget.bubble != null) _playBubble(widget.bubble!);

    _scheduleNextBlink();
  }

  /// 冒一次頭頂泡泡：時長依泡泡種類（見 mascot_bubbles.dart 註冊表）。
  void _playBubble(EmotionBubble bubble) {
    _bubbleShown = bubble;
    _bubbleCtrl.duration = bubbleSpecFor(bubble).duration;
    _bubbleCtrl.forward(from: 0);
  }

  void _scheduleNextBlink() {
    _blinkTimer?.cancel();
    if (widget.paused) return; // 閒置凍結時不排下一次眨眼
    // 人類眨眼間隔大約 2~6 秒，取隨機避免機械感
    _blinkTimer = Timer(
      Duration(milliseconds: 2400 + _rng.nextInt(3200)),
      () async {
        if (!mounted) return;
        if (MascotEmotion.blinkAssetForPath(widget.asset) != null) {
          await _blinkOnce();
          // 偶爾連眨兩下，更像活的
          if (mounted && _rng.nextDouble() < 0.22) {
            await Future<void>.delayed(const Duration(milliseconds: 140));
            if (mounted) await _blinkOnce();
          }
        }
        if (mounted) _scheduleNextBlink();
      },
    );
  }

  Future<void> _blinkOnce() async {
    setState(() => _eyesClosed = true);
    await Future<void>.delayed(const Duration(milliseconds: 130));
    if (mounted) setState(() => _eyesClosed = false);
  }

  @override
  void didUpdateWidget(covariant MascotStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reactionTick != widget.reactionTick) {
      _reactionCtrl.forward(from: 0);
    }
    // 情緒事件帶了泡泡，且（事件序號、泡泡或立繪改變）就重冒一次。
    // 同情境連點會被 MascotPersona 的 holdDuration 擋掉，不會狂閃。
    if (widget.bubble != null &&
        (oldWidget.bubbleTick != widget.bubbleTick ||
            oldWidget.bubble != widget.bubble ||
            oldWidget.asset != widget.asset)) {
      _playBubble(widget.bubble!);
    }
    if (oldWidget.paused != widget.paused) {
      if (widget.paused) {
        // 閒置凍結：停呼吸、取消眨眼，畫面靜止省電。
        _breathCtrl.stop();
        _blinkTimer?.cancel();
        _eyesClosed = false; // 不要定格在閉眼；隨即重建會套用
      } else {
        // 恢復：重新開始呼吸與眨眼。
        if (!_breathCtrl.isAnimating) _breathCtrl.repeat(reverse: true);
        _scheduleNextBlink();
      }
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _petBlissTimer?.cancel();
    _petCtrl.dispose();
    _breathCtrl.dispose();
    _reactionCtrl.dispose();
    _bubbleCtrl.dispose();
    _chargeCtrl.dispose();
    _burstCtrl.dispose();
    super.dispose();
  }

  bool _isHeadHit(Offset position, {bool relaxed = false}) {
    const center = Offset(126, 88);
    final radiusX = relaxed ? 116.0 : 94.0;
    final radiusY = relaxed ? 88.0 : 70.0;
    final dx = (position.dx - center.dx) / radiusX;
    final dy = (position.dy - center.dy) / radiusY;
    return dx * dx + dy * dy <= 1;
  }

  /// 兔咪本體命中區（含一點觸控寬容）：點擊/充電只在摸得到兔咪的
  /// 位置生效，stage 四角的空白不反應。
  /// 座標是 252×252 stage 的局部空間；兔咪在所有機型都固定這個邏輯
  /// 尺寸（shell 只調整周圍場景高度，不縮放兔咪），所以不需按機型校準。
  bool _isBunnyHit(Offset position) {
    const center = Offset(126, 120);
    final dx = (position.dx - center.dx) / 96;
    final dy = (position.dy - center.dy) / 105;
    return dx * dx + dy * dy <= 1;
  }

  double _headDragAmount(Offset position) =>
      ((position.dx - 126) / 94).clamp(-1.0, 1.0).toDouble();

  void _triggerTapReaction() {
    _reactionCtrl.forward(from: 0);
    widget.onTap();
  }

  // ── 摸頭 ──

  /// 每幀收斂：彈簧跟手、放開回正、清掉過期愛心；全歸位就停驅動器省電。
  void _petFrame() {
    _petClock += 1;
    _petLean += (_petLeanTarget - _petLean) * 0.16;
    final pressTarget = _isPetting ? 1.0 : 0.0;
    _petPress += (pressTarget - _petPress) * 0.11;
    _hearts.removeWhere((h) => _petClock - h.bornTick > _PetHeart.lifetimeTicks);
    if (!_isPetting &&
        _hearts.isEmpty &&
        _petPress < 0.01 &&
        _petLean.abs() < 0.01) {
      _petLean = 0;
      _petPress = 0;
      _petCtrl.stop();
    }
  }

  void _beginHeadPet(Offset position) {
    _isPetting = true;
    _petStartClock = _petClock;
    _lastPetX = position.dx;
    _strokeAccum = 0;
    _petTotalStroke = 0;
    _petLeanTarget = _headDragAmount(position);
    playHaptic(HapticLevel.selection);
    // 摸滿一小段時間 → 瞇眼享受（有對應差分才會真的換臉）
    _petBlissTimer?.cancel();
    _petBlissTimer = Timer(const Duration(milliseconds: 550), () {
      if (mounted && _isPetting) setState(() => _petEyesClosed = true);
    });
    if (!_petCtrl.isAnimating) _petCtrl.repeat();
  }

  void _updateHeadPet(Offset position) {
    if (!_isPetting) return;
    if (!_isHeadHit(position, relaxed: true)) {
      _endHeadPet();
      return;
    }
    _petLeanTarget = _headDragAmount(position);
    final dx = position.dx - _lastPetX;
    _lastPetX = position.dx;
    _strokeAccum += dx.abs();
    _petTotalStroke += dx.abs();
    // 每搓滿一段距離：指尖冒一顆小愛心＋輕觸覺，回饋跟著搓動節奏走
    if (_strokeAccum >= 22) {
      _strokeAccum = 0;
      if (_hearts.length < 8) {
        _hearts.add(
          _PetHeart(
            origin: position,
            bornTick: _petClock,
            drift: _rng.nextDouble() * 2 - 1,
            size: 6.0 + _rng.nextDouble() * 2.5,
          ),
        );
      }
      playHaptic(HapticLevel.selection);
    }
  }

  void _endHeadPet() {
    if (!_isPetting) return;
    _isPetting = false;
    _petLeanTarget = 0;
    _petBlissTimer?.cancel();
    if (_petEyesClosed) setState(() => _petEyesClosed = false);
    // 有真的搓到（或摸了一小段時間）才算一次摸頭，避免誤觸也冒愛心語音
    final petted = _petTotalStroke > 18 || _petClock - _petStartClock > 27;
    if (petted) widget.onHeadPet?.call();
  }

  // ── 充電互動：長按蓄力 → 放開（或蓄滿）爆發 ──

  /// 蓄力觸覺：每跨過一檔（1/4）震一下，越接近蓄滿節奏感越明顯。
  void _onChargeTick() {
    final step = (_chargeCtrl.value * 4).floor();
    if (_isCharging && step > _chargeTickStep) {
      _chargeTickStep = step;
      playHaptic(HapticLevel.selection);
    }
  }

  void _beginCharge(Offset origin) {
    _endHeadPet(); // 保險：長按贏得手勢後不該殘留摸頭狀態
    _isCharging = true;
    _chargeOrigin = origin;
    _chargeTickStep = 0;
    playHaptic(HapticLevel.selection);
    _chargeCtrl.forward(from: 0);
  }

  void _updateCharge(Offset position) {
    if (!_isCharging) return;
    // 手指滑遠＝改變心意：光點散掉、兔咪緩緩回正，不觸發爆發。
    if ((position - _chargeOrigin).distance > 60) _cancelCharge();
  }

  void _releaseCharge() {
    if (!_isCharging) return;
    _isCharging = false;
    // 快放也有小跳（下限 0.35）；蓄滿（自動爆發）跳最高、星星最多。
    _burstPower = 0.35 + 0.65 * _chargeCtrl.value;
    _chargeCtrl.stop();
    _chargeCtrl.value = 0; // 下蹲瞬間釋放成起跳，squash→stretch 的「啵」
    playHaptic(_burstPower > 0.7 ? HapticLevel.medium : HapticLevel.light);
    widget.onEnergize?.call();
    _burstCtrl.forward(from: 0);
  }

  void _cancelCharge() {
    if (!_isCharging) return;
    _isCharging = false;
    _chargeCtrl.animateBack(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  /// 兔咪本體。有閉眼／瞇眼差分時把圖都疊進樹裡（用 opacity 切換），
  /// 讓差分圖保持解碼狀態，第一次換臉才不會閃白。
  /// 顯示優先序：摸頭瞇眼享受 > 眨眼 > 底圖。
  Widget _buildBunnyImage() {
    final blinkAsset = MascotEmotion.blinkAssetForPath(widget.asset);
    final blissAsset = MascotEmotion.petBlissAssetForPath(widget.asset);
    final layers = <String>{widget.asset, ?blinkAsset, ?blissAsset};
    if (layers.length == 1) {
      return Image.asset(widget.asset, fit: BoxFit.contain);
    }
    final String shown;
    if (_petEyesClosed && blissAsset != null) {
      shown = blissAsset;
    } else if (_eyesClosed && blinkAsset != null) {
      shown = blinkAsset;
    } else {
      shown = widget.asset;
    }
    return Stack(
      fit: StackFit.passthrough,
      children: [
        for (final asset in layers)
          Opacity(
            opacity: asset == shown ? 1 : 0,
            child: Image.asset(asset, fit: BoxFit.contain),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 快點（點頭也是）＝一般點擊反應；真正的摸頭要在頭上「搓動」。
      // 手勢語意：點＝打招呼、按住不動＝充電、頭上滑動＝摸頭。
      // 三者都只在兔咪本體範圍內生效，點到 stage 空白處不反應。
      onTapUp: (details) {
        if (_isBunnyHit(details.localPosition)) _triggerTapReaction();
      },
      onPanStart: (details) {
        if (_isHeadHit(details.localPosition)) {
          _beginHeadPet(details.localPosition);
        }
      },
      onPanUpdate: (details) {
        _updateHeadPet(details.localPosition);
      },
      onPanEnd: (_) => _endHeadPet(),
      onPanCancel: _endHeadPet,
      // 充電互動：按住不動（長按）蓄力，放開爆發。快點＝點擊反應、
      // 頭上滑動＝摸頭，互不干擾——長按只在手指靜止過門檻時成立。
      onLongPressStart: (details) {
        if (_isBunnyHit(details.localPosition)) {
          _beginCharge(details.localPosition);
        }
      },
      onLongPressMoveUpdate: (details) =>
          _updateCharge(details.localPosition),
      onLongPressEnd: (_) => _releaseCharge(),
      onLongPressCancel: _cancelCharge,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 252,
        height: 252,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _reactionCtrl,
            _petCtrl,
            _bubbleCtrl,
            _chargeCtrl,
            _burstCtrl,
          ]),
          builder: (context, child) {
            // 摸頭：朝手指方向輕靠＋像承受手掌重量微微下沉。
            // 沒有自己的節奏——手停動作就停（_petFrame 只做彈簧收斂）。
            final petPress = _petPress;
            final petScaleX = 1 + 0.012 * petPress;
            final petScaleY = 1 - 0.022 * petPress;
            final petOffsetX = _petLean * 3.6 * petPress;
            final petOffsetY = 2.2 * petPress;
            final petTilt = _petLean * 0.032 * petPress;

            // 點擊反應：迷你版充電爆發——快速小蹲 → 小跳 → 落地回彈。
            // 錨定「有重量的身體」而不是 UI 等比縮放。
            final r = _reactionCtrl.value;
            double tapLift = 0, tapSink = 0, tapSy = 1, tapSx = 1;
            if (r > 0 && r < 1) {
              const crouchEnd = 0.18, airEnd = 0.72;
              if (r < crouchEnd) {
                final t = Curves.easeOut.transform(r / crouchEnd);
                tapSy = 1 - 0.045 * t;
                tapSx = 1 + 0.030 * t;
                tapSink = 4.5 * t; // 中心錨補償：蹲下時腳保持貼地
              } else if (r < airEnd) {
                final u = (r - crouchEnd) / (airEnd - crouchEnd);
                tapLift = -10 * 4 * u * (1 - u);
                final v = (1 - 2 * u).abs();
                tapSy = 1 + 0.035 * v;
                tapSx = 1 - 0.020 * v;
              } else {
                final t = (r - airEnd) / (1 - airEnd);
                final squash = math.sin(math.pi * t);
                tapSy = 1 - 0.030 * squash;
                tapSx = 1 + 0.022 * squash;
                tapSink = 1.5 * squash;
              }
            }

            // 充電蓄力：下蹲（squash）＋越蓄越明顯的小顫動（蓄勁感）。
            // scale 以中心為錨，下沉補償讓腳保持貼地。
            final charge = _chargeCtrl.value;
            final chargeEase = Curves.easeInOut.transform(charge);
            final chargeSquash = 0.06 * chargeEase;
            final chargeWobble = math.sin(charge * math.pi * 7) * 0.010 * charge;
            final chargeSink = 6.0 * chargeEase;

            // 爆發大跳：拋物線離地（高度 ∝ 蓄力量）＋沿速度方向拉長，
            // 落地接一下 squash 回彈。
            final burst = _burstCtrl.value;
            double burstLift = 0, burstScaleY = 1, burstScaleX = 1;
            if (burst > 0 && burst < 1) {
              final p = _burstPower;
              const airEnd = 0.74; // 空中/落地演出的分界
              if (burst < airEnd) {
                final u = burst / airEnd;
                final ramp = math.min(burst / 0.06, 1.0); // 首幀不瞬跳
                burstLift = -(16 + 26 * p) * 4 * u * (1 - u);
                final v = (1 - 2 * u).abs() * ramp;
                burstScaleY = 1 + 0.055 * p * v;
                burstScaleX = 1 - 0.035 * p * v;
              } else {
                final t = (burst - airEnd) / (1 - airEnd);
                final squash = math.sin(math.pi * t);
                burstLift = 3.0 * p * squash; // squash 時微沉，腳不飄
                burstScaleY = 1 - 0.06 * p * squash;
                burstScaleX = 1 + 0.045 * p * squash;
              }
            }

            // 地面陰影：依離地高度同步縮小變淡 → 「離開地面」的感覺。
            // 位置 bottom 要對到兔咪 CG 圖裡腳的位置（1024×1024 畫布，腳在 ~80%）
            // 點擊小跳與充電大跳各自歸一化再相乘，互不干擾原本手感。
            final liftProgress = (-tapLift / 10).clamp(0.0, 1.0);
            final burstLiftProgress = (-burstLift / 42).clamp(0.0, 1.0);
            final shadowScale =
                ui.lerpDouble(1, 0.88, liftProgress)! *
                ui.lerpDouble(1, 0.78, burstLiftProgress)!;
            final shadowOpacity =
                ui.lerpDouble(0.24, 0.13, liftProgress)! *
                ui.lerpDouble(1, 0.55, burstLiftProgress)!;
            final shadowColor = Color.lerp(
              const Color(0xFF5B4436),
              widget.accent,
              0.12,
            )!;
            return Stack(
              alignment: Alignment.center,
              children: [
                // 腳下橢圓陰影（在 sparkle 跟兔咪本體下方）
                Positioned(
                  // 對齊兔咪 CG 的腳底：shadow painter 的接觸影中心約落在 stage y=216。
                  bottom: 22,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Transform.scale(
                      scaleX: shadowScale,
                      child: SizedBox(
                        width: 158,
                        height: 38,
                        child: CustomPaint(
                          painter: _MascotGroundShadowPainter(
                            color: shadowColor,
                            opacity: shadowOpacity,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CustomPaint(
                          painter: _MascotSparklePainter(
                            progress: _reactionCtrl.value,
                            color: widget.accent,
                          ),
                        ),
                        CustomPaint(
                          painter: _MascotPetHeartsPainter(
                            hearts: List.of(_hearts),
                            clock: _petClock,
                            color: widget.accent,
                          ),
                        ),
                        CustomPaint(
                          painter: _MascotChargePainter(
                            progress: charge,
                            color: widget.accent,
                          ),
                        ),
                        CustomPaint(
                          painter: _MascotBurstPainter(
                            progress: burst,
                            power: _burstPower,
                            color: widget.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(
                    petOffsetX,
                    tapLift + tapSink + petOffsetY + burstLift + chargeSink,
                  ),
                  child: Transform.rotate(
                    angle: petTilt + chargeWobble,
                    alignment: Alignment.bottomCenter,
                    child: Transform.scale(
                      scaleX:
                          tapSx *
                          petScaleX *
                          (1 + chargeSquash * 0.55) *
                          burstScaleX,
                      scaleY:
                          tapSy *
                          petScaleY *
                          (1 - chargeSquash) *
                          burstScaleY,
                      child: child,
                    ),
                  ),
                ),
                // 頭頂情緒泡泡：畫在最上層（蓋住頭頂前方），不吃點擊。
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: MascotEmotionBubblePainter(
                        progress: _bubbleCtrl.value,
                        bubble: _bubbleShown,
                        accent: widget.accent,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 360),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(
                scale: Tween(begin: 0.92, end: 1.0).animate(anim),
                child: child,
              ),
            ),
            child: Padding(
              key: ValueKey(widget.asset),
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
              child: AnimatedBuilder(
                animation: _breath,
                builder: (context, bunny) => Transform.scale(
                  scaleY: 1 + 0.013 * _breath.value,
                  scaleX: 1 - 0.005 * _breath.value,
                  alignment: Alignment.bottomCenter,
                  child: bunny,
                ),
                child: _buildBunnyImage(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MascotGroundShadowPainter extends CustomPainter {
  final Color color;
  final double opacity;

  const _MascotGroundShadowPainter({
    required this.color,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    // 三層（由淡到深）：ambient 大暈 → 中層 pool → 雙腳 contact kiss。
    // 視角是斜俯視，暈的重心放在畫布下半（往觀者方向 pool）；
    // kiss 貼在畫布上緣附近 = 兔咪腳底正下方，蓋掉 CG 腳掌白邊
    // 與陰影之間的亮縫，才有「體重壓在地上」的感覺。

    final ambient = Paint()
      ..color = color.withValues(alpha: opacity * 0.34)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 11);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, size.height * 0.58),
        width: size.width * 0.96,
        height: size.height * 0.62,
      ),
      ambient,
    );

    final pool = Paint()
      ..color = color.withValues(alpha: opacity * 0.70)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, size.height * 0.52),
        width: size.width * 0.62,
        height: size.height * 0.40,
      ),
      pool,
    );

    // 左右腳各一個小接觸影（CG 站姿雙腳中心約在 ±12% 畫布寬），
    // 比 base opacity 再深一階，蓋掉腳掌白邊下的亮縫
    final kiss = Paint()
      ..color = color.withValues(alpha: (opacity * 1.3).clamp(0.0, 1.0))
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3.5);
    for (final dx in [-size.width * 0.12, size.width * 0.12]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx + dx, size.height * 0.27),
          width: size.width * 0.26,
          height: size.height * 0.26,
        ),
        kiss,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MascotGroundShadowPainter old) =>
      old.color != color || old.opacity != opacity;
}

class _MascotSparklePainter extends CustomPainter {
  final double progress;
  final Color color;

  _MascotSparklePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final opacity = (progress < 0.5 ? progress * 2 : (1 - progress) * 2).clamp(
      0.0,
      1.0,
    );
    final center = Offset(size.width / 2, size.height / 2 - 20);
    final specs = <({double angle, double distance, double size})>[
      (angle: -2.35, distance: 86, size: 7),
      (angle: -1.75, distance: 100, size: 5),
      (angle: -0.92, distance: 92, size: 8),
      (angle: -0.18, distance: 76, size: 5),
      (angle: 0.62, distance: 95, size: 7),
      (angle: 2.65, distance: 78, size: 5),
    ];
    for (final spec in specs) {
      final distance = spec.distance * Curves.easeOut.transform(progress);
      final offset = Offset(
        center.dx + distance * math.cos(spec.angle),
        center.dy + distance * math.sin(spec.angle),
      );
      final paint = Paint()
        ..color = color.withValues(alpha: 0.55 * opacity)
        ..style = PaintingStyle.fill;
      _drawEightStar(canvas, offset, spec.size * (0.7 + progress * 0.3), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MascotSparklePainter old) =>
      old.progress != progress || old.color != color;
}

/// 八角星（四長四短尖角），sparkle / 充電爆發共用。
void _drawEightStar(Canvas canvas, Offset center, double radius, Paint paint) {
  final path = Path();
  for (var i = 0; i < 8; i++) {
    final r = i.isEven ? radius : radius * 0.42;
    final angle = -math.pi / 2 + i * math.pi / 4;
    final p = Offset(
      center.dx + math.cos(angle) * r,
      center.dy + math.sin(angle) * r,
    );
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  path.close();
  canvas.drawPath(path, paint);
}

/// 充電光點：蓄力時能量光點從四周螺旋聚向兔咪，越蓄越亮越密。
/// 光點表寫死（角度/距離/相位/大小/速度），避免每幀隨機跳動；
/// 顏色由頁面主色偏暖金，跨頁都像「能量」而不會撞到主題色。
class _MascotChargePainter extends CustomPainter {
  final double progress;
  final Color color;

  _MascotChargePainter({required this.progress, required this.color});

  static const _motes =
      <({double angle, double dist, double phase, double size, double speed})>[
        (angle: -2.60, dist: 108, phase: 0.00, size: 2.6, speed: 1.00),
        (angle: -1.90, dist: 92, phase: 0.42, size: 2.0, speed: 1.25),
        (angle: -1.20, dist: 116, phase: 0.18, size: 3.0, speed: 0.90),
        (angle: -0.50, dist: 98, phase: 0.66, size: 2.2, speed: 1.15),
        (angle: 0.20, dist: 110, phase: 0.30, size: 2.7, speed: 1.05),
        (angle: 0.90, dist: 90, phase: 0.78, size: 1.9, speed: 1.30),
        (angle: 1.70, dist: 114, phase: 0.10, size: 2.4, speed: 0.95),
        (angle: 2.40, dist: 96, phase: 0.54, size: 2.1, speed: 1.20),
        (angle: 3.00, dist: 104, phase: 0.86, size: 2.8, speed: 1.10),
        (angle: -3.10, dist: 100, phase: 0.24, size: 2.3, speed: 1.18),
      ];

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = Offset(size.width / 2, size.height / 2 - 10);
    final glow = Color.lerp(color, const Color(0xFFF2B84B), 0.55)!;
    for (final m in _motes) {
      final t = (progress * m.speed * 2.2 + m.phase) % 1.0;
      final dist = ui.lerpDouble(m.dist, 16, Curves.easeIn.transform(t))!;
      final angle = m.angle + t * 0.9; // 微螺旋，比直線聚攏更有「吸入」感
      final pos =
          center + Offset(math.cos(angle) * dist, math.sin(angle) * dist * 0.82);
      final opacity =
          math.sin(math.pi * t) * (0.25 + 0.75 * progress).clamp(0.0, 1.0);
      canvas.drawCircle(
        pos,
        m.size * (0.7 + 0.5 * progress),
        Paint()..color = glow.withValues(alpha: (0.75 * opacity).clamp(0.0, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MascotChargePainter old) =>
      old.progress != progress || old.color != color;
}

/// 充電爆發：放開瞬間一圈光環「啵」地擴散＋星星向外炸開，
/// 星星數量、飛行距離都 ∝ 蓄力量（power 0.35~1.0）。
class _MascotBurstPainter extends CustomPainter {
  final double progress;
  final double power;
  final Color color;

  _MascotBurstPainter({
    required this.progress,
    required this.power,
    required this.color,
  });

  static const _stars = <({double angle, double dist, double size})>[
    (angle: -2.90, dist: 1.00, size: 7.5),
    (angle: -2.35, dist: 0.86, size: 5.0),
    (angle: -1.85, dist: 1.05, size: 6.5),
    (angle: -1.35, dist: 0.90, size: 8.0),
    (angle: -0.85, dist: 1.08, size: 5.5),
    (angle: -0.35, dist: 0.94, size: 7.0),
    (angle: 0.15, dist: 1.02, size: 5.0),
    (angle: 0.75, dist: 0.88, size: 6.0),
    (angle: 1.45, dist: 0.96, size: 4.5),
    (angle: 2.15, dist: 0.90, size: 5.5),
    (angle: 2.65, dist: 1.04, size: 6.5),
    (angle: 3.05, dist: 0.84, size: 4.5),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final center = Offset(size.width / 2, size.height / 2 - 24);
    final glow = Color.lerp(color, const Color(0xFFF2B84B), 0.45)!;
    final eased = Curves.easeOutCubic.transform(progress);
    // 前 20% 快速亮起，之後線性淡出
    final fade = progress < 0.2 ? progress / 0.2 : 1 - (progress - 0.2) / 0.8;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ui.lerpDouble(3.0, 0.6, eased)!
      ..color = glow.withValues(alpha: 0.38 * (1 - progress) * power);
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: ui.lerpDouble(70, 190 + 60 * power, eased)!,
        height: ui.lerpDouble(56, 150 + 48 * power, eased)!,
      ),
      ringPaint,
    );

    final count = 7 + (5 * power).round();
    final base = 62 + 44 * power;
    for (var i = 0; i < count && i < _stars.length; i++) {
      final s = _stars[i];
      final dist = base * s.dist * eased;
      final pos =
          center +
          Offset(
            math.cos(s.angle) * dist,
            math.sin(s.angle) * dist * 0.9 - 12 * eased, // 整體微微上飄
          );
      final paint = Paint()
        ..color = glow.withValues(alpha: (0.62 * fade).clamp(0.0, 1.0));
      _drawEightStar(
        canvas,
        pos,
        s.size * (0.65 + 0.35 * power) * (0.8 + 0.3 * eased),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MascotBurstPainter old) =>
      old.progress != progress || old.power != power || old.color != color;
}

/// 一顆摸頭愛心：從指尖冒出、往上飄、左右微晃、淡出。
/// 壽命用摸頭驅動器的幀時鐘計（不用牆鐘），測試裡才有確定性。
class _PetHeart {
  static const double lifetimeTicks = 50; // ~0.83 秒（60fps）

  final Offset origin;
  final double bornTick;
  final double drift; // 水平漂移個性 -1..1
  final double size;

  const _PetHeart({
    required this.origin,
    required this.bornTick,
    required this.drift,
    required this.size,
  });
}

/// 摸頭愛心層：每搓滿一段距離冒一顆，位置跟著當下指尖走，
/// 讓「摸的回饋」出現在手真正摸到的地方。
class _MascotPetHeartsPainter extends CustomPainter {
  final List<_PetHeart> hearts;
  final double clock;
  final Color color;

  _MascotPetHeartsPainter({
    required this.hearts,
    required this.clock,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (hearts.isEmpty) return;
    final pink = Color.lerp(color, const Color(0xFFEF8A9C), 0.72)!;
    for (final h in hearts) {
      final t = ((clock - h.bornTick) / _PetHeart.lifetimeTicks).clamp(
        0.0,
        1.0,
      );
      if (t >= 1) continue;
      final eased = Curves.easeOut.transform(t);
      final pos =
          h.origin +
          Offset(math.sin(t * math.pi * 2) * 2.0 * h.drift, -30 * eased);
      final fade = t < 0.18 ? t / 0.18 : 1 - (t - 0.18) / 0.82;
      final pop = t < 0.18
          ? Curves.easeOutBack.transform(t / 0.18)
          : 1.0; // 冒出來時「啵」地彈一下
      _drawHeart(
        canvas,
        pos,
        h.size * pop,
        Paint()..color = pink.withValues(alpha: (0.85 * fade).clamp(0.0, 1.0)),
      );
    }
  }

  void _drawHeart(Canvas canvas, Offset c, double s, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy + s * 0.85)
      ..cubicTo(
        c.dx - 1.25 * s,
        c.dy - 0.05 * s,
        c.dx - 0.55 * s,
        c.dy - 0.95 * s,
        c.dx,
        c.dy - 0.32 * s,
      )
      ..cubicTo(
        c.dx + 0.55 * s,
        c.dy - 0.95 * s,
        c.dx + 1.25 * s,
        c.dy - 0.05 * s,
        c.dx,
        c.dy + s * 0.85,
      )
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MascotPetHeartsPainter old) =>
      old.clock != clock ||
      old.hearts.length != hearts.length ||
      old.color != color;
}

class _SpeechBubblePainter extends CustomPainter {
  final Color color;
  final Color borderColor;
  _SpeechBubblePainter({required this.color, required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height - 8),
      const Radius.circular(16),
    );
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawRRect(bodyRect.shift(const Offset(0, 2)), shadowPaint);
    canvas.drawRRect(bodyRect, fillPaint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRRect(bodyRect, borderPaint);

    final tailPath = Path()
      ..moveTo(size.width / 2 - 8, size.height - 8)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width / 2 + 8, size.height - 8)
      ..close();
    canvas.drawPath(tailPath, fillPaint);
    canvas.drawPath(tailPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SpeechBubblePainter old) =>
      old.color != color || old.borderColor != borderColor;
}
