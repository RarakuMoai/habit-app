// 金幣系統數值常數表：發放量、登入等級曲線、寬限規則全部集中在這裡。
// 上架後有匿名使用數據再回來校數字，呼叫端不要散落 magic number。

/// 金幣發放來源。新增來源時在這裡加 enum + [CoinConfig.amountOf] 對應值。
enum CoinSource {
  /// 每日登入（金額依連續等級，見 [CoinConfig.loginRewardAt]）
  dailyLogin,

  /// 完成一個習慣打卡
  habitDone,

  /// 當日全部習慣完成
  allHabitsDone,

  /// 完成一顆番茄（專注時段）
  tomatoDone,

  /// 完成一段運動間歇訓練
  exerciseDone,

  /// 當日喝水達標
  waterGoal,

  /// 連續達標滿 7 天
  weeklyStreak,
}

abstract final class CoinConfig {
  /// 目前實際發放的來源；不在此集合的 award/revoke 一律 no-op。
  /// （2026-06-13 與用戶定案：先只給「每日登入」「習慣全達成」，其餘暫停。
  /// 要重新開放某來源，把它加回這裡即可，呼叫端都還在。）
  static const Set<CoinSource> enabledSources = {
    CoinSource.dailyLogin, // 每日登入（金額隨連續登入等級遞增）
    CoinSource.allHabitsDone, // 當日習慣全達成
    CoinSource.weeklyStreak, // 連續達標滿 7 天里程碑
  };


  // ── 固定金額來源 ──
  static const int habitDone = 2;
  static const int allHabitsDone = 5;
  static const int tomatoDone = 2;
  static const int exerciseDone = 3;
  static const int waterGoal = 5;
  static const int weeklyStreak = 20;

  /// 各來源固定金額（dailyLogin 走等級曲線，不在這裡）
  static int amountOf(CoinSource source) => switch (source) {
    CoinSource.habitDone => habitDone,
    CoinSource.allHabitsDone => allHabitsDone,
    CoinSource.tomatoDone => tomatoDone,
    CoinSource.exerciseDone => exerciseDone,
    CoinSource.waterGoal => waterGoal,
    CoinSource.weeklyStreak => weeklyStreak,
    // dailyLogin 金額依等級，呼叫端用 loginRewardAt(level)
    CoinSource.dailyLogin => loginBase,
  };

  // ── 每日登入等級曲線（2026-06-12 與用戶定案：輕鬆不嚴格）──
  /// 等級 1 的金幣數
  static const int loginBase = 5;

  /// 封頂等級（等級 = 連續登入天數，最高到此）
  static const int loginMaxLevel = 6;

  /// 缺席寬限天數：缺席 <= 此天數，等級不動（兔咪幫你看家）
  static const int loginGraceDays = 1;

  /// 超過寬限後的等級回退量（不歸零，輕鬆基調）
  static const int loginLevelDrop = 2;

  /// 等級對應的登入金幣：5, 6, 7, 8, 9, 10（封頂）
  static int loginRewardAt(int level) =>
      loginBase + (level.clamp(1, loginMaxLevel) - 1);

  // ── 帳本 ──
  /// 帳本只留最近 N 筆（給明細頁/除錯用，餘額才是真相來源）
  static const int ledgerMaxEntries = 200;
}
