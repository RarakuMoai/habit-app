// 打卡演出的共享時間常數。
//
// 單獨一個檔案的理由：勾勾描繪是 HabitCard 的動畫，衝擊點是編排器的一拍，
// 但兩者必須是**同一個時間**——筆尖落點就是觸覺與音效的落點。放在任何一邊
// 都會讓另一邊反向相依；放這裡兩邊都只 import 常數，不形成循環。
//
// Reduce Motion 也走同一條規則：勾勾縮短成 [kCheckDrawDurationReduced]，
// 衝擊點就跟著縮短，不是各自寫一個數字。

import 'package:flutter/foundation.dart';

// Duration 之間不能在 const 運算式裡相加，所以毫秒數才是真正的來源，
// Duration 常數由它們組出來。

/// 勾勾描完的長度＝主衝擊點（毫秒）。
const int kCheckDrawMs = 300;

/// Reduce Motion：仍然把勾畫出來（語意不能只剩顏色變化），但不拖長。
const int kCheckDrawReducedMs = 140;

/// 一般模式下，泡泡／台詞比衝擊點晚多少（先動起來，才開口）。
const int kSpeakAfterImpactMs = 170;

/// Reduce Motion 下的同一個間隔。位移演出拿掉了，但順序要留著。
const int kSpeakAfterImpactReducedMs = 60;

const Duration kCheckDrawDuration = Duration(milliseconds: kCheckDrawMs);
const Duration kCheckDrawDurationReduced = Duration(
  milliseconds: kCheckDrawReducedMs,
);

/// 這一次要用哪一組勾勾長度。
@visibleForTesting
Duration checkDrawDurationFor({required bool reduceMotion}) =>
    reduceMotion ? kCheckDrawDurationReduced : kCheckDrawDuration;
