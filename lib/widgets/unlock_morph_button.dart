// 衣櫃／音樂盒的小動作鈕，以及購買成功時的「解鎖」演出。
//
// 原本尚未購買的曲目用 `Icons.lock_open_rounded`——那是**打開的鎖**，語意剛好
// 相反；而且購買成功是瞬間換圖（鎖 → 加入），使用者按下「解鎖」之後畫面上沒有
// 任何「東西被打開了」的過程。
//
// 這裡把它拉成一條有先後的弧線，節奏沿用 `docs/visual_spec.md` §動效的
// anticipation → impact → recovery：
//
//   蓄力(180ms) → 掙脫般搖晃(720ms，伴隨搖晃音) → **彈開**(解鎖音＋觸覺＋星芒)
//   → 鎖一邊回彈一邊淡出(1040ms) → 換手 → 「加入」淡入(1000ms)。總長 2940ms。
//
// 淡出的起點刻意就是**彈開的那一幀**：星芒炸開的同時舊內容就開始走，不會有一段
// 「光都放完了、畫面卻還沒開始變」的空檔。
//
// **衝擊點對齊看得到的那一幀**（鎖真的彈開的瞬間），不是購買完成的那一刻——
// 所以音效由這個元件在 impact 播，`_buyTrack` 不再自己播，否則會提早半秒。
//
// ⚠️ **兩組內容各自的位置與大小全程不變，變的只有透明度。** 做法是把「未購買」與
// 「已購買」當成兩組**各自獨立排版**的內容疊在同一顆膠囊裡輪替，而不是去
// 插值一份共用的版面。理由是踩出來的：共用版面時，標籤一從「50 足跡幣」換成
// 「加入」，內容寬度就變，於是 `FittedBox` 的縮放倍率跟著變——實測 85pt 寬的
// 鈕上是 0.70 → 1.0，整組內容連圖示帶文字放大 43%，讀起來就是「圖案往右滑才
// 定位」。兩組各排各的，每一組的位置與大小就都等於它靜態時的樣子，淡入完不必
// 再移動任何東西，收尾切回靜態鈕也不會跳。
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
        child: MiniButtonContent(
          icon: iconWidget ?? Icon(icon, size: 17, color: fg),
          label:
              labelWidget ??
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
        ),
      ),
    );
  }
}

/// 小動作鈕的**內容**（不含底色與 InkWell）。
///
/// 之所以要能單獨拿出來用：解鎖演出需要把「未購買」與「已購買」兩組內容疊在
/// 同一顆膠囊裡交叉淡入，而**每一組都必須自己排自己的版**——`FittedBox` 的
/// 縮放倍率取決於內容有多寬，兩組寬度差很多（實測 85pt 的鈕上，「50 足跡幣」
/// 被縮到 0.70，「加入」則是 1.0）。共用一組版面就一定會有人被拉著跑。
class MiniButtonContent extends StatelessWidget {
  final Widget icon;
  final Widget label;

  const MiniButtonContent({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [icon, const SizedBox(width: 5), label],
        ),
      ),
    );
  }
}

// ── 解鎖演出的時間軸 ────────────────────────────────────
//
// 這些是**唯一**的真相來源；測試 import 它們，不要在別處另寫一組數字。
//
// ⚠️ 節拍全部以**絕對毫秒**寫在 [_Beat] 裡，比例常數一律由它推導。
// 早期是把 `180 / 1920` 這種分數手寫在各處，改一次總長就要重算一整排，
// 漏掉一個就是節拍錯位而且很難看出來。要調時間軸只動 [_Beat]。
//
// 為什麼這麼慢：第一版 1000ms 跑完，實機看起來像「閃一下就結束」。精緻感需要
// 時間——尤其掙脫（要讀得出「它在用力」）與彈開之後的消散。

/// 時間軸上的每一個節拍（毫秒）。
abstract final class _Beat {
  /// 蓄力結束＝開始搖晃（也是搖晃音的觸發點）。
  static const shake = 180;

  /// 鎖彈開＝衝擊點。解鎖音、觸覺、星芒、**以及淡出**都從這一幀起算。
  static const impact = 900;

  /// 鎖的**物理**演出收乾淨（overshoot 回到 1.0、舞台放大收回）。
  static const lockSettled = 1300;

  /// 換手：舊內容剛好淡完，新內容從同一刻開始淡入。
  ///
  /// ⚠️ 兩段**首尾相接、不重疊**，交界處的空洞是靠**曲線**處理的，不是靠重疊。
  /// 這兩條路都走過：
  /// - 線性且首尾相接 → 交界處兩邊同時趨近 0，出現一顆**完全空白的膠囊**
  ///   （實錄 1977ms 整顆是空的）。時間拉愈長洞愈明顯。
  /// - 讓兩段重疊 220ms 去補那個洞 → 洞補起來了，但實錄 1847ms 看得到兩組
  ///   **半透明疊在一起的鬼影**，又回到當初否決「同時淡入淡出」的那個問題。
  ///
  /// 現在的做法是讓淡出用 `easeInCirc`、淡入用 `easeOutCirc`——這兩條在端點的
  /// 斜率趨近無限大，也就是兩邊都**近乎垂直地穿過**「快看不見」的那一段，於是
  /// 誰也不必等誰。空白縮到 20ms 以內，而且任何一幀都只有一組內容。
  /// 一般的 easeIn/easeOut 不夠——實測仍空 60ms，多項式曲線在終點是平滑收 0 的。
  static const handoff = 1940;

  /// 演出結束。
  static const total = 2940;

  /// 星芒從炸開到散盡。
  static const burst = 830;
}

/// 蓄力：鎖繃緊、微微縮小。
const Duration kUnlockAnticipate = Duration(milliseconds: _Beat.shake);

/// 掙脫般的左右搖晃（振幅先漲後收），起點伴隨搖晃音。
const Duration kUnlockShake = Duration(
  milliseconds: _Beat.impact - _Beat.shake,
);

/// 鎖彈開後的物理餘韻：overshoot 收回、舞台放大收乾淨。
/// 淡出**與這一段重疊**——鎖是一邊回彈一邊化掉的。
const Duration kUnlockSettle = Duration(
  milliseconds: _Beat.lockSettled - _Beat.impact,
);

/// 化成「加入」：舊內容淡出 → 換手 → 新內容淡入。
///
/// **兩者不重疊。** 比稿實錄證實同時淡入淡出在這顆鈕上會糊掉：兩組內容的版面
/// 差很多（未購買那組被 `FittedBox` 縮到 0.70、已購買那組是 1.0），字必然互相
/// 穿插，中間約 280ms 讀起來是「≡+50 加入幣」。錯開之後任何一幀都只有一組東西。
const Duration kUnlockMorph = Duration(
  milliseconds: _Beat.total - _Beat.impact,
);

/// 完整演出長度。
const Duration kUnlockTotal = Duration(milliseconds: _Beat.total);

/// Reduce Motion 版：只保留語意上的三段換圖，不做位移與縮放。
const Duration kUnlockTotalReduced = Duration(milliseconds: 420);

/// 搖晃開始（＝搖晃音的觸發點）在整條弧線上的位置。
const double kUnlockShakeAt = _Beat.shake / _Beat.total;

/// 鎖彈開（＝衝擊點）在整條弧線上的位置。
const double kUnlockImpactAt = _Beat.impact / _Beat.total;

/// 鎖的**物理**演出收乾淨的位置（overshoot 回到 1.0、舞台放大收回）。
///
/// ⚠️ 這**不是**淡出的起點，兩者是分開的：鎖是一邊回彈一邊化掉的。
const double kUnlockMorphAt = _Beat.lockSettled / _Beat.total;

/// 舊內容開始淡出＝**鎖彈開的那一幀**。
///
/// 使用者指定：星芒炸開的同時舊內容就要開始走，不會有一段「光都放完了、畫面卻
/// 還沒開始變」的空檔。
const double kUnlockFadeOutAt = kUnlockImpactAt;

/// 換手點：舊內容剛好淡完、新內容從這裡開始（理由見 `_Beat.handoff`）。
const double kUnlockHandoffAt = _Beat.handoff / _Beat.total;

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
    // 使用者：「太短，根本看不清楚就消失」。240ms → 830ms。
    const span = _Beat.burst / _Beat.total;
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
        final fadeOut = _fadeOutAt(t, reduce);
        final c = _fadeInAt(t, reduce);

        // 底層＝「未購買」那一組內容（會動的鎖＋原本的標籤），照它自己的版面。
        // 膠囊底色與 InkWell 由這一顆提供，所以只把**內容**調透明度，
        // 不能整顆包 Opacity——那樣底色也會跟著淡掉。
        final button = MiniActionButton(
          label: widget.unlockedLabel,
          icon: widget.unlockedIcon,
          color: widget.color,
          onTap: widget.onUnlockedTap,
          // Reduce Motion 只留換圖：**完全不建** Transform 與光效，
          // 而不是建了再傳 0——後者等於偏好沒有真的生效。
          iconWidget: Opacity(
            opacity: fadeOut,
            child: reduce
                ? SizedBox(width: 17, height: 17, child: _lockIcon(t, reduce))
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
                            child: _lockIcon(t, reduce),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          labelWidget: Opacity(
            opacity: fadeOut,
            child: Text(
              widget.lockedLabel,
              style: _labelStyle,
              softWrap: false,
              maxLines: 1,
            ),
          ),
        );

        // 上層＝「已購買」那一組內容，**自己排自己的版**（見 [MiniButtonContent]）。
        // Positioned.fill 讓它拿到與底層完全相同的外框，於是它算出來的位置與縮放
        // 就等於演出結束後那顆靜態鈕——淡入完不必再移動任何東西。
        final incoming = c <= 0
            ? null
            : Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: c.clamp(0.0, 1.0),
                    child: MiniButtonContent(
                      icon: Icon(
                        widget.unlockedIcon,
                        size: 17,
                        color: widget.color,
                      ),
                      label: Text(
                        widget.unlockedLabel,
                        style: _labelStyle,
                        softWrap: false,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
              );

        if (reduce) {
          return Stack(
            fit: StackFit.passthrough,
            children: [button, ?incoming],
          );
        }
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
            ?incoming,
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _UnlockBurstPainter(
                    progress: _burstAt(t),
                    glow: _afterglowAt(t),
                    color: widget.color,
                    lockedContentWidth: _lockedContentWidth,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 底層（未購買那一組）的鎖：彈開前闔著，彈開後打開。
  ///
  /// 這裡只管鎖。「加入」圖示屬於另一組內容、疊在上層自己淡入，兩者不共用
  /// 任何版面——正是這個分離讓演出全程沒有位移。
  Widget _lockIcon(double t, bool reduce) {
    final open = reduce ? t >= 0.34 : t >= kUnlockImpactAt;
    return Icon(
      open ? Icons.lock_open_rounded : Icons.lock_rounded,
      size: 17,
      color: widget.color,
    );
  }

  TextStyle get _labelStyle => TextStyle(
    color: widget.color,
    fontSize: 12.5,
    fontWeight: FontWeight.w900,
  );

  /// 量一段文字在目前 textScaler 下的自然尺寸（不受任何約束）。
  Size _measure(String text, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler:
          MediaQuery.maybeOf(context)?.textScaler ?? TextScaler.noScaling,
    )..layout();
    return tp.size;
  }

  /// 未購買那一組的不透明度：鎖彈開的那一幀開始走，換手點歸零。
  ///
  /// `easeInCirc` 讓它**在尾端垂直掉完**（導數在終點趨近無限大），少待在「快看不見」的那一段。理由見
  /// `_Beat.handoff`：交界處的空洞是靠曲線處理的，不是靠兩段重疊。
  double _fadeOutAt(double t, bool reduce) {
    if (reduce) return t >= 0.67 ? 0 : 1;
    final p = ((t - kUnlockFadeOutAt) / (kUnlockHandoffAt - kUnlockFadeOutAt))
        .clamp(0.0, 1.0);
    return 1 - Curves.easeInCirc.transform(p);
  }

  /// 已購買那一組的不透明度：從換手點淡到演出結束。
  ///
  /// `easeOutCirc` 讓它**一起步就衝出來**（同一個道理，反過來），與上面那條互補。
  double _fadeInAt(double t, bool reduce) {
    if (reduce) return t >= 0.67 ? 1 : 0;
    final p = ((t - kUnlockHandoffAt) / (1 - kUnlockHandoffAt)).clamp(0.0, 1.0);
    return Curves.easeOutCirc.transform(p);
  }

  /// 未購買那一組內容的自然寬度（圖示＋間距＋標籤）。星芒光源用它反推鎖在哪。
  double get _lockedContentWidth =>
      17 + 5 + _measure(widget.lockedLabel, _labelStyle).width;
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

  /// 未購買那一組內容的自然寬度。用來反推鎖在哪。
  final double lockedContentWidth;

  const _UnlockBurstPainter({
    required this.progress,
    required this.glow,
    required this.color,
    required this.lockedContentWidth,
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

  /// 光源＝**鎖頭的實際位置**。
  ///
  /// 兩個踩過的坑，兩個都得算進去：
  ///
  /// 1. 第一版寫死成 `8 + 17/2`（假設圖示貼齊按鈕左緣），但內容是
  ///    `MainAxisAlignment.center` **置中**的——140pt 的按鈕上差了約 24px，
  ///    整團星星因此偏在鎖的左邊。
  /// 2. 第二版算了置中卻忽略 `FittedBox`：真實卡片的鈕只有約 85pt，
  ///    「50 足跡幣」那組內容塞不下、被縮到 0.70，鎖的實際尺寸與位置都跟著變。
  ///
  /// 所以這裡照 `MiniButtonContent` 的排版原樣重算一次：扣掉左右 padding、
  /// 求 `scaleDown` 倍率、再置中。
  Offset _origin(Size s) {
    const pad = 8.0;
    const iconSize = 17.0;
    final inner = s.width - pad * 2;
    if (inner <= 0 || lockedContentWidth <= 0) {
      return Offset(s.width / 2, s.height / 2);
    }
    final scale = math.min(1.0, inner / lockedContentWidth);
    final left = pad + (inner - lockedContentWidth * scale) / 2;
    return Offset(left + iconSize * scale / 2, s.height / 2);
  }

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
