// 兔咪場景共用元件：把首頁那組「兔咪 + 對話框 + 互動動畫」抽成可共用 widget，
// 讓其他頁面（專注計時、喝水、體重、家庭）能套用同樣的呈現。
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

import '../pages/home/room_metrics.dart';
import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/mascot.dart';
import '../utils/scene_time.dart';
import '../utils/sfx_service.dart';
import '../utils/wardrobe_catalog.dart';
import '../utils/wardrobe_store.dart';
import 'mascot_bubbles.dart';
import 'reward_animation_anchor.dart';

/// 搓動頭部時從指尖冒出的小愛心壽命；原本約 0.83 秒，延長 0.3 秒。
@visibleForTesting
const Duration mascotPetHeartLifetime = Duration(milliseconds: 1130);

const Duration _mascotPetMinimumHold = Duration(milliseconds: 450);

/// 兔咪環境光融合參數（四時段完整背景的房間用）。
///
/// 由頁面依 [SceneTimeState] 權重「算好再傳入」：兔咪層自己不讀時間，
/// 跟背景 crossfade 同一次 rebuild 更新，不會出現圖已換色、兔咪還停在
/// 上一分鐘的錯拍。不傳（null）= 中性，其他頁行為與原本完全相同。
@immutable
class MascotSceneLighting {
  /// 色溫濾鏡（`ColorFilter.matrix` 的 20 值，白平衡式 scale+offset）；
  /// null = 不套濾鏡（白天核心＝零成本路徑）。
  final List<double>? colorMatrix;

  /// 接地影的環境色（會再與頁面 accent 輕混，維持既有質感）。
  final Color shadowColor;

  /// 接地影基準不透明度（中性 0.24；光源越近/越低角度影子越實）。
  final double shadowOpacity;

  /// 接地影橫向偏移 px（正 = 影子往右 = 光從左來）。跳躍時會放大
  /// 偏移，側光下「人起影跑」的方向感更明顯。
  final double shadowDx;

  const MascotSceneLighting({
    this.colorMatrix,
    required this.shadowColor,
    required this.shadowOpacity,
    this.shadowDx = 0,
  });

  static const MascotSceneLighting neutral = MascotSceneLighting(
    shadowColor: Color(0xFF5B4436),
    shadowOpacity: 0.24,
  );
}

/// 房間光源幾何：四時段的接地影偏移／強度，依「這個房間的窗與檯燈
/// 在哪」逐房設定（註冊表見 widgets/scene_rooms.dart）。
///
/// 色溫刻意**不做**成房間參數——同一顆太陽、同一種黃昏，四時段色溫
/// 全 App 一致（見 [mascotLightingForScene]），房間只決定影子往哪跑。
/// 這也是「新造型零調整」的關鍵：融合只跟時間與房間有關，跟兔咪
/// 身上穿什麼無關。
@immutable
class RoomLightGeometry {
  /// 各時段接地影橫向偏移 px（正 = 影子往右 = 光源在左）。
  final double morningDx, dayDx, duskDx, nightDx;

  /// 各時段接地影基準不透明度（光源越近／角度越低影子越實）。
  final double morningOpacity, dayOpacity, duskOpacity, nightOpacity;

  const RoomLightGeometry({
    required this.morningDx,
    required this.dayDx,
    required this.duskDx,
    required this.nightDx,
    this.morningOpacity = 0.26,
    this.dayOpacity = 0.22,
    this.duskOpacity = 0.24,
    this.nightOpacity = 0.24,
  });
}

/// 由場景時段權重算出兔咪環境光。
///
/// 色溫（白平衡式 scale+offset）：清晨粉金、白天中性、黃昏琥珀、夜晚
/// 燈暖微暗；量刻意小——目標是「坐進光線裡」，不是換一隻兔子。因為
/// 濾鏡乘在「當下顯示的任何兔咪圖」上（含造型皮膚與表情差分），
/// 新造型不需要任何逐圖調整。接地影的方向與濃度吃 [geometry]。
MascotSceneLighting mascotLightingForScene(
  SceneTimeState s,
  RoomLightGeometry geometry,
) {
  final rs = s.blendValue(morning: 1.02, day: 1, dusk: 1.04, night: 0.97);
  final gs = s.blendValue(morning: 0.99, day: 1, dusk: 0.965, night: 0.915);
  final bs = s.blendValue(morning: 0.965, day: 1, dusk: 0.90, night: 0.86);
  final ro = s.blendValue(morning: 5, day: 0, dusk: 8, night: 7);
  final go = s.blendValue(morning: 1, day: 0, dusk: 1, night: 2);
  final bo = s.blendValue(morning: 0, day: 0, dusk: -4, night: -2);
  final isIdentity =
      (rs - 1).abs() < 0.004 &&
      (gs - 1).abs() < 0.004 &&
      (bs - 1).abs() < 0.004 &&
      ro.abs() < 0.5 &&
      go.abs() < 0.5 &&
      bo.abs() < 0.5;
  return MascotSceneLighting(
    // 白天核心 = null（零成本路徑，不掛 ColorFiltered）。
    colorMatrix: isIdentity
        ? null
        : <double>[
            rs, 0, 0, 0, ro, //
            0, gs, 0, 0, go, //
            0, 0, bs, 0, bo, //
            0, 0, 0, 1, 0,
          ],
    // 接地影環境色（全房間共用的暖木調；會再與頁面 accent 輕混）。
    shadowColor: s.blendOpaque(
      morning: const Color(0xFF6B4B38),
      day: const Color(0xFF5B4436),
      dusk: const Color(0xFF6F4529),
      night: const Color(0xFF4E4238),
    ),
    shadowOpacity: s.blendValue(
      morning: geometry.morningOpacity,
      day: geometry.dayOpacity,
      dusk: geometry.duskOpacity,
      night: geometry.nightOpacity,
    ),
    shadowDx: s.blendValue(
      morning: geometry.morningDx,
      day: geometry.dayDx,
      dusk: geometry.duskDx,
      night: geometry.nightDx,
    ),
  );
}

/// 兔咪場景區當下按著的手指數（由 shell 的彩蛋偵測層更新）。
///
/// 單指手勢（點／充電／摸頭）與雙指彩蛋（骰子對決）互讓的依據：
/// 第二指落下的瞬間 [MascotStage] 會取消進行中的充電與摸頭，
/// 避免充電蓄滿自動爆發搶在彩蛋觸發之前。
abstract final class MascotScenePointers {
  static final ValueNotifier<int> count = ValueNotifier<int>(0);
}

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

  /// 點擊兔咪的自訂行為；未提供時走共用的 [MascotContext.tapReaction]。
  final VoidCallback? onTap;
  final VoidCallback? onHeadPet;
  final VoidCallback? onEnergize;

  /// 閒置凍結：true 時兔咪暫停呼吸與眨眼，讓畫面完全靜止省電；
  /// 一有互動由上層轉回 false 即恢復。
  final bool paused;

  /// 環境光融合（見 [MascotSceneLighting]）；null = 中性。
  /// 一般頁面用 [lightGeometry] 就好；這個參數留給需要自己控制
  /// 重算時機／做 A/B 的頁面（例如首頁）。
  final MascotSceneLighting? lighting;

  /// 房間光源幾何：給了就自動跟著 [SceneTimeController]（分鐘級）
  /// 算出四時段色溫＋接地影，頁面不需要自己監聽時間。
  /// 與 [lighting] 同時給時以 [lighting] 為準。
  final RoomLightGeometry? lightGeometry;

  const PersonaScene({
    super.key,
    required this.accent,
    this.reactionTick = 0,
    this.onTap,
    this.onHeadPet,
    this.onEnergize,
    this.paused = false,
    this.lighting,
    this.lightGeometry,
  });

  @override
  Widget build(BuildContext context) {
    // 自動融合：跟著場景時間分鐘級重算（與背景 crossfade 同一個
    // notify，不會出現背景已變色、兔咪還停在上一分鐘的錯拍）。
    if (lighting == null && lightGeometry != null) {
      return ListenableBuilder(
        listenable: SceneTimeController.instance,
        builder: (_, _) => _buildScene(
          context,
          mascotLightingForScene(
            SceneTimeController.instance.state,
            lightGeometry!,
          ),
        ),
      );
    }
    return _buildScene(context, lighting);
  }

  Widget _buildScene(BuildContext context, MascotSceneLighting? lighting) {
    final effectivePaused = paused || MascotIdleScope.pausedOf(context);

    void handleTap() {
      final callback = onTap;
      if (callback != null) {
        callback();
      } else {
        MascotPersona.interact(MascotContext.tapReaction);
      }
    }

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
          onTap: handleTap,
          onHeadPet: handleHeadPet,
          onEnergize: handleEnergize,
          paused: effectivePaused,
          lighting: lighting,
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

  /// 環境光融合（見 [MascotSceneLighting]）；null = 中性。
  final MascotSceneLighting? lighting;

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
    this.lighting,
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
          // 兔咪跟背景同一個寬度縮放（14PM == 1.0 零位移；SE 縮到 ~0.87
          // 才不會相對房間過大）。以 bottomCenter 為錨，腳的落點不因縮放
          // 改變；Transform 會連 hit test 一起變換，手勢座標不受影響。
          child: LayoutBuilder(
            builder: (context, box) => Transform.scale(
              scale: mascotStageScale(
                maxWidth: box.maxWidth,
                maxHeight: box.maxHeight,
              ),
              alignment: Alignment.bottomCenter,
              child: RewardAnimationAnchor(
                kind: RewardAnimationAnchorKind.mascot,
                // 252×252 stage 的胸前／兩手之間，避免看起來像從肚子噴出。
                alignment: const Alignment(0, 0.08),
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
                  lighting: lighting,
                ),
              ),
            ),
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

  /// 環境光融合（見 [MascotSceneLighting]）；null = 中性。
  final MascotSceneLighting? lighting;

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
    this.lighting,
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
  Timer? _blinkStepTimer;
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
  double _petClockMs = 0; // 取自 Ticker elapsed；不受 60/120Hz 螢幕更新率影響
  double _petStartClockMs = 0;
  bool _petEyesClosed = false; // 摸夠久 → 瞇眼享受（有對應差分才真的換臉）
  Timer? _petBlissTimer;
  final List<_PetHeart> _hearts = [];

  // ── 立繪換圖過場與「分頁被收起來」──
  // 七個兔咪頁都常駐在 IndexedStack 裡，沒被選到的那幾頁由 main.dart 的
  // TickerMode 靜音。靜音的 ticker 不會推進 AnimationController，換立繪的
  // AnimatedSwitcher 就會凍在「舊立繪不透明、新立繪全透明」——切回那一頁時
  // 第一幀先閃出上一個動作（多半是預設站姿），才補播 0.36 秒過場。
  // 對策：靜音期間換圖不做過場（duration 0 不需要 tick 就落定），並在剛被
  // 靜音時換掉 switcher 的 key，把離開前沒跑完的過場整組丟掉，免得舊立繪
  // 半透明殘影一起凍在樹上。
  bool _tickersEnabled = true;
  int _poseSwitcherGeneration = 0;

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

    MascotScenePointers.count.addListener(_onScenePointersChanged);

    _scheduleNextBlink();
  }

  /// 雙指彩蛋互讓：第二指落下就放掉單指互動（不觸發爆發／摸頭結算），
  /// 讓場景把手指交給彩蛋長按偵測。摸頭不通知 persona——否則摸頭
  /// 台詞先冒、彩蛋開場又接對局台詞，兔咪像連珠炮。
  void _onScenePointersChanged() {
    if (MascotScenePointers.count.value < 2) return;
    _cancelCharge();
    _endHeadPet(notifyPersona: false);
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
    _blinkTimer = Timer(Duration(milliseconds: 2400 + _rng.nextInt(3200)), () {
      if (!mounted) return;
      if (MascotEmotion.blinkAssetForPath(widget.asset) != null) {
        _blinkOnce(
          onDone: () {
            // 偶爾連眨兩下，更像活的。
            if (_rng.nextDouble() < 0.22) {
              _blinkStepTimer = Timer(
                const Duration(milliseconds: 140),
                () => _blinkOnce(onDone: _scheduleNextBlink),
              );
            } else {
              _scheduleNextBlink();
            }
          },
        );
      } else {
        _scheduleNextBlink();
      }
    });
  }

  void _blinkOnce({required VoidCallback onDone}) {
    if (!mounted || widget.paused) return;
    setState(() => _eyesClosed = true);
    _blinkStepTimer?.cancel();
    _blinkStepTimer = Timer(const Duration(milliseconds: 130), () {
      if (!mounted || widget.paused) return;
      setState(() => _eyesClosed = false);
      onDone();
    });
  }

  void _cancelBlinkTimers() {
    _blinkTimer?.cancel();
    _blinkStepTimer?.cancel();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // valuesOf 會建立依賴：分頁切換造成的靜音／解除靜音都會回到這裡。
    final enabled = TickerMode.valuesOf(context).enabled;
    if (enabled == _tickersEnabled) return;
    _tickersEnabled = enabled;
    // 只在「被收起來」時換 key：重建發生在看不見的時候，切回來不會多一次
    // 重建（也就不會有重解圖的空窗）。
    if (!enabled) _poseSwitcherGeneration++;
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
        _cancelBlinkTimers();
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
    MascotScenePointers.count.removeListener(_onScenePointersChanged);
    _cancelBlinkTimers();
    _petBlissTimer?.cancel();
    unawaited(SfxService.instance.stop(SfxCue.tumiCharge));
    unawaited(SfxService.instance.stop(SfxCue.tumiPet));
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
    _petClockMs = (_petCtrl.lastElapsedDuration?.inMicroseconds ?? 0) / 1000.0;
    _petLean += (_petLeanTarget - _petLean) * 0.16;
    final pressTarget = _isPetting ? 1.0 : 0.0;
    _petPress += (pressTarget - _petPress) * 0.11;
    _hearts.removeWhere(
      (h) => _petClockMs - h.bornMs > mascotPetHeartLifetime.inMilliseconds,
    );
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
    if (MascotScenePointers.count.value >= 2) return; // 雙指＝彩蛋長按中
    if (!_petCtrl.isAnimating) {
      _petClockMs = 0;
      _petCtrl.repeat();
    }
    _isPetting = true;
    _petStartClockMs = _petClockMs;
    _lastPetX = position.dx;
    _strokeAccum = 0;
    _petTotalStroke = 0;
    _petLeanTarget = _headDragAmount(position);
    playHaptic(HapticLevel.selection);
    unawaited(SfxService.instance.playLoop(SfxCue.tumiPet));
    // 摸滿一小段時間 → 瞇眼享受（有對應差分才會真的換臉）
    _petBlissTimer?.cancel();
    _petBlissTimer = Timer(const Duration(milliseconds: 550), () {
      if (mounted && _isPetting) setState(() => _petEyesClosed = true);
    });
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
            bornMs: _petClockMs,
            drift: _rng.nextDouble() * 2 - 1,
            size: 6.5 + _rng.nextDouble() * 2.7,
          ),
        );
      }
      playHaptic(HapticLevel.selection);
    }
  }

  void _endHeadPet({bool notifyPersona = true}) {
    if (!_isPetting) return;
    _isPetting = false;
    unawaited(SfxService.instance.stop(SfxCue.tumiPet));
    _petLeanTarget = 0;
    _petBlissTimer?.cancel();
    if (_petEyesClosed) setState(() => _petEyesClosed = false);
    // 有真的搓到（或摸了一小段時間）才算一次摸頭，避免誤觸也冒愛心語音
    final petted =
        _petTotalStroke > 18 ||
        _petClockMs - _petStartClockMs > _mascotPetMinimumHold.inMilliseconds;
    if (petted && notifyPersona) widget.onHeadPet?.call();
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
    if (MascotScenePointers.count.value >= 2) return; // 雙指＝彩蛋長按中
    _endHeadPet(); // 保險：長按贏得手勢後不該殘留摸頭狀態
    _isCharging = true;
    _chargeOrigin = origin;
    _chargeTickStep = 0;
    playHaptic(HapticLevel.selection);
    unawaited(SfxService.instance.play(SfxCue.tumiCharge));
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
    unawaited(SfxService.instance.stop(SfxCue.tumiCharge));
    unawaited(SfxService.instance.play(SfxCue.tumiJump));
    playHaptic(_burstPower > 0.7 ? HapticLevel.medium : HapticLevel.light);
    widget.onEnergize?.call();
    _burstCtrl.forward(from: 0);
  }

  void _cancelCharge() {
    if (!_isCharging) return;
    _isCharging = false;
    unawaited(SfxService.instance.stop(SfxCue.tumiCharge));
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
      onLongPressMoveUpdate: (details) => _updateCharge(details.localPosition),
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
            final chargeWobble =
                math.sin(charge * math.pi * 7) * 0.010 * charge;
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
            final lighting = widget.lighting ?? MascotSceneLighting.neutral;
            final liftProgress = (-tapLift / 10).clamp(0.0, 1.0);
            final burstLiftProgress = (-burstLift / 42).clamp(0.0, 1.0);
            final maxLift = math.max(liftProgress, burstLiftProgress);
            final shadowScale =
                ui.lerpDouble(1, 0.88, liftProgress)! *
                ui.lerpDouble(1, 0.78, burstLiftProgress)!;
            final shadowOpacity =
                ui.lerpDouble(
                  lighting.shadowOpacity,
                  lighting.shadowOpacity * 0.54,
                  liftProgress,
                )! *
                ui.lerpDouble(1, 0.55, burstLiftProgress)!;
            final shadowColor = Color.lerp(
              lighting.shadowColor,
              widget.accent,
              0.12,
            )!;
            // 側光時「人起影跑」：身體離地越高，影子往光源反方向再滑一點。
            final shadowDx = lighting.shadowDx * (1 + 0.6 * maxLift);
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
                    child: Transform.translate(
                      offset: Offset(shadowDx, 0),
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
                            clockMs: _petClockMs,
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
                          tapSy * petScaleY * (1 - chargeSquash) * burstScaleY,
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
            // 分頁被收起來時直接換圖、且丟掉沒跑完的過場（見 _tickersEnabled）。
            key: ValueKey<int>(_poseSwitcherGeneration),
            duration: _tickersEnabled
                ? const Duration(milliseconds: 360)
                : Duration.zero,
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
                // 環境色溫（清晨粉金/黃昏琥珀/夜晚燈暖微暗）套在兔咪
                // 本體（含眨眼/瞇眼差分）上；白天 colorMatrix 為 null，
                // 走零成本路徑。互動特效（星星/愛心/泡泡）不濾色。
                child: widget.lighting?.colorMatrix == null
                    ? _buildBunnyImage()
                    : ColorFiltered(
                        colorFilter: ColorFilter.matrix(
                          widget.lighting!.colorMatrix!,
                        ),
                        child: _buildBunnyImage(),
                      ),
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
          center +
          Offset(math.cos(angle) * dist, math.sin(angle) * dist * 0.82);
      final opacity =
          math.sin(math.pi * t) * (0.25 + 0.75 * progress).clamp(0.0, 1.0);
      canvas.drawCircle(
        pos,
        m.size * (0.7 + 0.5 * progress),
        Paint()
          ..color = glow.withValues(alpha: (0.75 * opacity).clamp(0.0, 1.0)),
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
/// 壽命用摸頭驅動器的 elapsed time 計（不用牆鐘），測試裡才有確定性。
class _PetHeart {
  final Offset origin;
  final double bornMs;
  final double drift; // 水平漂移個性 -1..1
  final double size;

  const _PetHeart({
    required this.origin,
    required this.bornMs,
    required this.drift,
    required this.size,
  });
}

/// 摸頭愛心層：每搓滿一段距離冒一顆，位置跟著當下指尖走，
/// 讓「摸的回饋」出現在手真正摸到的地方。
class _MascotPetHeartsPainter extends CustomPainter {
  final List<_PetHeart> hearts;
  final double clockMs;
  final Color color;

  _MascotPetHeartsPainter({
    required this.hearts,
    required this.clockMs,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (hearts.isEmpty) return;
    final pink = Color.lerp(color, const Color(0xFFEF8A9C), 0.72)!;
    for (final h in hearts) {
      final t = ((clockMs - h.bornMs) / mascotPetHeartLifetime.inMilliseconds)
          .clamp(0.0, 1.0);
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
        Paint()..color = pink.withValues(alpha: (0.92 * fade).clamp(0.0, 1.0)),
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
      old.clockMs != clockMs ||
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
