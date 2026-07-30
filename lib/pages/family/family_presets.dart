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

const List<Preset> kHabitPresets = [
  Preset('刷牙', 5, '🦷'),
  Preset('寫作業', 10, '📚', 0, true),
  Preset('整理房間', 10, '🧹'),
  Preset('閱讀', 10, '📖', 0, true),
  Preset('早起', 10, '🌅'),
  Preset('運動', 15, '🏃', 0, true),
  Preset('喝足夠的水', 5, '💧'),
];

const List<Preset> kDeductionPresets = [
  Preset('罵髒話', 10, '🤬'),
  Preset('不寫作業', 15, '📵'),
  Preset('頂嘴不聽話', 10, '😤'),
  Preset('睡過頭', 10, '😴'),
  Preset('說謊', 20, '🤥'),
  Preset('亂發脾氣', 10, '💢'),
  Preset('打架動手', 30, '👊'),
];

const List<Preset> kRewardPresets = [
  Preset('看電視', 30, '📺', 0, true),
  Preset('玩遊戲', 30, '🎮', 0, true),
  Preset('選今晚的晚餐', 50, '🍽️'),
  Preset('買零食', 50, '🍬'),
  Preset('延後睡覺', 40, '🌙', 0, true),
  Preset('電影院看電影', 100, '🎬'),
  Preset('買玩具', 150, '🧸'),
];
