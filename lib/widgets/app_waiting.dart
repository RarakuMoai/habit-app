// 全 app 共用的「正在等待」語彙。
//
// 這條進度條的來源是啟動畫面（U1 已驗收的 _StartupSplash）。刻意讓每個房間
// 用同一條，而不是各頁自己想：使用者開 app 看到它，進任何一頁再看到同一條，
// 讀起來是同一盞燈在亮，不是十六個各自為政的系統在轉圈。
//
// 為什麼是橫條不是轉圈：轉圈是「系統在忙」的通用符號，走的是 Material 預設
// 的形狀與 seed 派生色，跟這個 app 的暖色手繪世界沒有關係。橫條是這個 app
// 自己已經畫過的東西。
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

/// 整頁／整個分頁還沒載完時的等待畫面：置中的一條 [AppLoadingBar]。
///
/// **只放進度條，不放兔咪。** 這些等待多半只有幾個 frame，讓角色閃現一下再
/// 消失會變成雜訊；而且兔咪要在等待時做什麼是待機生命感那條線的題目，
/// 不在這裡決定。
///
/// 不自帶 [Scaffold]：呼叫端本來就有自己的骨架（有的還帶 AppBar），
/// 這裡多包一層會在載完的瞬間換掉整個 Scaffold，反而多一次跳動。
class AppPageWaiting extends StatelessWidget {
  const AppPageWaiting({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: AppLoadingBar());
  }
}
