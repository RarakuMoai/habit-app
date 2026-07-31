// 育兒模式常用選項預設資料（習慣／扣分／獎勵）
import 'family_models.dart';

// ── 常用選項預設資料 ──

class Preset {
  final String name;
  final int value;
  final String emoji;
  final int defaultMinutes;
  final bool supportsFrequency;
  const Preset(
    this.name,
    this.value, [
    this.emoji = '',
    this.defaultMinutes = 0,
    this.supportsFrequency = false,
  ]);
}

// 每個常用習慣的個別設定（積分、時間、頻率）
class HabitPresetCfg {
  int points;
  int minutes;
  String frequency;
  int weeklyTarget;
  HabitPresetCfg({
    required this.points,
    this.minutes = 0,
    this.frequency = HabitFrequency.daily,
    this.weeklyTarget = 3,
  });
}

class RewardPresetCfg {
  int points;
  int minutes;
  RewardPresetCfg({required this.points, this.minutes = 0});
}

// 積分基準：以「做家事 30 分」為一件費力事的標準（2026-07-31 重訂）。
// 一天典型收入約 100-150 分，獎勵定價以此為基礎（見 kRewardPresets）。
//
// ⚠️ 每日可多次的習慣分數要另外抓：那個分數會被乘上一天的次數。
// 做家事一天 1-3 次 × 30 = 30-90 分合理；喝水一天 6-8 杯，所以只給 5 分/杯。
const List<Preset> kHabitPresets = [
  Preset('刷牙', 10, '🦷'),
  Preset('早起', 10, '🌅'),
  Preset('今日多喝水', 5, '🥤', 0, true),
  Preset('整理房間', 20, '🧹'),
  Preset('閱讀', 20, '📖', 0, true),
  Preset('寫作業', 30, '📚', 0, true),
  Preset('運動', 30, '🏃', 0, true),
  Preset('練習樂器', 30, '🎹', 30, true),
  Preset('做家事', 30, '🧺', 0, true),
];

// 扣分跟對應的正向行為對稱：不寫作業 30 ＝ 白做一次「寫作業」。
const List<Preset> kDeductionPresets = [
  Preset('睡過頭', 10, '😴'),
  Preset('罵髒話', 20, '🤬'),
  Preset('頂嘴不聽話', 20, '😤'),
  Preset('亂發脾氣', 20, '💢'),
  Preset('不寫作業', 30, '📵'),
  Preset('說謊', 50, '🤥'),
  Preset('打架動手', 50, '👊'),
];

// 以一天約 100-150 分回推：日常娛樂存一天、零食類兩天、大獎勵一週上下。
const List<Preset> kRewardPresets = [
  Preset('看電視', 100, '📺', 0, true),
  Preset('玩遊戲', 100, '🎮', 0, true),
  Preset('延後睡覺', 150, '🌙', 0, true),
  Preset('買零食', 200, '🍬'),
  Preset('選今晚的晚餐', 200, '🍽️'),
  Preset('電影院看電影', 500, '🎬'),
  Preset('買玩具', 800, '🧸'),
];
