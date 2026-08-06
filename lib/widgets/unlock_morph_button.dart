// 衣櫃／音樂盒的小動作鈕，以及購買成功時的「解鎖」演出。
//
// 原本尚未購買的曲目用 `Icons.lock_open_rounded`——那是**打開的鎖**，語意剛好
// 相反；而且購買成功是瞬間換圖（鎖 → 加入），使用者按下「解鎖」之後畫面上沒有
// 任何「東西被打開了」的過程。
//
// 這裡把它拉成一條有先後的弧線，節奏沿用 `docs/visual_spec.md` §動效的
// anticipation → impact → recovery：
//
//   蓄力(130ms) → 掙脫般搖晃(350ms) → **彈開**(音效＋觸覺＋光圈) → 落定(220ms)
//   → 化成「加入」(300ms)
//
// **衝擊點對齊看得到的那一幀**（鎖真的彈開的瞬間），不是購買完成的那一刻——
// 所以音效由這個元件在 impact 播，`_buyTrack` 不再自己播，否則會提早半秒。
//
// Reduce Motion 走同一條語意但省略位移與縮放：鎖仍然從闔著換成打開再換成加入，
// 音效與觸覺照樣觸發，只是不搖、不縮放、不放光圈（見 engineering_guardrails
// §兔咪素材與演出的 Reduce Motion 條）。

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

// ── 解鎖演出的時間軸（總長 1000ms）─────────────────────────
//
// 這些是**唯一**的真相來源；測試 import 它們，不要在別處另寫一組數字。

/// 蓄力：鎖繃緊、微微縮小。
const Duration kUnlockAnticipate = Duration(milliseconds: 130);

/// 掙脫般的左右搖晃（振幅遞減）。
const Duration kUnlockShake = Duration(milliseconds: 350);

/// 彈開後的落定（縮放 overshoot 收回）。
const Duration kUnlockSettle = Duration(milliseconds: 220);

/// 化成「加入」圖示的交叉淡入。
const Duration kUnlockMorph = Duration(milliseconds: 300);

/// 完整演出長度。
const Duration kUnlockTotal = Duration(milliseconds: 1000);

/// Reduce Motion 版：只保留語意上的三段換圖，不做位移與縮放。
const Duration kUnlockTotalReduced = Duration(milliseconds: 320);

/// 鎖彈開（＝衝擊點）在整條弧線上的位置。
const double kUnlockImpactAt = 0.48;

/// 搖晃的最大角度（弧度）。約 7°，再大就從「掙脫」變成「壞掉」。
const double _kShakeMaxAngle = 0.12;

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

  /// 這一輪演出是否已經播過衝擊音（避免 rebuild 重播）。
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
      _impactFired = false;
      _ctrl.duration = _reduceMotion ? kUnlockTotalReduced : kUnlockTotal;
      _ctrl.forward(from: 0);
    } else if (old.owned && !widget.owned) {
      _ctrl.value = 0;
      _impactFired = false;
    }
  }

  void _maybeFireImpact() {
    if (_impactFired) return;
    final at = _reduceMotion ? 0.0 : kUnlockImpactAt;
    if (_ctrl.value < at) return;
    _impactFired = true;
    // 鎖真的彈開的這一幀才給聲音與觸覺；購買完成的那一刻刻意不給。
    playFeedback(SfxCue.unlock);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 蓄力＋落定合成的縮放。
  double _scaleAt(double t) {
    const anticipateEnd = 0.13;
    const settleEnd = 0.70;
    if (t <= anticipateEnd) {
      // 1.0 → 0.90，繃緊
      return 1 - 0.10 * Curves.easeOut.transform(t / anticipateEnd);
    }
    if (t < kUnlockImpactAt) return 0.90; // 搖晃期間維持繃緊
    if (t < settleEnd) {
      // 0.90 → 1.14 → 1.0：彈開的 overshoot
      final p = (t - kUnlockImpactAt) / (settleEnd - kUnlockImpactAt);
      return p < 0.35
          ? 0.90 + 0.24 * Curves.easeOutBack.transform(p / 0.35)
          : 1.14 - 0.14 * Curves.easeOutCubic.transform((p - 0.35) / 0.65);
    }
    return 1;
  }

  /// 掙脫般的搖晃：四次來回，振幅遞減。
  double _shakeAngleAt(double t) {
    const start = 0.13;
    if (t < start || t >= kUnlockImpactAt) return 0;
    final p = (t - start) / (kUnlockImpactAt - start);
    // 遞減包絡：一開始最用力，快掙脫時反而穩下來
    final decay = 1 - Curves.easeInCubic.transform(p) * 0.72;
    return math.sin(p * math.pi * 8) * _kShakeMaxAngle * decay;
  }

  /// 彈開瞬間的光圈：從鎖身擴散出去後淡掉。
  double _pulseAt(double t) {
    const span = 0.26;
    if (t < kUnlockImpactAt || t > kUnlockImpactAt + span) return 0;
    return (t - kUnlockImpactAt) / span;
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
        final morphed = reduce
            ? t
            : ((t - 0.70) / 0.30).clamp(0.0, 1.0).toDouble();
        final opened = reduce
            ? (t >= 0.5 ? 1.0 : 0.0)
            : (t >= kUnlockImpactAt ? 1.0 : 0.0);

        return MiniActionButton(
          label: widget.unlockedLabel,
          icon: widget.unlockedIcon,
          color: widget.color,
          onTap: widget.onUnlockedTap,
          // Reduce Motion 只留交叉淡入：**完全不建** Transform 與光圈，
          // 而不是建了再傳 0——後者等於偏好沒有真的生效。
          iconWidget: reduce
              ? SizedBox(
                  width: 17,
                  height: 17,
                  child: _iconStack(opened, morphed),
                )
              : SizedBox(
                  width: 17,
                  height: 17,
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      _pulseRing(_pulseAt(t)),
                      Transform.rotate(
                        angle: _shakeAngleAt(t),
                        child: Transform.scale(
                          scale: _scaleAt(t),
                          child: _iconStack(opened, morphed),
                        ),
                      ),
                    ],
                  ),
                ),
          labelWidget: _label(morphed),
        );
      },
    );
  }

  /// 鎖（闔）→ 鎖（開）→ 目標圖示，三張疊著各自淡入淡出。
  Widget _iconStack(double opened, double morphed) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: (1 - opened).clamp(0.0, 1.0),
          child: Icon(Icons.lock_rounded, size: 17, color: widget.color),
        ),
        Opacity(
          opacity: (opened * (1 - morphed)).clamp(0.0, 1.0),
          child: Icon(Icons.lock_open_rounded, size: 17, color: widget.color),
        ),
        Opacity(
          opacity: morphed.clamp(0.0, 1.0),
          child: Icon(widget.unlockedIcon, size: 17, color: widget.color),
        ),
      ],
    );
  }

  Widget _pulseRing(double p) {
    if (p <= 0) return const SizedBox.shrink();
    return Opacity(
      opacity: (1 - p) * 0.55,
      child: Transform.scale(
        scale: 1 + p * 1.9,
        child: Container(
          width: 17,
          height: 17,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: widget.color, width: 1.4),
          ),
        ),
      ),
    );
  }

  Widget _label(double morphed) {
    final style = TextStyle(
      color: widget.color,
      fontSize: 12.5,
      fontWeight: FontWeight.w900,
    );
    // 兩個標籤疊著換，寬度取較寬的那個，換的過程不推擠版面。
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: 1 - morphed,
          child: Text(widget.lockedLabel, style: style),
        ),
        Opacity(
          opacity: morphed,
          child: Text(widget.unlockedLabel, style: style),
        ),
      ],
    );
  }
}
