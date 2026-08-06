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
//   → 光影餘韻與落定(400ms) → 化成「加入」(600ms)。總長 1900ms。
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

// ── 解鎖演出的時間軸（總長 1900ms）─────────────────────────
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
const Duration kUnlockMorph = Duration(milliseconds: 600);

/// 完整演出長度。
const Duration kUnlockTotal = Duration(milliseconds: 1900);

/// Reduce Motion 版：只保留語意上的三段換圖，不做位移與縮放。
const Duration kUnlockTotalReduced = Duration(milliseconds: 420);

/// 搖晃開始（＝搖晃音的觸發點）在整條弧線上的位置。
const double kUnlockShakeAt = 180 / 1900;

/// 鎖彈開（＝衝擊點）在整條弧線上的位置。
const double kUnlockImpactAt = 900 / 1900;

/// 開始化成「加入」的位置。
const double kUnlockMorphAt = 1300 / 1900;

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
    return math.sin(p * math.pi * 13) * _kShakeMaxAngle * envelope;
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
    return math.sin(p * math.pi * 13) * 2.6 * envelope;
  }

  /// 演出期間整組放大，否則搖晃與光爆在 17px 上都讀不出來。
  /// 收尾回到 1.0，靜態時與其他按鈕一致。
  double _stageScaleAt(double t) {
    const rampIn = 0.10;
    if (t < rampIn) return 1 + 0.55 * Curves.easeOut.transform(t / rampIn);
    if (t < kUnlockMorphAt) return 1.55;
    final p = (t - kUnlockMorphAt) / (1 - kUnlockMorphAt);
    return 1.55 - 0.55 * Curves.easeInOutCubic.transform(p);
  }

  /// 彈開瞬間的光爆進度（0→1 後結束）。
  double _burstAt(double t) {
    const span = 0.34; // 實拍只看得到 2 幀，拉長
    if (t < kUnlockImpactAt || t > kUnlockImpactAt + span) return 0;
    return (t - kUnlockImpactAt) / span;
  }

  /// 彈開後停留的柔光暈（比光爆長，負責「成就感的餘韻」）。
  double _afterglowAt(double t) {
    if (t < kUnlockImpactAt || t > kUnlockMorphAt) return 0;
    final p = (t - kUnlockImpactAt) / (kUnlockMorphAt - kUnlockImpactAt);
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
        return MiniActionButton(
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
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        // 餘韻的柔光暈墊在最底，讓彈開之後那半秒不是空的
                        _afterglow(_afterglowAt(t)),
                        _burst(_burstAt(t)),
                        Transform.translate(
                          offset: Offset(_shakeDxAt(t), 0),
                          child: Transform.rotate(
                            angle: _shakeAngleAt(t),
                            child: Transform.scale(
                              scale: _scaleAt(t),
                              child: _iconRelay(t),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          labelWidget: _label(t, reduce),
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
    if (p < 0.45) {
      // 開著的鎖縮小淡出（交棒）
      final q = p / 0.45;
      return Opacity(
        opacity: 1 - Curves.easeIn.transform(q),
        child: Transform.scale(
          scale: 1 - 0.35 * Curves.easeIn.transform(q),
          child: Icon(Icons.lock_open_rounded, size: 17, color: widget.color),
        ),
      );
    }
    // 目標圖示長出來（接棒）
    final q = Curves.easeOutBack.transform(((p - 0.45) / 0.55).clamp(0.0, 1.0));
    return Opacity(
      opacity: Curves.easeOut.transform(((p - 0.45) / 0.35).clamp(0.0, 1.0)),
      child: Transform.scale(
        scale: 0.62 + 0.38 * q,
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
  Widget _burst(double p) {
    if (p <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        size: const Size(17, 17),
        painter: _UnlockBurstPainter(progress: p, color: widget.color),
      ),
    );
  }

  /// 彈開之後停留的柔光暈。
  Widget _afterglow(double p) {
    if (p <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: Container(
        width: 17,
        height: 17,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.42 * p),
              blurRadius: 10 + 8 * p,
              spreadRadius: 1 + 2 * p,
            ),
          ],
        ),
      ),
    );
  }

  /// 標籤同樣**接力**不交叉淡入。
  ///
  /// 實拍抓到的醜幀就在這裡：「解鎖 50」與「加入」同時半透明疊著，數字與中文
  /// 直接壓在一起，讀成「50 加」這種壞掉的字。文字比圖示更不能重疊。
  ///
  /// 兩段都留在 Stack 裡是為了**撐住寬度**（換手時按鈕不能忽寬忽窄，
  /// 外層 FittedBox 會跟著重算縮放而抖動），但任何一幀只有一段看得見。
  Widget _label(double t, bool reduce) {
    final style = TextStyle(
      color: widget.color,
      fontSize: 12.5,
      fontWeight: FontWeight.w900,
    );
    final p = reduce
        ? (t >= 0.67 ? 1.0 : 0.0)
        : ((t - kUnlockMorphAt) / (1 - kUnlockMorphAt)).clamp(0.0, 1.0);
    // 硬切點：之前只有舊標籤，之後只有新標籤。中間沒有重疊區。
    const handover = 0.42;
    final lockedOpacity = p < handover
        ? 1 - Curves.easeIn.transform(p / handover)
        : 0.0;
    final unlockedOpacity = p < handover
        ? 0.0
        : Curves.easeOut.transform((p - handover) / (1 - handover));
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: lockedOpacity,
          child: Text(widget.lockedLabel, style: style),
        ),
        Opacity(
          opacity: unlockedOpacity,
          child: Text(widget.unlockedLabel, style: style),
        ),
      ],
    );
  }
}

/// 彈開瞬間的光爆：一圈擴散環 ＋ 八道放射光芒。
///
/// 用 painter 而不是疊 widget，是因為光芒要畫到圖示框外面（17×17 之外），
/// widget 版會被父層的尺寸與 FittedBox 影響到位置。
class _UnlockBurstPainter extends CustomPainter {
  /// 0→1。0 是彈開的那一幀。
  final double progress;
  final Color color;

  const _UnlockBurstPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final p = progress.clamp(0.0, 1.0);
    final fade = 1 - Curves.easeIn.transform(p);

    // 擴散環：實拍第一版太細太大，讀起來像刮痕。收小範圍、加粗。
    final ringR = size.width * (0.46 + 0.62 * Curves.easeOutCubic.transform(p));
    canvas.drawCircle(
      c,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6 * fade + 0.4
        ..color = color.withValues(alpha: 0.75 * fade),
    );

    // 放射光芒：從鎖身邊緣往外抽，長度先長後收
    const rays = 6; // 8 道在小尺寸下糊成一團，減少但加粗
    final reach = Curves.easeOutCubic.transform(p);
    final inner = size.width * (0.38 + 0.26 * reach);
    final outer = inner + size.width * 0.34 * (1 - Curves.easeIn.transform(p));
    final rayPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.4 * fade + 0.3
      ..color = color.withValues(alpha: 0.85 * fade);
    for (var i = 0; i < rays; i++) {
      // 錯開半格，讓光芒不要正對著鎖的上下左右（那樣讀起來像十字準星）
      final a = (i + 0.5) * (math.pi * 2 / rays);
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * inner, c + d * outer, rayPaint);
    }
  }

  @override
  bool shouldRepaint(_UnlockBurstPainter old) =>
      old.progress != progress || old.color != color;
}
