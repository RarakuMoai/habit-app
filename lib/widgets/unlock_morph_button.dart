// 衣櫃／音樂盒的小動作鈕，以及購買成功時的「解鎖」演出。
//
// 原本尚未購買的曲目用 `Icons.lock_open_rounded`——那是**打開的鎖**，語意剛好
// 相反；而且購買成功是瞬間換圖（鎖 → 加入），使用者按下「解鎖」之後畫面上沒有
// 任何「東西被打開了」的過程。
//
// 這裡把它拉成一條有先後的弧線，節奏沿用 `docs/visual_spec.md` §動效的
// anticipation → impact → recovery：
//
//   蓄力(180ms) → 掙脫般搖晃(720ms，伴隨搖晃音) → **彈開**(解鎖音＋觸覺＋光爆)
//   → 光影餘韻與落定(400ms) → 化成「加入」(680ms，其中淡入約 500ms)。總長 1980ms。
//
// **衝擊點對齊看得到的那一幀**（鎖真的彈開的瞬間），不是購買完成的那一刻——
// 所以音效由這個元件在 impact 播，`_buyTrack` 不再自己播，否則會提早半秒。
//
// 圖示是**接力**不是交叉淡入：鎖與「加入」形狀差太多，兩張半透明疊在一起會讀成
// 「圖案缺一塊」。所以鎖先縮走消失，目標圖示才從小長回來，中間沒有重疊區。
//
// Reduce Motion 走同一條語意但省略位移與縮放：鎖仍然從闔著換成打開再換成加入，
// 解鎖音與觸覺照樣觸發（那是事實回饋），只是不搖、不縮放、不放光效——搖晃音也
// 一併省略，因為那一聲是在描述一個不會發生的動作。

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/sfx_service.dart';

/// 衣櫃／音樂盒列上的小動作鈕（原 `_PrimaryMiniButton`）。
///
/// [iconWidget] / [labelWidget] 給需要自己做動畫的呼叫端覆寫用；
/// 一般情況只傳 [icon] 與 [label] 就好。
class MiniActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  /// 覆寫圖示區（[UnlockMorphButton] 用來塞會動的鎖）。
  final Widget? iconWidget;

  /// 覆寫文字區（同上，用來做標籤交叉淡入）。
  final Widget? labelWidget;

  const MiniActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.enabled = true,
    this.iconWidget,
    this.labelWidget,
  });

  @override
  Widget build(BuildContext context) {
    final fg = enabled ? color : AppInk.faint;
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
                iconWidget ?? Icon(icon, size: 17, color: fg),
                const SizedBox(width: 5),
                labelWidget ??
                    Text(
                      label,
                      style: TextStyle(
                        color: fg,
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

// ── 解鎖演出的時間軸（總長 1980ms）─────────────────────────
//
// 這些是**唯一**的真相來源；測試 import 它們，不要在別處另寫一組數字。
//
// 為什麼這麼慢：第一版 1000ms 跑完，實機看起來像「閃一下就結束」。精緻感需要
// 時間——尤其掙脫（要讀得出「它在用力」）與彈開之後的餘韻（成就感發生在那裡）。

/// 蓄力：鎖繃緊、微微縮小。
const Duration kUnlockAnticipate = Duration(milliseconds: 180);

/// 掙脫般的左右搖晃（振幅先漲後收），起點伴隨搖晃音。
const Duration kUnlockShake = Duration(milliseconds: 720);

/// 彈開後的光影展開與落定——成就感在這一段，不能太短。
const Duration kUnlockSettle = Duration(milliseconds: 400);

/// 化成「加入」圖示。**接力不重疊**：鎖先縮走，圖示才長出來。
const Duration kUnlockMorph = Duration(milliseconds: 680);

/// 完整演出長度。
const Duration kUnlockTotal = Duration(milliseconds: 1980);

/// Reduce Motion 版：只保留語意上的三段換圖，不做位移與縮放。
const Duration kUnlockTotalReduced = Duration(milliseconds: 420);

/// 搖晃開始（＝搖晃音的觸發點）在整條弧線上的位置。
const double kUnlockShakeAt = 180 / 1980;

/// 鎖彈開（＝衝擊點）在整條弧線上的位置。
const double kUnlockImpactAt = 900 / 1980;

/// 開始化成「加入」的位置。
const double kUnlockMorphAt = 1300 / 1980;

/// 搖晃的最大角度（弧度）。約 9°，再大就從「掙脫」變成「壞掉」。
const double _kShakeMaxAngle = 0.16;

/// 「尚未擁有 → 已擁有」時播一段解鎖演出的動作鈕。
///
/// 真相仍在外部（[owned] 由 store 的 ValueNotifier 驅動）；這個元件只負責在
/// [owned] 由 false 翻成 true 的那一刻把過程演出來，不持有任何購買狀態。
class UnlockMorphButton extends StatefulWidget {
  /// 外部真相：是否已擁有。false → true 會觸發演出。
  final bool owned;

  /// 未擁有時的標籤（例：「解鎖 30」）。
  final String lockedLabel;

  /// 已擁有時的標籤（例：「加入」）。
  final String unlockedLabel;

  /// 已擁有時的圖示（例：`Icons.playlist_add_rounded`）。
  final IconData unlockedIcon;

  final Color color;

  /// 未擁有時點下去（開購買確認）。
  final VoidCallback onLockedTap;

  /// 已擁有時點下去（加入清單）。
  final VoidCallback onUnlockedTap;

  const UnlockMorphButton({
    super.key,
    required this.owned,
    required this.lockedLabel,
    required this.unlockedLabel,
    required this.unlockedIcon,
    required this.color,
    required this.onLockedTap,
    required this.onUnlockedTap,
  });

  @override
  State<UnlockMorphButton> createState() => _UnlockMorphButtonState();
}

class _UnlockMorphButtonState extends State<UnlockMorphButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  /// 這一輪演出是否已經播過搖晃音／衝擊音（避免 rebuild 重播）。
  bool _shakeFired = false;
  bool _impactFired = false;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: kUnlockTotal)
      ..addListener(_maybeFireImpact)
      // 演完就把動畫樹收掉，回到零成本的靜態鈕：否則三張疊圖（含 opacity 0
      // 的鎖）會一直留在樹上，既浪費也讓「鎖不見了」變成假的。
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) setState(() {});
      });
  }

  @override
  void didUpdateWidget(covariant UnlockMorphButton old) {
    super.didUpdateWidget(old);
    // 只有「沒有 → 有」才演。反向（例如資料重載）直接落到已擁有的樣子。
    if (!old.owned && widget.owned) {
      _shakeFired = _impactFired = false;
      _ctrl.duration = _reduceMotion ? kUnlockTotalReduced : kUnlockTotal;
      _ctrl.forward(from: 0);
    } else if (old.owned && !widget.owned) {
      _ctrl.value = 0;
      _shakeFired = _impactFired = false;
    }
  }

  void _maybeFireImpact() {
    final t = _ctrl.value;
    // 搖晃音：跟著鎖開始掙扎的那一刻起。Reduce Motion 沒有搖晃，就不放這一聲。
    if (!_shakeFired && !_reduceMotion && t >= kUnlockShakeAt) {
      _shakeFired = true;
      // ⚠️ 佔位音效：這是「集氣」不是「鎖在掙脫」。專用音效待補，
      //    見 docs/pending_assets.md。觸覺刻意不給——衝擊點才給。
      playFeedback(SfxCue.tumiCharge, haptic: HapticLevel.none);
    }
    if (_impactFired) return;
    if (t < (_reduceMotion ? 0.0 : kUnlockImpactAt)) return;
    _impactFired = true;
    // 鎖真的彈開的這一幀才給聲音與觸覺；購買完成的那一刻刻意不給。
    playFeedback(SfxCue.unlock);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 蓄力（繃緊）→ 彈開（overshoot）→ 落定。
  double _scaleAt(double t) {
    if (t <= kUnlockShakeAt) {
      // 1.0 → 0.88，繃緊
      return 1 - 0.12 * Curves.easeOut.transform(t / kUnlockShakeAt);
    }
    if (t < kUnlockImpactAt) {
      // 搖晃期間維持繃緊；最後一小段再多壓一點，讀成「就要撐不住了」
      final p = (t - kUnlockShakeAt) / (kUnlockImpactAt - kUnlockShakeAt);
      return p < 0.86 ? 0.88 : 0.88 - 0.04 * ((p - 0.86) / 0.14);
    }
    if (t < kUnlockMorphAt) {
      // 0.84 → 1.22 → 1.0：彈開的 overshoot，慢慢收回才有餘韻
      final p = (t - kUnlockImpactAt) / (kUnlockMorphAt - kUnlockImpactAt);
      return p < 0.30
          ? 0.84 + 0.38 * Curves.easeOutBack.transform(p / 0.30)
          : 1.22 - 0.22 * Curves.easeOutCubic.transform((p - 0.30) / 0.70);
    }
    return 1;
  }

  /// 掙脫般的搖晃：振幅先漲、中段最用力、彈開前一瞬間**靜止**。
  ///
  /// 那個靜止是刻意的——沒有它，彈開就只是搖晃的延續，讀不出「掙脫成功」。
  double _shakeAngleAt(double t) {
    if (t < kUnlockShakeAt || t >= kUnlockImpactAt) return 0;
    final p = (t - kUnlockShakeAt) / (kUnlockImpactAt - kUnlockShakeAt);
    final double envelope;
    if (p < 0.18) {
      envelope = Curves.easeOut.transform(p / 0.18); // 漲起來
    } else if (p < 0.86) {
      envelope = 1; // 全力掙扎
    } else {
      envelope = 1 - Curves.easeInCubic.transform((p - 0.86) / 0.14); // 屏住
    }
    // 實拍回饋：13 個半週期在 720ms 內太急躁，讀成「抖」不是「掙脫」。減半。
    return math.sin(p * math.pi * 6.5) * _kShakeMaxAngle * envelope;
  }

  /// 搖晃的橫向位移（px）。
  ///
  /// **實拍發現：17px 的圖示上，±9° 旋轉只有約 1.3px 的邊緣位移，肉眼完全讀不到。**
  /// 小尺寸要讓「掙扎」讀得出來，靠的是位移不是旋轉。兩者同相疊加。
  double _shakeDxAt(double t) {
    if (t < kUnlockShakeAt || t >= kUnlockImpactAt) return 0;
    final p = (t - kUnlockShakeAt) / (kUnlockImpactAt - kUnlockShakeAt);
    final double envelope;
    if (p < 0.18) {
      envelope = Curves.easeOut.transform(p / 0.18);
    } else if (p < 0.86) {
      envelope = 1;
    } else {
      envelope = 1 - Curves.easeInCubic.transform((p - 0.86) / 0.14);
    }
    return math.sin(p * math.pi * 6.5) * 2.6 * envelope;
  }

  /// 演出期間整組放大，否則搖晃與光爆在 17px 上都讀不出來。
  /// 收尾回到 1.0，靜態時與其他按鈕一致。
  double _stageScaleAt(double t) {
    const rampIn = 0.10;
    if (t < rampIn) return 1 + 0.55 * Curves.easeOut.transform(t / rampIn);
    if (t < kUnlockImpactAt) return 1.55;
    // ⚠️ 縮放**必須在 morph 開始前收乾淨**。放在 morph 期間收的話，圖示已經
    // 換成「加入」了還在縮，看起來就是「加入圖示從左邊跑到右邊」——實機抓到的
    // 殘留位移就是這一段。收在落定段（彈開→morph）裡，那時注意力還在鎖上。
    final p = ((t - kUnlockImpactAt) / (kUnlockMorphAt - kUnlockImpactAt))
        .clamp(0.0, 1.0);
    return 1.55 - 0.55 * Curves.easeInOutCubic.transform(p);
  }

  /// 彈開瞬間的光爆進度（0→1 後結束）。
  double _burstAt(double t) {
    // 使用者：「太短，根本看不清楚就消失」。0.12(約 240ms) → 0.42(約 830ms)。
    const span = 0.42;
    if (t < kUnlockImpactAt || t > kUnlockImpactAt + span) return 0;
    return (t - kUnlockImpactAt) / span;
  }

  /// 彈開後停留的柔光暈（比光爆長，負責「成就感的餘韻」）。
  double _afterglowAt(double t) {
    // 實拍：撐到 morph 起點太久，光暈跟接下來的換手打架。收在一半。
    final end = kUnlockImpactAt + (kUnlockMorphAt - kUnlockImpactAt) * 0.55;
    if (t < kUnlockImpactAt || t > end) return 0;
    final p = (t - kUnlockImpactAt) / (end - kUnlockImpactAt);
    return p < 0.25
        ? Curves.easeOut.transform(p / 0.25)
        : 1 - Curves.easeIn.transform((p - 0.25) / 0.75);
  }

  @override
  Widget build(BuildContext context) {
    // 還沒買、或演出已經播完 → 一般的靜態鈕，零動畫成本。
    if (!widget.owned) {
      return MiniActionButton(
        label: widget.lockedLabel,
        icon: Icons.lock_rounded, // 闔上的鎖：語意要和「尚未擁有」一致
        color: widget.color,
        onTap: widget.onLockedTap,
      );
    }
    if (_ctrl.isCompleted || !_ctrl.isAnimating && _ctrl.value == 0) {
      return MiniActionButton(
        label: widget.unlockedLabel,
        icon: widget.unlockedIcon,
        color: widget.color,
        onTap: widget.onUnlockedTap,
      );
    }

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        final reduce = _reduceMotion;
        final button = MiniActionButton(
          label: widget.unlockedLabel,
          icon: widget.unlockedIcon,
          color: widget.color,
          onTap: widget.onUnlockedTap,
          // Reduce Motion 只留換圖：**完全不建** Transform 與光效，
          // 而不是建了再傳 0——後者等於偏好沒有真的生效。
          iconWidget: reduce
              ? SizedBox(width: 17, height: 17, child: _reducedIcon(t))
              : SizedBox(
                  width: 17,
                  height: 17,
                  // 演出期間整組放大：17px 放不下任何動態，實拍證明搖晃與光爆
                  // 在原尺寸下都讀不出來。收尾回到 1.0。
                  child: Transform.scale(
                    scale: _stageScaleAt(t),
                    child: Transform.translate(
                      offset: Offset(_shakeDxAt(t), 0),
                      child: Transform.rotate(
                        angle: _shakeAngleAt(t),
                        child: Transform.scale(
                          scale: _scaleAt(t),
                          child: _iconRelay(t),
                        ),
                      ),
                    ),
                  ),
                ),
          labelWidget: _label(t, reduce),
        );
        if (reduce) return button;
        // ⚠️ 光效**鋪滿整顆按鈕**，不是關在 17px 的圖示格子裡。
        //
        // 前五版都畫在圖示的 17×17 裡（放大後也才 ~26px）——在那個尺寸做
        // 「光影渲染」，實機上根本看不到。使用者連續回報「沒看到特效」，
        // 根因不是效果不好，是**層級放錯了**。高階 App 的解鎖演出，光是打在
        // 整張卡或整顆按鈕上的。
        //
        // 用 Stack 疊在按鈕之上、IgnorePointer 不吃手勢；按鈕本身完全不必知道
        // 有光效存在，兩者徹底分開。
        return Stack(
          // ⚠️ **必須 passthrough。** 預設的 StackFit.loose 會把寬度約束放鬆，
          // 按鈕就從「填滿父層給的寬度」掉回「內容有多寬就多寬」——實測框體
          // 在演出期間縮掉 40%（418px → 250px），而靜態分支沒包 Stack 所以
          // 正常，於是看起來就是「框體大小一直在變」。
          // passthrough 讓按鈕收到與 Stack 相同的約束，框體才會全程固定。
          fit: StackFit.passthrough,
          clipBehavior: Clip.none,
          children: [
            button,
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _UnlockBurstPainter(
                    progress: _burstAt(t),
                    glow: _afterglowAt(t),
                    color: widget.color,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 圖示的**接力**：同一時間只有一個圖示看得見。
  ///
  /// 第一版是三張疊著交叉淡入，結果鎖與「加入」兩個形狀不同的字形會在中途
  /// 各自半透明地疊在一起——實機看起來就是「有幾幀怪怪的、圖案缺一塊」。
  /// 改成接力之後：鎖先縮走並消失，目標圖示才從小長回來，中間沒有重疊區。
  Widget _iconRelay(double t) {
    if (t < kUnlockImpactAt) {
      return Icon(Icons.lock_rounded, size: 17, color: widget.color);
    }
    if (t < kUnlockMorphAt) {
      return Icon(Icons.lock_open_rounded, size: 17, color: widget.color);
    }
    final p = ((t - kUnlockMorphAt) / (1 - kUnlockMorphAt)).clamp(0.0, 1.0);
    if (p < 0.26) {
      // 開著的鎖縮小淡出（交棒要快，慢了就是一段沒東西看的空白）
      final q = p / 0.26;
      return Opacity(
        opacity: 1 - Curves.easeIn.transform(q),
        child: Transform.scale(
          scale: 1 - 0.35 * Curves.easeIn.transform(q),
          child: Icon(Icons.lock_open_rounded, size: 17, color: widget.color),
        ),
      );
    }
    // 目標圖示長出來（接棒）
    final q = Curves.easeOutBack.transform(((p - 0.26) / 0.74).clamp(0.0, 1.0));
    return Opacity(
      opacity: Curves.easeOut.transform(((p - 0.26) / 0.13).clamp(0.0, 1.0)),
      child: Transform.scale(
        // 彈入幅度刻意小：量過 0.62 起跳會讓圖示左緣再滑約 6px，讀成「加入
        // 出現後還在跑」。留一點點長出來的感覺就好。
        scale: 0.88 + 0.12 * q,
        child: Icon(widget.unlockedIcon, size: 17, color: widget.color),
      ),
    );
  }

  /// Reduce Motion 的換圖：不縮放不重疊，直接接力換。
  Widget _reducedIcon(double t) {
    if (t < 0.34) {
      return Icon(Icons.lock_rounded, size: 17, color: widget.color);
    }
    if (t < 0.67) {
      return Icon(Icons.lock_open_rounded, size: 17, color: widget.color);
    }
    return Icon(widget.unlockedIcon, size: 17, color: widget.color);
  }

  /// 彈開瞬間的光爆：擴散環 ＋ 放射光芒。

  TextStyle get _labelStyle => TextStyle(
    color: widget.color,
    fontSize: 12.5,
    fontWeight: FontWeight.w900,
  );

  /// 量一段文字在目前 textScaler 下的寬度。
  double _measure(String text, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler:
          MediaQuery.maybeOf(context)?.textScaler ?? TextScaler.noScaling,
    )..layout();
    return tp.width;
  }

  /// 標籤：自然寬度、內容維持置中，圖示到文字的間距固定。
  ///
  /// 三件事（圖示不動 ／ 間距固定 ／ 內容置中）數學上無法同時成立，因為兩段
  /// 文字寬度不同。前一版放掉「置中」，結果是整組偏左、看起來沒對齊；改成
  /// 放掉「圖示不動」——但把那一次位移**壓在彈開的 120ms 內完成**，那時
  /// 注意力在鎖彈開與光上，等「加入」浮出來時版面早就定住了。
  Widget _label(double t, bool reduce) {
    final p = reduce
        ? (t >= 0.67 ? 1.0 : 0.0)
        : ((t - kUnlockMorphAt) / (1 - kUnlockMorphAt)).clamp(0.0, 1.0);
    const handover = 0.26;
    final lockedOpacity = p < handover
        ? 1 - Curves.easeIn.transform(p / handover)
        : 0.0;
    // 「加入」的淡入刻意拉長：短促地跳出來讀起來像閃現，慢慢浮出來才像
    // 「東西被換上去了」。走完整個 morph 剩餘段。
    final unlockedOpacity = p < handover
        ? 0.0
        : Curves.easeOutCubic.transform((p - handover) / (1 - handover));

    // ⚠️ 寬度只能在**兩段文字都看不見的那一瞬間**改。
    //
    // 上一版排在彈開瞬間，但舊標籤要到 morph 才開始淡出——槽先縮、字還在，
    // 「解鎖 50」就被裁成「解鎖 5」「解鎖」，持續約 400ms。那是使用者說
    // 「整個亂掉」的主因。
    //
    // handover(0.26) 這一點舊標籤剛淡完、新標籤還沒進場，圖示也正在接力，
    // 三者都是空的，寬度在這裡快速換完就不會被看見。
    final wp = reduce
        ? p
        : Curves.easeInOut.transform(
            ((p - (handover - 0.06)) / 0.12).clamp(0.0, 1.0),
          );
    final w = ui.lerpDouble(
      _measure(widget.lockedLabel, _labelStyle),
      _measure(widget.unlockedLabel, _labelStyle),
      wp,
    )!;

    return SizedBox(
      width: w,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Opacity(
            opacity: lockedOpacity,
            child: Text(
              widget.lockedLabel,
              style: _labelStyle,
              softWrap: false,
              maxLines: 1,
            ),
          ),
          Opacity(
            opacity: unlockedOpacity,
            child: Text(
              widget.unlockedLabel,
              style: _labelStyle,
              softWrap: false,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// 彈開瞬間的光爆：一圈擴散環 ＋ 八道放射光芒。
///
/// 用 painter 而不是疊 widget，是因為光芒要畫到圖示框外面（17×17 之外），
/// widget 版會被父層的尺寸與 FittedBox 影響到位置。
/// 解鎖那一刻的星芒：以**鎖頭為中心**四散開來的小顆黃色星星。
///
/// 前六版都是「放射光線＋擴散環」，那是任何 App 的解鎖特效都會長成的樣子；
/// 這一版是使用者直接指定的規格，不再由我發明：
///
///   「光芒是一顆一顆的黃色星星圖案，小小顆的，從鎖頭為中心四散開來，
///    持續時間要長一點——太短根本看不清楚就消失。」
///
/// 因此：**星星是實體形狀**（五角星路徑）不是光線，顏色是暖黃不是元件主色，
/// 而且整段拉到約 830ms，讓每一顆都有被看清楚的時間。
class _UnlockBurstPainter extends CustomPainter {
  /// 星芒進度 0→1（0 是鎖彈開那一幀）。
  final double progress;

  /// 彈開之後鎖身的柔光 0→1→0。
  final double glow;

  final Color color;

  const _UnlockBurstPainter({
    required this.progress,
    required this.glow,
    required this.color,
  });

  /// 星星的暖黃。與足跡幣同一個金黃家族，不用元件主色——星星就是要跳出來。
  static const _gold = Color(0xFFFFC53D);
  static const _goldLight = Color(0xFFFFE082);

  /// 每顆星的參數：角度偏移、飛行距離倍率、大小、起跑延遲、自轉方向。
  ///
  /// 刻意手寫而不是亂數：亂數每次不一樣，沒辦法一格一格對照著調。
  static const _count = 12;
  static const _angleJitter = [
    0.0,
    0.22,
    -0.15,
    0.30,
    -0.26,
    0.10,
    -0.32,
    0.18,
    -0.08,
    0.26,
    -0.20,
    0.05,
  ];
  static const _dist = [
    1.0,
    0.72,
    0.88,
    0.60,
    1.0,
    0.78,
    0.66,
    0.94,
    0.82,
    0.58,
    1.0,
    0.70,
  ];
  static const _sizes = [
    3.4,
    2.4,
    3.0,
    2.0,
    3.6,
    2.6,
    2.2,
    3.2,
    2.8,
    2.0,
    3.4,
    2.4,
  ];
  static const _delay = [
    0.0,
    0.06,
    0.02,
    0.10,
    0.0,
    0.05,
    0.12,
    0.03,
    0.08,
    0.14,
    0.01,
    0.07,
  ];
  static const _spin = [
    1.0,
    -1.0,
    1.0,
    -1.0,
    -1.0,
    1.0,
    1.0,
    -1.0,
    -1.0,
    1.0,
    -1.0,
    1.0,
  ];

  /// 光源＝鎖頭位置（按鈕左側圖示中心），不是按鈕正中央。
  Offset _origin(Size s) => Offset(8 + 17 / 2, s.height / 2);

  /// 五角星路徑。
  Path _star(Offset c, double r, double rotation) {
    const points = 5;
    final inner = r * 0.44;
    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final rad = i.isEven ? r : inner;
      final a = rotation - math.pi / 2 + i * math.pi / points;
      final pt = c + Offset(math.cos(a) * rad, math.sin(a) * rad);
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final o = _origin(size);
    final p = progress.clamp(0.0, 1.0);

    // 鎖身留一點暖光墊底，讓星星不是憑空出現在白紙上。
    if (glow > 0) {
      canvas.drawCircle(
        o,
        14 + 10 * glow,
        Paint()
          ..color = _gold.withValues(alpha: 0.16 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    if (p <= 0) return;

    // 飛行距離：夠遠才看得出「四散」，但實拍證明 1.55× 會散到按鈕外很遠，
    // 在真實卡片裡會像碎屑撒滿整張卡。收在按鈕高度附近，讀成「鎖周圍的星光」。
    final reach = size.height * 1.05;

    for (var i = 0; i < _count; i++) {
      final lp = ((p - _delay[i]) / (1 - _delay[i])).clamp(0.0, 1.0);
      if (lp <= 0) continue;

      // 出發快、後段減速——像被彈出去然後慢下來，不是等速平移。
      final travel = Curves.easeOutCubic.transform(lp);
      // 淡出留到後段，前 55% 完全實心，才有「看清楚」的時間。
      final a = lp < 0.55 ? 1.0 : 1 - (lp - 0.55) / 0.45;
      // 快消失時微微縮小，讀成飄遠而不是被切掉。
      final scale = 1 - 0.35 * Curves.easeIn.transform(lp);

      final ang = (i / _count) * math.pi * 2 + _angleJitter[i];
      final c =
          o +
          Offset(math.cos(ang), math.sin(ang)) * (reach * _dist[i] * travel);
      final r = _sizes[i] * scale;
      if (r <= 0.2 || a <= 0.01) continue;

      final rot = _spin[i] * lp * math.pi * 0.9;
      final star = _star(c, r, rot);

      // 外圈柔光讓小星星在淺底上也有存在感
      canvas.drawPath(
        star,
        Paint()
          ..color = _goldLight.withValues(alpha: (0.55 * a).clamp(0.0, 1.0))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2),
      );
      canvas.drawPath(
        star,
        Paint()..color = _gold.withValues(alpha: (0.95 * a).clamp(0.0, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(_UnlockBurstPainter old) =>
      old.progress != progress || old.glow != glow || old.color != color;
}
