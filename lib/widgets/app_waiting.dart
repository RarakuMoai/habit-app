// 全 app 共用的「正在等待」語彙。
//
// 這條進度條的來源是啟動畫面（U1 已驗收的 _StartupSplash）。刻意讓每個房間
// 用同一條，而不是各頁自己想：使用者開 app 看到它，進任何一頁再看到同一條，
// 讀起來是同一盞燈在亮，不是十六個各自為政的系統在轉圈。
//
// 為什麼是橫條不是轉圈：轉圈是「系統在忙」的通用符號，走的是 Material 預設
// 的形狀與 seed 派生色，跟這個 app 的暖色手繪世界沒有關係。橫條是這個 app
// 自己已經畫過的東西。
import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_style.dart';

/// 等待用的圓角暖橘進度條。
///
/// 不確定進度（indeterminate）是刻意的：這些等待都是讀本機資料，快到給不出
/// 有意義的百分比，硬給一個假的進度反而是騙人。
class AppLoadingBar extends StatelessWidget {
  const AppLoadingBar({super.key, this.width = defaultWidth});

  /// 啟動畫面用的寬度。各頁沿用同一個值，兩層之間才不會有「同一條卻不一樣長」
  /// 的違和——這是 U1 學到的：同一個元素在兩個地方長得不一樣會讀成故障。
  static const double defaultWidth = 96;

  static const double _height = 5;

  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          minHeight: _height,
          backgroundColor: AppWaiting.track,
          color: AppWaiting.bar,
          semanticsLabel: AppLocalizations.of(context).commonLoading,
        ),
      ),
    );
  }
}

/// 整頁／整個分頁還沒載完時的等待畫面：置中的一條 [AppLoadingBar]，
/// 而且**慢到值得說一聲時才亮**。
///
/// 這些頁讀的是本機 prefs，實測多半只等一幀就載完了。若無條件顯示，使用者
/// 看到的不是「燈亮起來」而是閃一下就沒了——一閃而過的東西讀起來就是故障感，
/// 正好與這個 milestone 想要的相反。所以先靜靜等 [_appearAfter]，過了門檻才
/// 淡入：快的載入從頭到尾什麼都不出現，慢的才看得到燈。
///
/// **只放進度條，不放兔咪。** 讓角色閃現一下再消失會變成雜訊；而且兔咪要在
/// 等待時做什麼是待機生命感那條線的題目，不在這裡決定。
///
/// 不自帶 [Scaffold]：呼叫端本來就有自己的骨架（有的還帶 AppBar），
/// 這裡多包一層會在載完的瞬間換掉整個 Scaffold，反而多一次跳動。
class AppPageWaiting extends StatefulWidget {
  const AppPageWaiting({super.key});

  /// 低於這個門檻的等待完全不顯示。200ms 是「還沒來得及被讀成停頓」與
  /// 「久到需要交代一聲」的分界。
  static const Duration _appearAfter = Duration(milliseconds: 200);

  /// 淡入時長。硬切一樣是閃，只是慢了 200ms 才閃；淡入才讀得出「亮起來」。
  static const Duration _fadeIn = Duration(milliseconds: 180);

  @override
  State<AppPageWaiting> createState() => _AppPageWaitingState();
}

class _AppPageWaitingState extends State<AppPageWaiting> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(AppPageWaiting._appearAfter, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduce Motion 只拿掉淡入這段動畫，不改「什麼時候該出現」——門檻是語意
    // （這次等待久不久），不是裝飾。
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Center(
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: reduceMotion ? Duration.zero : AppPageWaiting._fadeIn,
        curve: Curves.easeOut,
        child: const AppLoadingBar(),
      ),
    );
  }
}
