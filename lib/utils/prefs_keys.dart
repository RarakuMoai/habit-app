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
  // 連續登入天數（給 weeklyStreak 里程碑用；與等級曲線分開計）
  static const coinLoginStreak = 'coin_login_streak';

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

  // ── 計時頁：上層模式（專注/運動/節拍器）與運動子模式 ──────────────
  static const timerMode = 'timer_mode'; // 'focus' | 'exercise' | 'metronome'
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

  // ── 計時頁：單純節拍器（與運動的超慢跑節拍器各存各的）──────────
  static const metronomeBpm = 'metronome_bpm';
  static const metronomeTone = 'metronome_tone';
  static const metronomeVolume = 'metronome_volume';
  static const metronomeBeats = 'metronome_beats'; // 每小節拍數（拍號分子）
  static const metronomeBeatUnit = 'metronome_beat_unit'; // 拍號分母（4/8）
  static const metronomeTempoNote = 'metronome_tempo_note'; // BPM 對應音符
  static const metronomeSubdivision = 'metronome_subdivision'; // 細分拍
  static const metronomeAccent = 'metronome_accent'; // 第一拍重音
  static const metronomeHaptic = 'metronome_haptic'; // 觸覺跟拍

  // ── 功能開關 ─────────────────────────────────────────────
  static const timerEnabled = 'timer_enabled';
  static const waterEnabled = 'water_enabled';
  static const weightTrackingEnabled = 'weight_tracking_enabled';
  static const familyEnabled = 'family_enabled';
  static const wardrobeEnabled = 'wardrobe_enabled';
  // 底部分頁的使用者自訂排序（存 TabIds 字串清單，非 index）
  static const tabOrder = 'tab_order';

  // ── 習慣 / 連續天數 ──────────────────────────────────────
  static const habits = 'habits';
  static const streak = 'streak';
  static const lastOpenDate = 'last_open_date';

  // 習慣的逐日完成歷史（補打勾 / 統計用）。每個邏輯日一個 key，值是當天
  // 「已完成的每日習慣 id」清單（JSON）。打勾/取消當下寫入，跨日不清除。
  static const habitDoneDayPrefix = 'habit_done_';
  static String habitDoneDay(String date) => '$habitDoneDayPrefix$date';
  // 已刪除習慣的墓碑（JSON 清單：{id,name,frequency,createdAt,deletedAt}），
  // 讓歷史/補打勾仍能顯示「某天當時存在、後來刪掉」的條目。
  static const habitTombstones = 'habit_tombstones';

  // ── 喝水 ─────────────────────────────────────────────────
  static const waterCupMl = 'water_cup_ml';
  static const waterGoalMl = 'water_goal_ml';
  static const waterGoalDate = 'water_goal_date';
  static const waterGoalSuggestionDismissed = 'water_goal_suggestion_dismissed';
  // 收起建議卡時記下「當下的建議值（ml）」。之後體重等資料變動讓新建議
  // 與這個基準差距夠大，就解除收起、讓提示重新出現（避免錯過更新）。
  static const waterGoalSuggestionBaseline = 'water_goal_suggestion_baseline';

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
  static const parentPinQuestion = 'parent_pin_question'; // 忘記密碼救援問題（明文）
  static const parentPinAnswerHash = 'parent_pin_answer_hash'; // 救援答案雜湊
  static const legacyParentPin = 'parent_pin'; // 舊版明文 PIN，僅遷移用

  // ── 音訊 ─────────────────────────────────────────────────
  static const musicMuted = 'music_muted';
  static const sfxMuted = 'sfx_muted';
  static const legacyBgmMuted = 'bgm_muted'; // 舊版名稱，僅遷移用

  // ── 衣櫃 / 音樂盒 ───────────────────────────────────────
  static const wardrobeSelectedOutfit = 'wardrobe_selected_outfit';
  static const wardrobeOwnedOutfits = 'wardrobe_owned_outfits';
  static const bgmMode = 'bgm_mode'; // 舊版 single/playlist 設定，保留供遷移
  static const bgmSelectedTrack = 'bgm_selected_track';
  static const bgmPlaylist = 'bgm_playlist';
  static const bgmOwnedTracks = 'bgm_owned_tracks';

  // ── 回憶本（特殊事件 / 劇情）──────────────────────────────
  static const storyUnlocked = 'story_unlocked'; // JSON：[{id, date}]，依解鎖時間
  static const storyUnread = 'story_unread'; // 未讀事件 id（未來「書發亮」用）

  // ── 訂閱（佔位，之後接金流時填寫真正狀態）────────────────
  static const subscriptionActive = 'subscription_active';

  // ── 單位系統 ─────────────────────────────────────────────
  static const unitSystem = 'unit_system';

  // ── 換日線（一天從幾點開始；夜貓族把午夜往後挪）────────────
  // int 小時 0~6；只套用在習慣/喝水/體重的「紀錄日」，金幣發獎判重
  // 刻意維持純日曆午夜（見 coin_service），避免靠切設定重複領獎。
  static const dayStartHour = 'day_start_hour';

  // ── Debug（kDevToolsEnabled 控制讀取；目前 release 也暫時開，正式版會移除）──
  static const debugSceneHour = 'debug_scene_hour'; // double 0~24
  static const debugStartTab = 'debug_start_tab'; // int 啟動分頁 index
  static const debugFakeTabCount = 'debug_fake_tab_count'; // 舊版 int 假分頁數，保留供清除
  static const debugFakeTabs = 'debug_fake_tabs'; // List<String> 開啟的模擬分頁 id
  static const debugDayShift = 'debug_day_shift'; // int 已快轉天數（顯示用）
  static const debugDaySnapshot = 'debug_day_snapshot'; // 快轉前整包快照(JSON)，供還原
}
