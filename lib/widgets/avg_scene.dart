// AVG（視覺小說）風格的敘事場景播放器。
//
// 為什麼要有這個：app 已經有 24 張場景背景（6 房間 × 4 時段）與整套兔咪情緒
// 差分，但它們目前只被當底圖用。AVG 是唯一能把這批既有資產變成「內容」的格式
// ——同一張圖當背景是一次性的，當場景可以反覆使用。
//
// ⚠️ 使用邊界（違反這條會毀掉它）：**只用於一生一次或罕見的時刻**——引導、
// 回憶本事件、久違回來、節日。AVG 是「坐下來讀」的節奏，習慣 app 是「三十秒
// 打勾就走」的節奏；日常打勾的反應一律維持泡泡＋表情，不進 AVG，否則它會擋在
// 使用者最不耐煩的那一刻。
//
// ⚠️ 格式變了，角色不能變：兔咪一句仍以 20 字為上限、話少、慢半拍
// （docs/tumi_character_guide.md）。AVG 的誘惑是「反正文字便宜就多寫」，不要。
//
// ⚠️ 互動一律是「點畫面」：推進台詞、推進到下一頁，全部同一個手勢。不要再加
// 「繼續」按鈕——在 AVG 裡多一顆按鈕等於告訴使用者「剛才那些點擊不算數」。
//
// 台詞一律走 ARB，不要硬編（引導頁 2026-08-09 才剛把硬編中文清掉）。
import 'package:flutter/material.dart';

import '../utils/app_style.dart';
import '../utils/mascot.dart';
import 'mascot_scene.dart';

/// 場景裡的一句台詞。
class AvgLine {
  /// 台詞內容（從 ARB 取，不要硬編）。
  final String text;

  /// 這句話時兔咪的表情（MascotEmotion 的 assetKey，例如 wake / smile）。
  final String emotion;

  const AvgLine(this.text, {this.emotion = 'neutral_front'});
}

/// 一個敘事場景：一張背景 + 一串台詞，逐句逐字播出，點畫面推進。
///
/// 版型定案（2026-08-09 使用者實機挑選）：**半透明浮動對話框**，背景透出來，
/// 立繪佔畫面高度 40%。當時另一版是不透明貼底＋立繪 46%，沉浸感較強但吃掉
/// 下半部場景；使用者選了看得到場景的這版，另一版已刪除。
class AvgScene extends StatefulWidget {
  const AvgScene({
    super.key,
    required this.background,
    required this.lines,
    required this.onFinished,
    this.speakerName,
    this.onTapSound,
  });

  /// 背景圖 asset 路徑。
  final String background;

  final List<AvgLine> lines;

  /// 最後一句講完後再點一下畫面時呼叫——直接推進到下一頁，不經過任何按鈕。
  final VoidCallback onFinished;

  /// 對話框上的說話者名牌；null 就不顯示。
  final String? speakerName;

  /// 每次點擊推進時的音效回呼。
  final VoidCallback? onTapSound;

  @override
  State<AvgScene> createState() => AvgSceneState();
}

class AvgSceneState extends State<AvgScene> with TickerProviderStateMixin {
  int _lineIndex = 0;
  String _shown = '';

  // 逐字用 AnimationController 而不是 Timer.periodic：跟畫面刷新同步，
  // 而且 widget test 的 pump 推得動（Timer 版在測試裡要等真實時鐘）。
  late final AnimationController _typer = AnimationController(
    vsync: this,
    duration: Duration.zero,
  );

  // 對話框進場（淡入＋輕微上滑）。
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  // ▼ 的呼吸。
  late final AnimationController _caret = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  AvgLine get _line => widget.lines[_lineIndex];

  bool get _lineComplete => !_typer.isAnimating;

  @override
  void initState() {
    super.initState();
    _typer.addListener(_onTypeTick);
    // 逐字跑完時要重繪一次，▼ 才會出現。最後一個 tick 觸發的 setState 發生在
    // status 還是 forward 的時候，少了這行 _lineComplete 會永遠停在舊值。
    _typer.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) setState(() {});
    });
    _enter.forward();
    _caret.repeat(reverse: true);
    _startLine();
  }

  @override
  void dispose() {
    _typer.dispose();
    _enter.dispose();
    _caret.dispose();
    super.dispose();
  }

  void _startLine() {
    final chars = _line.text.characters.length;
    _typer
      ..duration = Duration(milliseconds: 55 * chars)
      ..reset()
      ..forward();
  }

  void _onTypeTick() {
    final chars = _line.text.characters;
    final n = (_typer.value * chars.length).round().clamp(0, chars.length);
    final next = chars.take(n).toString();
    if (next != _shown) setState(() => _shown = next);
  }

  /// 點畫面：整句還沒打完就先補完；已經打完就進下一句；最後一句之後推進頁面。
  void advance() {
    widget.onTapSound?.call();
    if (_typer.isAnimating) {
      _typer.stop();
      setState(() => _shown = _line.text);
      return;
    }
    if (_lineIndex >= widget.lines.length - 1) {
      widget.onFinished();
      return;
    }
    setState(() => _lineIndex++);
    _startLine();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: advance,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(widget.background, fit: BoxFit.cover),
          // 背景下緣壓一層暖色薄罩，讓半透明對話框裡的字在任何一張圖上都讀得到
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  const Color(0xFF4A3524).withValues(alpha: 0.18),
                ],
                stops: const [0.5, 1.0],
              ),
            ),
          ),
          _mascot(),
          Align(alignment: Alignment.bottomCenter, child: _dialogueBox()),
        ],
      ),
    );
  }

  // 立繪。表情之間 crossfade——瞬間硬切是廉價感最重的一點。
  Widget _mascot() {
    final asset = MascotEmotion.values
        .firstWhere(
          (e) => e.assetKey == _line.emotion,
          orElse: () => MascotEmotion.neutralFront,
        )
        .assetPath;
    return LayoutBuilder(
      builder: (context, c) {
        final size = c.maxHeight * 0.40;
        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            // 往上推，讓腳站在對話框上緣附近而不是被切掉
            padding: EdgeInsets.only(bottom: c.maxHeight * 0.28),
            child: SizedBox(
              width: size,
              height: size,
              // 立繪不吃點擊：整頁的點擊要一致推進對話，戳兔咪卻不推進
              // 會讀成「壞掉了」。
              child: IgnorePointer(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: FittedBox(
                    key: ValueKey(asset),
                    child: MascotStage(
                      asset: asset,
                      accent: Colors.orange,
                      reactionTick: 0,
                      onTap: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _dialogueBox() {
    final enter = CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: FadeTransition(
          opacity: enter,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.14),
              end: Offset.zero,
            ).animate(enter),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 108),
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.68),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6B4A2F).withValues(alpha: 0.14),
                    blurRadius: 22,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.speakerName != null) ...[
                    Text(
                      widget.speakerName!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.orange.shade800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    _shown,
                    style: const TextStyle(
                      fontSize: 18,
                      height: 1.55,
                      color: AppInk.strong,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _advanceCaret(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 推進符號：AVG 的標誌性語言。這句打完才出現——打字中就出現會變成催促。
  // 用 ▼ 而不是「點一下繼續」：文字提示是 app 的語彙，不是遊戲的。
  Widget _advanceCaret() {
    return SizedBox(
      height: 14,
      child: Align(
        alignment: Alignment.centerRight,
        child: AnimatedOpacity(
          opacity: _lineComplete ? 1 : 0,
          duration: const Duration(milliseconds: 240),
          child: AnimatedBuilder(
            animation: _caret,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, _caret.value * 3 - 1.5),
              child: Opacity(opacity: 0.45 + _caret.value * 0.55, child: child),
            ),
            child: Icon(
              Icons.arrow_drop_down_rounded,
              size: 26,
              color: Colors.orange.shade700,
            ),
          ),
        ),
      ),
    );
  }
}
