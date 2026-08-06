// 底部面板頂端的拖曳把手。
//
// 改版前全 app 有 **27 個各自手刻**的把手，分成兩種樣式（36×4 走
// `AppSurfaces.dragHandle`，40×4 硬寫 `#E8DDD4`＋圓角 99），而且**沒有任何一個
// 有手勢處理**——全部是純裝飾的 Container。計時器的專注設定更被放進
// `ScrollContinuationArea` 裡面，所以它還會跟著內容一起捲走。
//
// 這裡收斂成一個元件，解決三件事：
//
// 1. **外觀一致**：36×4、`AppSurfaces.dragHandle`、圓角 2。
//    這是原本的多數樣式（16/26），也是新增習慣面板用的那一種。
// 2. **釘住**：這個元件必須放在**捲動區之外**（面板 Column 的第一個 child），
//    不要塞進 ListView / ScrollContinuationArea 裡。
// 3. **實質有效**：點一下收起面板。
//
// ⚠️ **拖曳不在這裡實作。** `showModalBottomSheet` 的 `enableDrag` 預設就是
// true，全 app 35 個面板沒有任何一處關掉它——往下拉關閉、往上拉回原位是框架
// 本來就有的行為。它之所以「沒反應」，唯一原因是把手被包在捲動區裡，垂直手勢
// 被 Scrollable 搶走。把手釘到捲動區外面，框架的拖曳就會生效。
//
// 所以這個元件刻意**只註冊 onTap**：TapGestureRecognizer 不會參與垂直拖曳的
// 手勢競爭，面板的拖曳照常運作。加了自己的 onVerticalDrag 反而會把它搶回來。

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_feedback.dart';
import '../utils/app_style.dart';

/// 把手本體的尺寸與圓角。改這裡＝改全 app。
const double kSheetHandleWidth = 36;
const double kSheetHandleHeight = 4;
const double kSheetHandleRadius = 2;

/// 可點範圍的總高度。視覺只有 4px，但觸控目標要夠大才按得到。
const double kSheetHandleTapHeight = 28;

class SheetDragHandle extends StatelessWidget {
  /// 點一下是否收起面板。預設 true。
  ///
  /// 少數情況要傳 false：面板有未儲存的輸入、或關閉需要走自己的確認流程。
  /// 傳 false 時把手只剩視覺，拖曳仍然可用（那是框架的行為）。
  final bool tapToClose;

  /// 覆寫收起行為（例如要先收鍵盤、或回傳值）。null = `Navigator.maybePop`。
  final VoidCallback? onClose;

  const SheetDragHandle({super.key, this.tapToClose = true, this.onClose});

  @override
  Widget build(BuildContext context) {
    final bar = Container(
      width: kSheetHandleWidth,
      height: kSheetHandleHeight,
      decoration: BoxDecoration(
        color: AppSurfaces.dragHandle,
        borderRadius: BorderRadius.circular(kSheetHandleRadius),
      ),
    );

    if (!tapToClose && onClose == null) {
      return Center(
        child: SizedBox(
          height: kSheetHandleTapHeight,
          child: Center(child: bar),
        ),
      );
    }

    return Semantics(
      button: true,
      label: AppLocalizations.of(context).dtCollapse,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          playHaptic(HapticLevel.light);
          if (onClose != null) {
            onClose!();
          } else {
            Navigator.maybePop(context);
          }
        },
        child: Center(
          child: SizedBox(
            // 寬一點的可點區，但不要整條橫跨——避免蓋掉面板頂端兩側的內容。
            width: 120,
            height: kSheetHandleTapHeight,
            child: Center(child: bar),
          ),
        ),
      ),
    );
  }
}
