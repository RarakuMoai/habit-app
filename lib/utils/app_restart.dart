import 'package:flutter/widgets.dart';

/// 包在整個 app 最外層，提供「乾淨重啟整棵 widget 樹」的能力。
///
/// 重置全部資料時需要回到初始狀態。用 [RootRestart.restart] 換掉內層的
/// [KeyedSubtree] key，會讓底下整棵 [MyApp]（含 MaterialApp / Navigator /
/// 所有 route）當成一個單位被丟棄、再用全新 state 重建——重跑 startup 流程、
/// 從清空後的 SharedPreferences 重載金幣/衣櫃/音訊並落在 onboarding。
///
/// 比 `pushNamedAndRemoveUntil((_) => false)` 安全：後者會把含
/// `AnimatedSwitcher`（內部用 GlobalKey 包子節點）的 home route 逐一強拆，
/// 卸載順序錯亂時 InheritedElement 還掛著 dependent，會觸發 framework 的
/// `_dependents.isEmpty` 斷言（debug 紅屏）。整棵子樹一次替換則是 Flutter
/// 正規支援的卸載路徑，不會有 reparent 殘留依賴。
class RootRestart extends StatefulWidget {
  final Widget child;
  const RootRestart({super.key, required this.child});

  static void restart(BuildContext context) {
    context.findAncestorStateOfType<_RootRestartState>()?._restart();
  }

  @override
  State<RootRestart> createState() => _RootRestartState();
}

class _RootRestartState extends State<RootRestart> {
  Key _key = UniqueKey();

  void _restart() => setState(() => _key = UniqueKey());

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _key, child: widget.child);
}
