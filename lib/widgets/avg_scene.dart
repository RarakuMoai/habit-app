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
// 台詞一律走 ARB，不要硬編（引導頁 2026-08-09 才剛把硬編中文清掉）。
import 'package:flutter/material.dart';

import '../utils/app_style.dart';
import '../utils/mascot.dart';
import 'mascot_scene.dart';

/// 對話框版型。兩版並存是為了讓使用者實機挑一版，挑定後刪掉另一版。
enum AvgLayout {
  /// 經典 AVG：不透明紙質對話框貼底、立繪大。沉浸感最強，但吃掉下半部畫面。
  solidBox,

  /// 輕量 AVG：半透明對話框貼底、背景透出來、立繪略小。場景看得比較完整。
  glassBox,
}

/// 場景裡的一句台詞。
class AvgLine {
  /// 台詞內容（從 ARB 取，不要硬編）。
  final String text;

  /// 這句話時兔咪的表情（MascotEmotion 的 assetKey，例如 wake / smile）。
  final String emotion;

  const AvgLine(this.text, {this.emotion = 'neutral_front'});
}

/// 一個敘事場景：一張背景 + 一串台詞，逐句逐字播出，點畫面推進。
class AvgScene extends StatefulWidget {
  const AvgScene({
    super.key,
    required this.background,
    required this.lines,
    required this.onFinished,
    required this.layout,
    this.speakerName,
    this.tapHint,
    this.onTapSound,
  });

  /// 背景圖 asset 路徑。
  final String background;

  final List<AvgLine> lines;

  /// 全部播完後呼叫（引導頁用來顯示「繼續」按鈕）。
  final VoidCallback onFinished;

  final AvgLayout layout;

  /// 對話框上的說話者名牌；null 就不顯示。
  final String? speakerName;

  /// 對話框角落的「點一下繼續」提示。
  final String? tapHint;

  /// 每次點擊推進時的音效回呼。
  final VoidCallback? onTapSound;

  @override
  State<AvgScene> createState() => AvgSceneState();
}

class AvgSceneState extends State<AvgScene> with SingleTickerProviderStateMixin {
  int _lineIndex = 0;
  String _shown = '';
  bool _finished = false;

  // 逐字用 AnimationController 而不是 Timer.periodic：跟畫面刷新同步，
  // 而且 widget test 的 pump 推得動（Timer 版在測試裡要等真實時鐘）。
  late final AnimationController _typer = AnimationController(
    vsync: this,
    duration: Duration.zero,
  );

  AvgLine get _line => widget.lines[_lineIndex];

  @override
  void initState() {
    super.initState();
    _typer.addListener(_onTypeTick);
    _startLine();
  }

  @override
  void dispose() {
    _typer.dispose();
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

  /// 點畫面：整句還沒打完就先補完；已經打完就進下一句。
  void advance() {
    if (_finished) return;
    widget.onTapSound?.call();
    if (_typer.isAnimating) {
      _typer.stop();
      setState(() => _shown = _line.text);
      return;
    }
    if (_lineIndex >= widget.lines.length - 1) {
      setState(() => _finished = true);
      widget.onFinished();
      return;
    }
    setState(() => _lineIndex++);
    _startLine();
  }

  bool get _lineComplete => !_typer.isAnimating;

  @override
  Widget build(BuildContext context) {
    final solid = widget.layout == AvgLayout.solidBox;
    return GestureDetector(
      onTap: advance,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(widget.background, fit: BoxFit.cover),
          // 背景壓一層暖色薄罩，讓白字／深字在任何一張圖上都讀得到
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  const Color(0xFF4A3524).withValues(alpha: solid ? 0.10 : 0.18),
                ],
                stops: const [0.5, 1.0],
              ),
            ),
          ),
          _mascot(solid: solid),
          Align(alignment: Alignment.bottomCenter, child: _dialogueBox(solid)),
        ],
      ),
    );
  }

  // 立繪：站在對話框上緣。solidBox 版更大更近，glassBox 版留多一點場景。
  Widget _mascot({required bool solid}) {
    final asset = MascotEmotion.values
        .firstWhere(
          (e) => e.assetKey == _line.emotion,
          orElse: () => MascotEmotion.neutralFront,
        )
        .assetPath;
    return LayoutBuilder(
      builder: (context, c) {
        final size = c.maxHeight * (solid ? 0.46 : 0.40);
        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            // 往上推，讓腳站在對話框上緣附近而不是被切掉
            padding: EdgeInsets.only(bottom: c.maxHeight * (solid ? 0.30 : 0.28)),
            child: SizedBox(
              width: size,
              height: size,
              // 立繪不吃點擊：整頁的點擊要一致推進對話，戳兔咪卻不推進
              // 會讀成「壞掉了」。
              child: IgnorePointer(
                child: FittedBox(
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
        );
      },
    );
  }

  Widget _dialogueBox(bool solid) {
    final boxColor = solid
        ? const Color(0xFFFFFBF4)
        : Colors.white.withValues(alpha: 0.68);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(solid ? 0 : 16, 0, solid ? 0 : 16, solid ? 0 : 14),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 132),
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
          decoration: BoxDecoration(
            color: boxColor,
            borderRadius: solid
                ? const BorderRadius.vertical(top: Radius.circular(22))
                : BorderRadius.circular(22),
            border: Border.all(
              color: Colors.orange.withValues(alpha: solid ? 0.18 : 0.28),
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
              const SizedBox(height: 10),
              // 這句打完才出現的推進提示（打字中出現會催促使用者）
              SizedBox(
                height: 16,
                child: AnimatedOpacity(
                  opacity: _lineComplete && !_finished ? 1 : 0,
                  duration: const Duration(milliseconds: 260),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      widget.tapHint ?? '',
                      style: const TextStyle(fontSize: 12, color: AppInk.faint),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
