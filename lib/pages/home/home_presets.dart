// 首頁常用習慣 preset 定義與選取時的自訂設定。

import '../../utils/prefs_keys.dart';

class PresetConfig {
  int minutes;
  String frequency;
  int weeklyTarget;
  PresetConfig({
    required this.minutes,
    this.frequency = 'daily',
    this.weeklyTarget = 3,
  });
}

class HomePreset {
  final String name;
  final String emoji;
  final String? linkedSetting;
  final String? linkedLabel;
  final int? defaultMinutes;
  final bool supportsFrequency;
  const HomePreset(
    this.name,
    this.emoji, [
    this.linkedSetting,
    this.linkedLabel,
    this.defaultMinutes,
    this.supportsFrequency = false,
  ]);
}

const List<HomePreset> kHomePresets = [
  HomePreset('刷牙', '🦷'),
  HomePreset('整理環境', '🧹'),
  HomePreset('閱讀', '📖', null, null, 0, true),
  HomePreset('早起', '🌅'),
  HomePreset('運動', '🏃', null, null, 0, true),
  HomePreset('喝足夠的水', '💧', PrefsKeys.waterEnabled, '選取後自動開啟喝水頁籤'),
  HomePreset('冥想', '🧘', null, null, 0, true),
  HomePreset('早睡', '🌙'),
];
