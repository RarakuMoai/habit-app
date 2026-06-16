import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_feedback.dart';
import '../../utils/app_style.dart';
import '../../utils/mascot.dart';
import '../../utils/metronome_service.dart';
import '../../utils/prefs_keys.dart';
import '../../utils/sfx_service.dart';
import '../../utils/timer_mutex.dart';
import '../../widgets/hold_repeat_button.dart';

// 節拍器主色（跟專注番茄色、運動青綠明顯區分）
const Color kMetronomeAccent = Color(0xFF7C6BCF);

const int _kMinBpm = 30;
const int _kMaxBpm = 240;
const int _kMaxBeats = 12; // 拍號分子上限（每小節幾拍）
const double _pendMaxAngle = 0.46; // 擺幅 ±約 26°（state 與畫家共用）

// 一種細分選項。parts = 每「主拍」切幾下（傳給音訊引擎做等分）。
// 其餘為自繪音符圖示參數：notes 音符顆數、beams 符尾橫桿、tuplet 連音數字
// （0=不標）、dotted 附點（複合拍「不細分」= 一個附點四分音符）。
class _SubOption {
  final int parts;
  final String label;
  final int notes;
  final int beams;
  final int tuplet;
  final bool dotted;
  const _SubOption(
    this.parts,
    this.label, {
    this.notes = 1,
    this.beams = 0,
    this.tuplet = 0,
    this.dotted = false,
  });
}

// 簡單拍（一拍 = 四分音符，自然二等分）：細分走 2 的系統。
const List<_SubOption> _simpleSubs = [
  _SubOption(1, '不細分'),
  _SubOption(2, '八分', notes: 2, beams: 1),
  _SubOption(3, '三連', notes: 3, beams: 1, tuplet: 3),
  _SubOption(4, '十六分', notes: 4, beams: 2),
  _SubOption(6, '六連', notes: 6, beams: 2, tuplet: 6),
];

// 複合拍（一拍 = 附點四分音符，自然三等分）：細分走 3 的系統。
const List<_SubOption> _compoundSubs = [
  _SubOption(1, '不細分', dotted: true), // 附點四分音符
  _SubOption(3, '八分', notes: 3, beams: 1), // 一拍 3 個八分，不算三連、不標 3
  _SubOption(6, '十六分', notes: 6, beams: 2),
];

class _TimeSignaturePreset {
  final int beats;
  final int unit;
  final String hint;
  const _TimeSignaturePreset(this.beats, this.unit, this.hint);

  String get label => '$beats/$unit';
}

const List<_TimeSignaturePreset> _signaturePresets = [
  _TimeSignaturePreset(1, 4, '每拍都打點'),
  _TimeSignaturePreset(2, 4, '進行曲、快歌'),
  _TimeSignaturePreset(3, 4, '圓舞曲感'),
  _TimeSignaturePreset(4, 4, '最常見'),
  _TimeSignaturePreset(3, 8, '一組三連感'),
  _TimeSignaturePreset(6, 8, '兩組三連感'),
  _TimeSignaturePreset(9, 8, '三組三連感'),
  _TimeSignaturePreset(12, 8, '四組三連感'),
];

/// 單純節拍器：可調 BPM、拍號（每小節拍數）、第一拍重音、音色、音量。
/// 聲音走 [MetronomeService] 的無縫小節循環（取樣級等速）；擺錘＋拍點高亮＋觸覺
/// 走 [Ticker] 的連續相位，開跑時與音訊一起從第一拍對齊。
///
/// 開著時切到其他分頁不會停（跟運動/專注一樣常駐）；只有別的計時器「按開始」
/// 透過 [TimerMutex] 搶鎖時才會停下（由搶鎖那方跳提示）。切到背景才停音訊。
class MetronomeTimer extends StatefulWidget {
  const MetronomeTimer({super.key});

  @override
  State<MetronomeTimer> createState() => _MetronomeTimerState();
}

class _MetronomeTimerState extends State<MetronomeTimer>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // ── 設定（持久化）──
  int _bpm = 120;
  int _beats = 4; // 每小節拍數（拍號分子）
  int _beatUnit = 4; // 拍號分母
  int _subParts = 1; // 每「主拍」切幾下（1=不細分）
  bool _accent = true; // 第一拍重音
  bool _haptic = true; // 觸覺跟拍
  double _volume = 0.75;
  MetronomeTone _tone = MetronomeTone.wood;
  bool _loaded = false;

  // ── 執行狀態 ──
  bool _running = false;
  Ticker? _ticker;
  final ValueNotifier<double> _pendAngle = ValueNotifier<double>(0);
  final ValueNotifier<int> _currentBeat = ValueNotifier<int>(-1);
  double _pendPhase = math.pi / 2; // 起手在極端＝第一拍
  Duration _lastTickElapsed = Duration.zero;
  int _lastBeatIndex = -1;
  Timer? _loopRegenDebounce; // 連續改 BPM 時延遲重生音訊循環，避免狂寫暫存檔

  // tap tempo：保留近期點按時刻，取間隔平均換算 BPM
  final List<DateTime> _taps = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TimerMutex.register(ActiveTimer.metronome, _pauseForOther);
    _ticker = createTicker(_onTick);
    _loadPrefs();
  }

  @override
  void dispose() {
    _halt(); // 純清理，不可 setState
    _ticker?.dispose();
    _pendAngle.dispose();
    _currentBeat.dispose();
    TimerMutex.unregister(ActiveTimer.metronome);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 切到背景就停（ambient 音訊與 ticker 都不該在背景空轉）
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_running) _stop();
    }
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _bpm = (p.getInt(PrefsKeys.metronomeBpm) ?? 120).clamp(
        _kMinBpm,
        _kMaxBpm,
      );
      _beats = (p.getInt(PrefsKeys.metronomeBeats) ?? 4).clamp(1, _kMaxBeats);
      final unit = p.getInt(PrefsKeys.metronomeBeatUnit) ?? 4;
      _beatUnit = unit == 8 ? 8 : 4;
      // 舊版這個 key 存 String（細分 id），新版改存 int（細分數）。舊值還在時
      // 直接 getInt 會型別轉換丟例外 → _loadPrefs 中斷、_loaded 卡 false、節拍器
      // 空白。改用 get() 防禦讀取，非 int（含舊 String）一律退回不細分。
      final subRaw = p.get(PrefsKeys.metronomeSubdivision);
      _subParts = subRaw is int ? subRaw : 1;
      // 若存的細分不適用目前拍號律動，退回不細分
      final opts = _beatUnit == 8 && _beats % 3 == 0
          ? _compoundSubs
          : _simpleSubs;
      if (!opts.any((o) => o.parts == _subParts)) _subParts = 1;
      _accent = p.getBool(PrefsKeys.metronomeAccent) ?? true;
      _haptic = p.getBool(PrefsKeys.metronomeHaptic) ?? true;
      _volume = (p.getDouble(PrefsKeys.metronomeVolume) ?? 0.75).clamp(
        0.0,
        1.0,
      );
      _tone = MetronomeTone.fromId(p.getString(PrefsKeys.metronomeTone));
      _loaded = true;
    });
    // 預載音色，第一拍不漏
    unawaited(MetronomeService.instance.init(tone: _tone));
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(PrefsKeys.metronomeBpm, _bpm);
    await p.setInt(PrefsKeys.metronomeBeats, _beats);
    await p.setInt(PrefsKeys.metronomeBeatUnit, _beatUnit);
    await p.setInt(PrefsKeys.metronomeSubdivision, _subParts);
    await p.setBool(PrefsKeys.metronomeAccent, _accent);
    await p.setBool(PrefsKeys.metronomeHaptic, _haptic);
    await p.setDouble(PrefsKeys.metronomeVolume, _volume);
    await p.setString(PrefsKeys.metronomeTone, _tone.id);
  }

  // ── 啟停 ──

  void _toggle() => _running ? _stop() : _start();

  void _start() {
    if (_running) return;
    // 取鎖：若專注/運動正在倒數，自動暫停它並提示
    final paused = TimerMutex.acquire(ActiveTimer.metronome);
    if (paused != null && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(paused.pausedMessage)));
    }
    // 運作中節拍器面板蓋住兔咪：靜音兔咪語音，避免看不到卻聽到聲音
    MascotPersona.voiceMuted = true;
    setState(() => _running = true);
    _pendPhase = math.pi / 2; // 第一拍對齊
    _lastTickElapsed = Duration.zero;
    _lastBeatIndex = -1;
    _ticker?.start();
    _regenLoop();
    playFeedback(SfxCue.tap, haptic: HapticLevel.medium);
  }

  // 純清理（停 ticker / 音訊 / 釋放鎖），不碰 setState — 可在 dispose、
  // didUpdateWidget 等重建期安全呼叫。
  void _halt() {
    _running = false;
    MascotPersona.voiceMuted = false; // 停止/暫停/離開都恢復兔咪語音
    _ticker?.stop();
    _loopRegenDebounce?.cancel();
    _pendAngle.value = 0;
    _currentBeat.value = -1;
    unawaited(MetronomeService.instance.stopLoop());
    TimerMutex.release(ActiveTimer.metronome);
  }

  void _stop() {
    final wasRunning = _running;
    _halt();
    if (wasRunning && mounted) {
      setState(() {});
      playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
    }
  }

  // 被別的計時器搶走鎖：直接停（節拍器沒有「進度」要保留）
  void _pauseForOther() {
    if (!_running) return;
    _halt();
    if (mounted) setState(() {});
  }

  void _regenLoop() {
    if (!_running) return;
    unawaited(
      MetronomeService.instance.startOrUpdateLoop(
        bpm: _bpm,
        tone: _tone,
        volume: _volume,
        beatsPerBar: _mainBeats,
        accentFirst: _accent,
        subdivisionsPerBeat: _subParts,
        // 複合拍的內部三分由 subdivisionsPerBeat 自然帶出，不需額外次重音
      ),
    );
  }

  // 複合拍：分母 8 且分子是 3 的倍數（3/8 當作 1 個複合大拍）。
  bool get _isCompound => _beatUnit == 8 && _beats % 3 == 0;
  // 主拍數：複合拍 = 分子/3（6/8→2、9/8→3、12/8→4、3/8→1）；簡單拍 = 分子。
  int get _mainBeats => _isCompound ? _beats ~/ 3 : _beats;
  // 目前拍號可選的細分清單（簡單 5 種 / 複合 3 種）。
  List<_SubOption> get _subOptions => _isCompound ? _compoundSubs : _simpleSubs;
  _SubOption get _currentSub => _subOptions.firstWhere(
    (o) => o.parts == _subParts,
    orElse: () => _subOptions.first,
  );

  String get _signatureLabel => '$_beats/$_beatUnit';

  // 每幀：相位前進 π/拍（讀當下 BPM→改速平順）；越過極端＝下一拍。
  void _onTick(Duration elapsed) {
    if (!_running) return;
    final dt = (elapsed - _lastTickElapsed).inMicroseconds / 1e6;
    _lastTickElapsed = elapsed;
    _pendPhase += math.pi * _bpm / 60 * dt;
    _pendAngle.value = _pendMaxAngle * math.sin(_pendPhase);
    final idx = ((_pendPhase - math.pi / 2) / math.pi).floor();
    if (idx != _lastBeatIndex) {
      _lastBeatIndex = idx;
      final beatInBar = idx % _mainBeats;
      _currentBeat.value = beatInBar;
      final isAccent = _accent && _mainBeats > 1 && beatInBar == 0;
      if (_haptic) {
        playHaptic(isAccent ? HapticLevel.medium : HapticLevel.selection);
      }
    }
  }

  // ── 設定變更 ──

  void _setBpm(int v) {
    final nv = v.clamp(_kMinBpm, _kMaxBpm);
    if (nv == _bpm) return;
    setState(() => _bpm = nv);
    _persist();
    if (!_running) return;
    // 擺錘每幀即時跟上；音訊循環 debounce 後重生（避免連按狂寫檔）
    _loopRegenDebounce?.cancel();
    _loopRegenDebounce = Timer(const Duration(milliseconds: 200), _regenLoop);
  }

  void _setTimeSignature(int beats, int unit) {
    final nv = beats.clamp(1, _kMaxBeats);
    final nu = unit == 8 ? 8 : 4;
    if (nv == _beats && nu == _beatUnit) return;
    setState(() {
      _beats = nv;
      _beatUnit = nu;
      // 換拍號後若目前細分不適用新律動（如簡單→複合），退回不細分
      if (!_subOptions.any((o) => o.parts == _subParts)) _subParts = 1;
    });
    _persist();
    _restartBarIfRunning();
    playHaptic(HapticLevel.selection);
  }

  void _setSubdivision(int parts) {
    if (parts == _subParts) return;
    setState(() => _subParts = parts);
    _persist();
    _regenLoop();
    playHaptic(HapticLevel.selection);
  }

  void _restartBarIfRunning() {
    if (!_running) return;
    // 小節結構變了：重置相位讓拍點與新的重音對齊
    _pendPhase = math.pi / 2;
    _lastBeatIndex = -1;
    _currentBeat.value = -1;
    _regenLoop();
  }

  void _setTone(MetronomeTone t) {
    final changed = t != _tone;
    if (changed) {
      setState(() => _tone = t);
      _persist();
      unawaited(MetronomeService.instance.init(tone: t));
      if (_running) _regenLoop();
    }
    // 每次點按都試聽（含重複點同一個）；跑著時循環已有聲就不另外出聲
    if (!_running) {
      MetronomeService.instance.play(volume: _previewVolume, tone: t);
    }
    playHaptic(HapticLevel.selection);
  }

  void _setAccent(bool v) {
    setState(() => _accent = v);
    _persist();
    _regenLoop();
  }

  void _setHaptic(bool v) {
    setState(() => _haptic = v);
    _persist();
  }

  void _setVolume(double v) {
    setState(() => _volume = v.clamp(0.0, 1.0));
    unawaited(MetronomeService.instance.setLoopVolume(_volume));
  }

  double get _previewVolume => _volume <= 0 ? 0.75 : _volume;

  void _tapTempo() {
    final now = DateTime.now();
    // 距離上一拍超過 2 秒視為重新開始抓速
    if (_taps.isNotEmpty &&
        now.difference(_taps.last) > const Duration(seconds: 2)) {
      _taps.clear();
    }
    _taps.add(now);
    if (_taps.length > 5) _taps.removeAt(0);
    playHaptic(HapticLevel.selection);
    // 每次點按都出一聲節拍器音（沒在跑時才出，跑著時循環本身已有聲，免重疊）
    if (!_running) {
      MetronomeService.instance.play(volume: _previewVolume, tone: _tone);
    }
    if (_taps.length >= 2) {
      var totalMs = 0;
      for (var i = 1; i < _taps.length; i++) {
        totalMs += _taps[i].difference(_taps[i - 1]).inMilliseconds;
      }
      final avg = totalMs / (_taps.length - 1);
      if (avg > 0) _setBpm((60000 / avg).round());
    }
  }

  // 速度術語（粗略對照，給使用者一點脈絡）
  String get _tempoTerm {
    final b = _bpm;
    if (b < 60) return 'Largo';
    if (b < 76) return 'Adagio';
    if (b < 108) return 'Andante';
    if (b < 120) return 'Moderato';
    if (b < 156) return 'Allegro';
    if (b < 176) return 'Vivace';
    return 'Presto';
  }

  // ── UI ──

  // 面板拖曳時版面在「緊湊（擺錘左、控制右）↔ 完整（擺錘置中、直排）」間連續交接，
  // 與專注/運動計時同一套（共用擺錘滑動＋縮放、周邊淡入淡出）。
  static const Alignment _kCompactMetroAlign = Alignment(-1.0, -0.18);
  static const Alignment _kFullMetroAlign = Alignment(0.0, -0.34);
  static const double _kDebugForceT = -1; // >=0 強制 t 供截圖微調擺錘定位

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    const color = kMetronomeAccent;
    return LayoutBuilder(
      builder: (context, c) {
        // 多數手機（含 SE，節拍器區 ~416pt）都吃滿可用高度→直接走「完整直排」
        // 版面（擺錘置中放大＋讀數/控制直排），跟專注/運動一致、不留上下空白。
        // 真的很矮（<380）才退回緊湊左右排。
        var t = Curves.easeInOutCubic.transform(
          _smoothRange(380, 400, c.maxHeight),
        );
        if (_kDebugForceT >= 0) t = _kDebugForceT;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: t <= 0
              ? _compactLayout(color, c.maxHeight)
              : t >= 1
              ? _fullLayout(color)
              : _blend(color, c.maxHeight, t),
        );
      },
    );
  }

  static double _smoothRange(double start, double end, double value) {
    final t = ((value - start) / (end - start)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  double _compactMetroSize(double h) => (h - 64).clamp(110.0, 168.0);
  static const double _fullMetroSize = 230;

  // 緊湊版：擺錘做高做窄填滿垂直空間（真實節拍器本就瘦高），寬度讓給右側讀數，
  // 避免上下一堆留白。數字＋拍點＋控制在右、底排 tap＋拍號。
  Widget _compactLayout(Color color, double h, {bool showMetro = true}) {
    // 擺錘高度吃滿可用高度（扣掉底排控制與間距），寬約高的 0.6（瘦高比例）
    final metroH = (h - 60).clamp(150.0, 280.0).toDouble();
    final metroW = metroH * 0.6;
    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  showMetro
                      ? _metronome(color, width: metroW, height: metroH)
                      : SizedBox(width: metroW, height: metroH),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _bpmReadout(color, numberSize: 34),
                          const SizedBox(height: 6),
                          _beatDots(color),
                          const SizedBox(height: 8),
                          _compactControls(color),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            _bottomControls(color, height: 44),
            const SizedBox(height: 2),
          ],
        ),
        Positioned(top: 0, right: 0, child: _settingsEntry(color)),
      ],
    );
  }

  // 完整版（面板收起，空間夠）：擺錘置中當英雄、數字／拍點／控制直排。
  Widget _fullLayout(Color color, {bool showMetro = true}) {
    return Stack(
      children: [
        Column(
          children: [
            const SizedBox(height: 34), // 留給右上設定鈕
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final side = math.min(
                      math.min(c.maxWidth, c.maxHeight),
                      _fullMetroSize,
                    );
                    return showMetro
                        ? _metronome(color, width: side, height: side)
                        : SizedBox.square(dimension: side);
                  },
                ),
              ),
            ),
            const SizedBox(height: 6),
            _bpmReadout(color, numberSize: 52),
            const SizedBox(height: 12),
            _beatDots(color),
            const SizedBox(height: 16),
            _compactControls(color),
            const SizedBox(height: 16),
            _bottomControls(color),
            const SizedBox(height: 6),
          ],
        ),
        Positioned(top: 0, right: 0, child: _settingsEntry(color)),
      ],
    );
  }

  // 交接：擺錘為共用元件，連續在緊湊（左、較小）↔完整（中、較大）滑動＋縮放；
  // 兩套周邊錯開淡入淡出且互不重疊（同專注/運動，降低每幀 saveLayer）。
  Widget _blend(Color color, double h, double t) {
    final fullHeight = math.max(h, 520.0);
    final size =
        _compactMetroSize(h) + (_fullMetroSize - _compactMetroSize(h)) * t;
    final align = Alignment.lerp(_kCompactMetroAlign, _kFullMetroAlign, t)!;
    final compactOpacity = Curves.easeIn.transform((1 - 2 * t).clamp(0.0, 1.0));
    final fullOpacity = Curves.easeIn.transform((2 * t - 1).clamp(0.0, 1.0));
    return ClipRect(
      child: Stack(
        children: [
          if (compactOpacity > 0.01)
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: compactOpacity,
                  child: _compactLayout(color, h, showMetro: false),
                ),
              ),
            ),
          if (fullOpacity > 0.01)
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: fullOpacity,
                  child: OverflowBox(
                    minHeight: fullHeight,
                    maxHeight: fullHeight,
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      height: fullHeight,
                      child: _fullLayout(color, showMetro: false),
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: Align(
                  alignment: align,
                  child: _metronome(color, width: size, height: size),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 擺錘小圖（純視覺，不疊數字）
  Widget _metronome(Color color, {required double width, required double height}) {
    return SizedBox(
      width: width,
      height: height,
      child: RepaintBoundary(
        child: ValueListenableBuilder<double>(
          valueListenable: _pendAngle,
          builder: (context, angle, _) => CustomPaint(
            size: Size(width, height),
            painter: _MetronomePainter(angle: angle, color: color),
          ),
        ),
      ),
    );
  }

  // BPM 大數字 + 速度術語（節拍器與超慢跑共用的讀數樣式）
  Widget _bpmReadout(Color color, {required double numberSize}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$_bpm',
          style: AppType.digits(
            fontSize: numberSize,
            fontWeight: FontWeight.w900,
            color: AppInk.strong,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'BPM · $_tempoTerm',
          style: TextStyle(
            fontSize: (numberSize * 0.3).clamp(11.0, 14.0),
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
            color: color,
          ),
        ),
      ],
    );
  }

  // 緊湊控制：− 大圓開始/停止 +
  Widget _compactControls(Color color) {
    Widget step(IconData icon, VoidCallback? onTap) {
      final on = onTap != null;
      return HoldRepeatButton(
        onTrigger: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: on ? 0.14 : 0.05),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: on ? color : AppInk.faint),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        step(
          Icons.remove_rounded,
          _bpm > _kMinBpm ? () => _setBpm(_bpm - 1) : null,
        ),
        const SizedBox(width: 14),
        _roundStartButton(color, 46),
        const SizedBox(width: 14),
        step(
          Icons.add_rounded,
          _bpm < _kMaxBpm ? () => _setBpm(_bpm + 1) : null,
        ),
      ],
    );
  }

  Widget _roundStartButton(Color color, double size) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: _running ? Colors.white : color,
        shape: CircleBorder(
          side: _running
              ? BorderSide(color: color.withValues(alpha: 0.5), width: 1.5)
              : BorderSide.none,
        ),
        elevation: _running ? 0 : 3,
        shadowColor: color.withValues(alpha: 0.4),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _toggle,
          child: Icon(
            _running ? Icons.stop_rounded : Icons.play_arrow_rounded,
            size: size * 0.46,
            color: _running ? color : Colors.white,
          ),
        ),
      ),
    );
  }

  // 明顯的設定入口：實心膠囊 + 齒輪 + 文字（取代原本很淡的小圖示）
  Widget _settingsEntry(Color color) {
    return Material(
      color: color,
      shape: const StadiumBorder(),
      elevation: 2,
      shadowColor: color.withValues(alpha: 0.4),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () {
          playFeedback(SfxCue.tap);
          _openSettings(color);
        },
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune_rounded, size: 16, color: Colors.white),
              SizedBox(width: 5),
              Text(
                '節拍設定',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _beatDots(Color color) {
    return ValueListenableBuilder<int>(
      valueListenable: _currentBeat,
      builder: (context, cur, _) {
        // FittedBox：拍數多（窄欄）時整排縮放塞進去，不會橫向溢出
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _mainBeats; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: _Dot(
                    active: i == cur,
                    accent: _accent && _mainBeats > 1 && i == 0,
                    color: color,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _bottomControls(Color color, {double height = 48}) {
    // 抽速不再霸佔整列：三者按 4:3:3 分空間，拍號/細分有更明顯的點擊區。
    return Row(
      children: [
        Expanded(flex: 4, child: _tapButton(color, height)),
        const SizedBox(width: 8),
        Expanded(flex: 3, child: _signaturePill(color, height)),
        const SizedBox(width: 8),
        Expanded(flex: 3, child: _subdivisionPill(color, height)),
      ],
    );
  }

  Widget _tapButton(Color color, double height) {
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _tapTempo,
        child: Container(
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.touch_app_rounded, size: 18, color: color),
                const SizedBox(width: 6),
                Text(
                  '點按抓速',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppInk.strong,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 拍號彈出鈕：顯示目前拍號，點開氣泡選 8 個拍號。
  Widget _signaturePill(Color color, double height) {
    return Builder(
      builder: (btnCtx) => _pillShell(
        color: color,
        height: height,
        onTap: () => _showSignatureMenu(btnCtx, color),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _signatureLabel,
                  style: AppType.digits(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppInk.strong,
                  ),
                ),
                Icon(Icons.arrow_drop_down_rounded, size: 18, color: color),
              ],
            ),
            const Text(
              '拍號',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: AppInk.soft,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 細分彈出鈕：顯示目前細分的音符圖示，點開氣泡選。
  Widget _subdivisionPill(Color color, double height) {
    return Builder(
      builder: (btnCtx) => _pillShell(
        color: color,
        height: height,
        onTap: () => _showSubdivisionMenu(btnCtx, color),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SubdivisionGlyph(
                  option: _currentSub,
                  color: AppInk.strong,
                  height: 17,
                ),
                Icon(Icons.arrow_drop_down_rounded, size: 18, color: color),
              ],
            ),
            const Text(
              '細分',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: AppInk.soft,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pillShell({
    required Color color,
    required double height,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          // FittedBox：窄機時整體縮放，絕不橫向溢出（修 RenderFlex overflow）
          child: FittedBox(fit: BoxFit.scaleDown, child: child),
        ),
      ),
    );
  }

  // 從鈕位置彈出選單；底部空間不足時 showMenu 會自動往上長。
  RelativeRect _anchorRect(BuildContext anchor) {
    final box = anchor.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    return RelativeRect.fromLTRB(
      topLeft.dx,
      topLeft.dy,
      overlay.size.width - topLeft.dx - box.size.width,
      overlay.size.height - topLeft.dy - box.size.height,
    );
  }

  Future<void> _showSignatureMenu(BuildContext anchor, Color color) async {
    playFeedback(SfxCue.tap);
    await showMenu<void>(
      context: context,
      position: _anchorRect(anchor),
      color: const Color(0xFFFFFDF9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: SizedBox(
            width: 240,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final p in _signaturePresets)
                    _menuRow(
                      color: color,
                      selected: p.beats == _beats && p.unit == _beatUnit,
                      onTap: () => _setTimeSignature(p.beats, p.unit),
                      leading: SizedBox(
                        width: 44,
                        child: Text(
                          p.label,
                          style: AppType.digits(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: AppInk.strong,
                          ),
                        ),
                      ),
                      label: p.hint,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showSubdivisionMenu(BuildContext anchor, Color color) async {
    playFeedback(SfxCue.tap);
    await showMenu<void>(
      context: context,
      position: _anchorRect(anchor),
      color: const Color(0xFFFFFDF9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: SizedBox(
            width: 240,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final o in _subOptions)
                    _menuRow(
                      color: color,
                      selected: o.parts == _subParts,
                      onTap: () => _setSubdivision(o.parts),
                      leading: SizedBox(
                        width: 46,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _SubdivisionGlyph(
                            option: o,
                            color: AppInk.strong,
                            height: 18,
                          ),
                        ),
                      ),
                      label: o.label,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 彈出選單的整列選項：左側主元素（拍號數字／細分音符）＋右側說明＋選中打勾。
  // 整列填滿選單寬度 → 短標籤不留大空白、長標籤不被截斷。
  Widget _menuRow({
    required Color color,
    required bool selected,
    required VoidCallback onTap,
    required Widget leading,
    String? label,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? color.withValues(alpha: 0.14)
            : const Color(0xFFFAF7F2),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.pop(context);
            onTap();
          },
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                leading,
                if (label != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: selected ? color : AppInk.soft,
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
                if (selected) Icon(Icons.check_rounded, size: 16, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 設定底板：參考超慢跑設定頁（圓角卡 + 區塊標題 + 完成鈕固定底部）──
  void _openSettings(Color color) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void apply(VoidCallback change) {
            change();
            setSheet(() {});
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.86,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.18),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: SingleChildScrollView(
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
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: Icon(
                                    Icons.av_timer_rounded,
                                    color: color,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '節拍器設定',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                          color: AppInk.strong,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        '音色、音量與跟拍方式',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: AppInk.soft,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: AppInk.iconFaint,
                                  ),
                                  onPressed: () => Navigator.pop(ctx),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _sheetSectionTitle(
                              Icons.graphic_eq_rounded,
                              color,
                              '音色（點一下試聽）',
                            ),
                            const SizedBox(height: 8),
                            LayoutBuilder(
                              builder: (context, c) {
                                final tileW = ((c.maxWidth - 8) / 2).clamp(
                                  118.0,
                                  180.0,
                                );
                                return Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final t in MetronomeTone.values)
                                      _sheetToneTile(
                                        color,
                                        tileW,
                                        t,
                                        _tone == t,
                                        () => apply(() => _setTone(t)),
                                      ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 18),
                            _sheetSectionTitle(
                              Icons.volume_up_rounded,
                              color,
                              '音量',
                            ),
                            _sheetVolumeRow(
                              color,
                              (v) => apply(() => _setVolume(v)),
                            ),
                            const SizedBox(height: 14),
                            _sheetSectionTitle(Icons.tune_rounded, color, '跟拍'),
                            const SizedBox(height: 8),
                            _sheetSwitchTile(
                              Icons.line_weight_rounded,
                              color,
                              '第一拍重音',
                              _beatUnit == 8 && _beats >= 6 && _beats % 3 == 0
                                  ? '小節開頭加重，複合拍補分組重音'
                                  : '小節開頭加重，方便抓拍',
                              _accent,
                              (v) => apply(() => _setAccent(v)),
                            ),
                            const SizedBox(height: 8),
                            _sheetSwitchTile(
                              Icons.vibration_rounded,
                              color,
                              '觸覺跟拍',
                              '靜音時用震動跟拍',
                              _haptic,
                              (v) => apply(() => _setHaptic(v)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.check_rounded, size: 19),
                        label: const Text(
                          '完成',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _toneIcon(MetronomeTone t) => switch (t) {
    MetronomeTone.wood => Icons.forest_rounded,
    MetronomeTone.kick => Icons.radio_button_checked_rounded,
    MetronomeTone.lowWood => Icons.spa_rounded,
    MetronomeTone.bell => Icons.notifications_none_rounded,
  };

  Widget _sheetSectionTitle(IconData icon, Color color, String title) {
    return Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: AppInk.strong,
          ),
        ),
      ],
    );
  }

  Widget _sheetToneTile(
    Color color,
    double width,
    MetronomeTone tone,
    bool selected,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.12)
                : const Color(0xFFFAF7F2),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.38)
                  : const Color(0xFFE8DDD4),
            ),
          ),
          child: Row(
            children: [
              Icon(
                _toneIcon(tone),
                size: 17,
                color: selected ? color : AppInk.soft,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  tone.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? color : AppInk.strong,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (selected) Icon(Icons.check_rounded, size: 16, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetVolumeRow(Color color, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Row(
        children: [
          Icon(Icons.volume_down_rounded, size: 18, color: color),
          Expanded(
            child: Slider(
              value: _volume.clamp(0.0, 1.0),
              divisions: 20,
              activeColor: color,
              inactiveColor: color.withValues(alpha: 0.16),
              onChanged: onChanged,
              onChangeEnd: (v) {
                _persist();
                MetronomeService.instance.play(
                  volume: _previewVolume,
                  tone: _tone,
                );
              },
            ),
          ),
          SizedBox(
            width: 46,
            child: Text(
              '${(_volume * 100).round()}%',
              textAlign: TextAlign.right,
              style: AppType.digits(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppInk.soft,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sheetSwitchTile(
    IconData icon,
    Color color,
    String label,
    String sub,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Material(
      color: const Color(0xFFFFFCF8),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          playHaptic(HapticLevel.selection);
          onChanged(!value);
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x0A46342B)),
            boxShadow: AppShadows.flat,
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: (value ? color : AppInk.faint).withValues(
                    alpha: value ? 0.12 : 0.10,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: value ? color : AppInk.faint,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        color: AppInk.strong,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppInk.soft,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: value,
                activeTrackColor: color,
                onChanged: (v) {
                  playHaptic(HapticLevel.selection);
                  onChanged(v);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 拍點：當前拍亮起；重音拍（小節第一拍）平時就用實心外圈標出。
class _Dot extends StatelessWidget {
  final bool active;
  final bool accent;
  final Color color;
  const _Dot({required this.active, required this.accent, required this.color});

  @override
  Widget build(BuildContext context) {
    final size = accent ? 16.0 : 12.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active
            ? color
            : (accent
                  ? color.withValues(alpha: 0.30)
                  : color.withValues(alpha: 0.14)),
        border: accent
            ? Border.all(color: color.withValues(alpha: 0.6), width: 1.5)
            : null,
        boxShadow: active
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}

// 細分拍音符圖示：依「幾顆音符 + 幾條符尾橫桿 + 連音數字」自繪，
// 不依賴音樂字型、跨語言通用（呼應多語言發行目標）。
class _SubdivisionGlyph extends StatelessWidget {
  final _SubOption option;
  final Color color;
  final double height;
  const _SubdivisionGlyph({
    required this.option,
    required this.color,
    this.height = 22,
  });

  @override
  Widget build(BuildContext context) {
    // 寬高比隨音符數增加，避免六連（6 顆）擠在一起看不清。
    final aspect = option.notes >= 5
        ? 2.7
        : option.notes >= 3
        ? 2.0
        : 1.5;
    return CustomPaint(
      size: Size(height * aspect, height),
      painter: _SubdivisionGlyphPainter(
        notes: option.notes,
        beams: option.beams,
        tuplet: option.tuplet,
        dotted: option.dotted,
        color: color,
      ),
    );
  }
}

class _SubdivisionGlyphPainter extends CustomPainter {
  final int notes; // 音符顆數
  final int beams; // 符尾橫桿數
  final int tuplet; // 連音數字（0=不標）
  final bool dotted; // 附點（複合拍「不細分」= 附點四分）
  final Color color;
  const _SubdivisionGlyphPainter({
    required this.notes,
    required this.beams,
    required this.tuplet,
    required this.dotted,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = Paint()..color = color;

    final headRx = (w * 0.08).clamp(2.0, 4.0).toDouble();
    final headRy = headRx * 0.8;
    final baseY = h * 0.72;
    final beamTop = h * (tuplet > 0 ? 0.30 : 0.22);

    final n = notes;
    final leftPad = w * 0.18;
    final span = w - leftPad * 2;
    double headX(int i) => n == 1 ? w * 0.42 : leftPad + span * (i / (n - 1));
    double stemX(int i) => headX(i) + headRx * 0.82;

    // 符頭（實心橢圓）
    for (var i = 0; i < n; i++) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(headX(i), baseY),
          width: headRx * 2,
          height: headRy * 2,
        ),
        fill,
      );
    }
    // 附點（複合拍「不細分」= 附點四分音符）
    if (dotted) {
      final dotR = headRx * 0.45;
      canvas.drawCircle(
        Offset(headX(0) + headRx + dotR * 2.0, baseY),
        dotR,
        fill,
      );
    }
    // 符桿
    final stem = Paint()
      ..color = color
      ..strokeWidth = (w * 0.03).clamp(1.2, 2.0).toDouble()
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < n; i++) {
      canvas.drawLine(
        Offset(stemX(i), baseY - headRy * 0.3),
        Offset(stemX(i), beamTop),
        stem,
      );
    }
    // 符尾橫桿（八分=1、十六分/六連=2）
    if (beams > 0 && n >= 2) {
      final bw = (h * 0.08).clamp(1.6, 3.2).toDouble();
      final beam = Paint()
        ..color = color
        ..strokeWidth = bw
        ..strokeCap = StrokeCap.round;
      for (var b = 0; b < beams; b++) {
        final by = beamTop + b * bw * 1.7;
        canvas.drawLine(Offset(stemX(0), by), Offset(stemX(n - 1), by), beam);
      }
    }
    // 連音數字（3 連、6 連）
    if (tuplet > 0) {
      final tp = TextPainter(
        text: TextSpan(
          text: '$tuplet',
          style: TextStyle(
            color: color,
            fontSize: h * 0.30,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final cx = (stemX(0) + stemX(n - 1)) / 2;
      tp.paint(canvas, Offset(cx - tp.width / 2, beamTop - tp.height - h * 0.02));
    }
  }

  @override
  bool shouldRepaint(_SubdivisionGlyphPainter old) =>
      old.notes != notes ||
      old.beams != beams ||
      old.tuplet != tuplet ||
      old.dotted != dotted ||
      old.color != color;
}

// 古典節拍器：梯形案體 + 支點在底部、往上的漸縮擺桿 + 配重塊 + 頂端球，
// 隨拍左右擺。數字另放在旁，不再疊在擺錘上。
class _MetronomePainter extends CustomPainter {
  final double angle;
  final Color color;
  const _MetronomePainter({required this.angle, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final stroke = math.max(1.6, w * 0.014);

    final bottomY = h * 0.93, topY = h * 0.13;
    final bHalf = w * 0.34, tHalf = w * 0.145;
    final pivot = Offset(cx, h * 0.795);
    final rodLen = h * 0.60;
    final dir = Offset(math.sin(angle), -math.cos(angle));
    final perp = Offset(math.cos(angle), math.sin(angle));
    final tip = pivot + dir * rodLen;

    // 1) 地面柔影（棕色非純黑，依插畫慣例）
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, bottomY + h * 0.035),
        width: w * 0.62,
        height: h * 0.055,
      ),
      Paint()
        ..color = const Color(0xFF6B4F3F).withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // 2) 案體（圓角梯形）+ 垂直漸層
    final body = _roundedPoly([
      Offset(cx - bHalf, bottomY),
      Offset(cx + bHalf, bottomY),
      Offset(cx + tHalf, topY),
      Offset(cx - tHalf, topY),
    ], w * 0.055);
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.10),
            color.withValues(alpha: 0.24),
          ],
        ).createShader(Rect.fromLTRB(cx - bHalf, topY, cx + bHalf, bottomY)),
    );
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: 0.5),
    );

    // 3) 內窗（白凹槽，襯托擺桿）+ 刻度
    final winTop = topY + h * 0.055, winBottom = bottomY - h * 0.085;
    final window = _roundedPoly([
      Offset(cx - bHalf * 0.5, winBottom),
      Offset(cx + bHalf * 0.5, winBottom),
      Offset(cx + tHalf * 0.62, winTop),
      Offset(cx - tHalf * 0.62, winTop),
    ], w * 0.03);
    canvas.drawPath(
      window,
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );
    canvas.drawPath(
      window,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: 0.18),
    );
    canvas.drawLine(
      Offset(cx, winTop + 4),
      Offset(cx, winBottom - 4),
      Paint()
        ..color = color.withValues(alpha: 0.16)
        ..strokeWidth = math.max(1.0, w * 0.005),
    );
    for (var i = 1; i <= 4; i++) {
      final ty = winTop + (winBottom - winTop) * (i / 5);
      canvas.drawLine(
        Offset(cx - w * 0.028, ty),
        Offset(cx + w * 0.028, ty),
        Paint()
          ..color = color.withValues(alpha: 0.14)
          ..strokeWidth = 1.3,
      );
    }

    // 4) 擺動弧（顯示路徑）
    canvas.drawArc(
      Rect.fromCircle(center: pivot, radius: rodLen),
      -math.pi / 2 - _pendMaxAngle,
      _pendMaxAngle * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, w * 0.008)
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.16),
    );

    // 5) 擺桿（漸縮）+ 一側高光
    final baseHalf = w * 0.017, tipHalf = w * 0.008;
    final rod = Path()
      ..moveTo(pivot.dx + perp.dx * baseHalf, pivot.dy + perp.dy * baseHalf)
      ..lineTo(tip.dx + perp.dx * tipHalf, tip.dy + perp.dy * tipHalf)
      ..lineTo(tip.dx - perp.dx * tipHalf, tip.dy - perp.dy * tipHalf)
      ..lineTo(pivot.dx - perp.dx * baseHalf, pivot.dy - perp.dy * baseHalf)
      ..close();
    canvas.drawPath(rod, Paint()..color = color);
    canvas.drawLine(
      pivot - perp * (baseHalf * 0.35),
      tip - perp * (tipHalf * 0.35),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..strokeWidth = math.max(1.0, w * 0.005)
        ..strokeCap = StrokeCap.round,
    );

    // 6) 配重（梯形塊，隨桿旋轉）+ 高光
    final wt = pivot + dir * (rodLen * 0.40);
    canvas.save();
    canvas.translate(wt.dx, wt.dy);
    canvas.rotate(angle);
    final ww = w * 0.17, wwTop = w * 0.135, wh = h * 0.078;
    final weight = _roundedPoly([
      Offset(-ww / 2, wh / 2),
      Offset(ww / 2, wh / 2),
      Offset(wwTop / 2, -wh / 2),
      Offset(-wwTop / 2, -wh / 2),
    ], w * 0.02);
    canvas.drawPath(weight, Paint()..color = color);
    canvas.drawPath(
      weight,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = Colors.white.withValues(alpha: 0.55),
    );
    canvas.restore();

    // 7) 頂端球（柔光 + 實心 + 白點高光）
    canvas.drawCircle(
      tip,
      w * 0.062,
      Paint()
        ..color = color.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(tip, w * 0.044, Paint()..color = color);
    canvas.drawCircle(
      tip - Offset(w * 0.013, w * 0.013),
      w * 0.014,
      Paint()..color = Colors.white.withValues(alpha: 0.6),
    );

    // 8) 支點螺絲
    final pr = math.max(2.6, w * 0.028);
    canvas.drawCircle(pivot, pr, Paint()..color = Colors.white);
    canvas.drawCircle(
      pivot,
      pr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = color.withValues(alpha: 0.7),
    );
    canvas.drawCircle(
      pivot,
      pr * 0.4,
      Paint()..color = color.withValues(alpha: 0.5),
    );
  }

  // 圓角多邊形：每個轉角用二次貝茲收圓。
  Path _roundedPoly(List<Offset> pts, double r) {
    final path = Path();
    final n = pts.length;
    for (var i = 0; i < n; i++) {
      final prev = pts[(i - 1 + n) % n];
      final cur = pts[i];
      final next = pts[(i + 1) % n];
      final v1 = prev - cur, v2 = next - cur;
      final l1 = v1.distance, l2 = v2.distance;
      final r1 = math.min(r, l1 / 2), r2 = math.min(r, l2 / 2);
      final p1 = cur + v1 * (r1 / l1);
      final p2 = cur + v2 * (r2 / l2);
      if (i == 0) {
        path.moveTo(p1.dx, p1.dy);
      } else {
        path.lineTo(p1.dx, p1.dy);
      }
      path.quadraticBezierTo(cur.dx, cur.dy, p2.dx, p2.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_MetronomePainter old) =>
      old.angle != angle || old.color != color;
}
