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

  // ── 金幣 ─────────────────────────────────────────────────
  static const coinBalance = 'coin_balance';
  static const coinLedger = 'coin_ledger';
  static const coinLoginLevel = 'coin_login_level';
  static const coinLastLoginDate = 'coin_last_login_date';

  // 每日一次型來源的防重複 key（date 格式 yyyy-MM-dd）
  static const coinClaimPrefix = 'coin_claim_';
  static String coinClaim(String source, String date) =>
      '$coinClaimPrefix${source}_$date';

  // ── 計時頁：專注（番茄鐘）──────────────────────────────────
  static const timerFocusMinutes = 'timer_focus_minutes';
  static const timerShortBreakMinutes = 'timer_short_break_minutes';
  static const timerLongBreakMinutes = 'timer_long_break_minutes';
  static const timerLongBreakEnabled = 'timer_long_break_enabled'; // 結尾長休息
  static const timerRounds = 'timer_rounds'; // 一節幾顆番茄（1–8）
  // 上次選的方案：0/1/2=預設組、3=自訂（重開 app 記憶用）。
  static const timerSelectedPreset = 'timer_selected_preset';
  // 自訂改為 3 個可命名槽。槽0 向後相容上面舊的 focus/short/rounds key。
  static String timerCustomFocus(int i) => 'timer_custom_${i}_focus';
  static String timerCustomShort(int i) => 'timer_custom_${i}_short';
  static String timerCustomRounds(int i) => 'timer_custom_${i}_rounds';
  static String timerCustomName(int i) => 'timer_custom_${i}_name';
  static const timerCustomSlot = 'timer_custom_slot'; // 目前生效的自訂槽 0–2

  // 帶日期的今日統計（date 格式 yyyy-MM-dd）
  static const timerTomatoesPrefix = 'timer_tomatoes_';
  static const timerFocusMinutesDayPrefix = 'timer_focus_min_';

  static String timerTomatoes(String date) => '$timerTomatoesPrefix$date';
  static String timerFocusMinutesDay(String date) =>
      '$timerFocusMinutesDayPrefix$date';

  // ── 計時頁：上層模式（專注/運動）與運動子模式 ──────────────
  static const timerMode = 'timer_mode'; // 'focus' | 'exercise'
  static const exerciseSubMode = 'exercise_submode'; // tabata/hiit/emom/gym/jog

  // 各運動子模式的設定，key 由 子模式 id + 欄位 組成（id：tabata/hiit/emom/gym/jog）
  static String _ex(String id, String field) => 'exercise_${id}_$field';
  static String exerciseWork(String id) => _ex(id, 'work'); // 每組運動秒數
  static String exerciseRest(String id) => _ex(id, 'rest'); // 每組休息秒數
  static String exerciseRounds(String id) => _ex(id, 'rounds'); // 總組數
  static String exercisePrep(String id) => _ex(id, 'prep'); // 開始前準備秒數
  static String exerciseWarmupOn(String id) => _ex(id, 'warmup_on');
  static String exerciseWarmup(String id) => _ex(id, 'warmup'); // 暖身秒數
  static String exerciseCooldownOn(String id) => _ex(id, 'cooldown_on');
  static String exerciseCooldown(String id) => _ex(id, 'cooldown'); // 收操秒數
  static String exerciseBpm(String id) => _ex(id, 'bpm');
  static String exerciseMetronomeOn(String id) => _ex(id, 'metronome_on');
  static String exerciseMetronomeSoundOn(String id) =>
      _ex(id, 'metronome_sound_on');
  static String exerciseMetronomeVolume(String id) =>
      _ex(id, 'metronome_volume');
  static String exerciseMetronomeTone(String id) => _ex(id, 'metronome_tone');

  // 帶日期的今日運動統計
  static const exerciseSessionsPrefix = 'exercise_sessions_';
  static const exerciseMinutesDayPrefix = 'exercise_min_';
  static String exerciseSessions(String date) => '$exerciseSessionsPrefix$date';
  static String exerciseMinutesDay(String date) =>
      '$exerciseMinutesDayPrefix$date';

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

  // ── Debug（僅 kDebugMode 讀取，截圖驗證用，release 不碰）──
  static const debugSceneHour = 'debug_scene_hour'; // double 0~24
  static const debugStartTab = 'debug_start_tab'; // int 啟動分頁 index
}
