// SharedPreferences key 集中定義。
//
// 所有持久化 key 一律在這裡宣告，頁面/服務只引用常數，不准在呼叫端
// 硬寫字串。新增 key 時順手分到對應區塊；帶日期的 key 用 prefix 常數
// 加上 `PrefsKeys.xxxDay(date)` helper 組出來。

abstract final class PrefsKeys {
  // ── Onboarding / 個人資料 ─────────────────────────────────
  static const onboardingDone = 'onboarding_done';
  static const onboardingDate = 'onboarding_date';
  static const userNickname = 'user_nickname';
  static const mascotName = 'mascot_name';
  static const userGender = 'user_gender';
  static const userBirthday = 'user_birthday';
  static const userHeight = 'user_height'; // 公制 cm // units-ok
  static const userWeight = 'user_weight'; // 公制 kg // units-ok
  static const targetWeight = 'target_weight'; // 公制 kg // units-ok
  static const userActivityLevel = 'user_activity_level';

  // ── 功能開關 ─────────────────────────────────────────────
  static const timerEnabled = 'timer_enabled';
  static const waterEnabled = 'water_enabled';
  static const weightTrackingEnabled = 'weight_tracking_enabled';
  static const familyEnabled = 'family_enabled';

  // ── 習慣 / 連續天數 ──────────────────────────────────────
  static const habits = 'habits';
  static const streak = 'streak';
  static const lastOpenDate = 'last_open_date';

  // ── 喝水 ─────────────────────────────────────────────────
  static const waterCupMl = 'water_cup_ml';
  static const waterGoalMl = 'water_goal_ml';
  static const waterGoalDate = 'water_goal_date';

  // 帶日期的 key（date 格式 yyyy-MM-dd）。
  // 注意：water_page 掃 getKeys() 時長 prefix 要先比對，
  // 避免 'water_extra_…' 被當成 'water_' 漏判。
  static const waterDayPrefix = 'water_';
  static const waterEntriesPrefix = 'water_entries_';
  static const waterExtraPrefix = 'water_extra_';
  static const waterSavedPrefix = 'water_saved_';
  static const waterEntriesSavedPrefix = 'water_entries_saved_';

  static String waterDay(String date) => '$waterDayPrefix$date';
  static String waterEntries(String date) => '$waterEntriesPrefix$date';
  static String waterExtra(String date) => '$waterExtraPrefix$date';
  static String waterSaved(String date) => '$waterSavedPrefix$date';
  static String waterEntriesSaved(String date) =>
      '$waterEntriesSavedPrefix$date';

  // ── 體重 ─────────────────────────────────────────────────
  static const weightRecords = 'weight_records';

  // ── 家庭（親子）─────────────────────────────────────────
  static const children = 'children';
  static const childHabits = 'child_habits';
  static const deductionItems = 'deduction_items';
  static const rewardItems = 'reward_items';
  static const voucherLogs = 'voucher_logs';
  static const legacyRedemptionLogs = 'redemption_logs'; // 舊版名稱，僅讀取
  static const pointRecords = 'point_records';
  static const pinDigits = 'pin_digits';
  static const parentPinHash = 'parent_pin_hash';
  static const legacyParentPin = 'parent_pin'; // 舊版明文 PIN，僅遷移用

  // ── 音訊 ─────────────────────────────────────────────────
  static const musicMuted = 'music_muted';
  static const sfxMuted = 'sfx_muted';
  static const legacyBgmMuted = 'bgm_muted'; // 舊版名稱，僅遷移用

  // ── 單位系統 ─────────────────────────────────────────────
  static const unitSystem = 'unit_system';
}
