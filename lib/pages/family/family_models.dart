// 育兒模式資料模型（小孩、習慣、扣分、獎勵、票券、積分紀錄）

// ── 資料模型 ──

class ChildData {
  final String id;
  String name;
  String avatar;
  int points;
  ChildData({
    required this.id,
    required this.name,
    this.avatar = '🐼',
    required this.points,
  });

  factory ChildData.fromJson(Map<String, dynamic> json) => ChildData(
    id: json['id'] as String,
    name: json['name'] as String,
    avatar: (json['avatar'] as String?) ?? '🐼',
    points: (json['points'] as int?) ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'avatar': avatar,
    'points': points,
  };
}

// 小孩習慣
class ChildHabit {
  final String id;
  final String childId;
  String name;
  int points;
  String completedDate; // 每日習慣：最後打卡日期；每週習慣：不使用
  String frequency; // 'daily' | 'weekly'
  int weeklyTarget; // 每週目標次數（1-7）
  List<String> weeklyDates; // 本週已完成的日期清單
  int minutes; // 持續時間（分鐘），0 表示未設定

  ChildHabit({
    required this.id,
    required this.childId,
    required this.name,
    required this.points,
    this.completedDate = '',
    this.frequency = 'daily',
    this.weeklyTarget = 3,
    List<String>? weeklyDates,
    this.minutes = 0,
  }) : weeklyDates = weeklyDates ?? [];

  factory ChildHabit.fromJson(Map<String, dynamic> json) => ChildHabit(
    id: json['id'] as String,
    childId: json['child_id'] as String,
    name: json['name'] as String,
    points: (json['points'] as int?) ?? 0,
    completedDate: (json['completed_date'] as String?) ?? '',
    frequency: (json['frequency'] as String?) ?? 'daily',
    weeklyTarget: (json['weekly_target'] as int?) ?? 3,
    weeklyDates:
        (json['weekly_dates'] as List?)?.map((e) => e as String).toList() ?? [],
    minutes: (json['minutes'] as int?) ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'child_id': childId,
    'name': name,
    'points': points,
    'completed_date': completedDate,
    'frequency': frequency,
    'weekly_target': weeklyTarget,
    'weekly_dates': weeklyDates,
    'minutes': minutes,
  };
}

// 扣分項目
class DeductionItem {
  final String id;
  final String childId;
  String name;
  int points; // 扣幾分（正整數，扣分時取負）
  String deductedDate; // 最後扣分日期，格式 yyyy-MM-dd；空字串表示今日未扣

  DeductionItem({
    required this.id,
    required this.childId,
    required this.name,
    required this.points,
    this.deductedDate = '',
  });

  factory DeductionItem.fromJson(Map<String, dynamic> json) => DeductionItem(
    id: json['id'] as String,
    childId: json['child_id'] as String,
    name: json['name'] as String,
    points: (json['points'] as int?) ?? 0,
    deductedDate: (json['deducted_date'] as String?) ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'child_id': childId,
    'name': name,
    'points': points,
    'deducted_date': deductedDate,
  };
}

// 獎勵項目
class RewardItem {
  final String id;
  String name;
  int pointsCost;
  int minutes;
  List<String> childIds;

  RewardItem({
    required this.id,
    required this.name,
    required this.pointsCost,
    this.minutes = 0,
    required this.childIds,
  });

  factory RewardItem.fromJson(Map<String, dynamic> json) => RewardItem(
    id: json['id'] as String,
    name: json['name'] as String,
    pointsCost: (json['points_cost'] as int?) ?? 0,
    minutes: (json['minutes'] as int?) ?? 0,
    childIds:
        (json['child_ids'] as List?)?.map((e) => e as String).toList() ?? [],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'points_cost': pointsCost,
    'minutes': minutes,
    'child_ids': childIds,
  };
}

// 票券紀錄（兌換後產生，need 使用才算消耗）
class VoucherLog {
  final String id;
  final String rewardId;
  final String childId;
  final String redeemedAt; // yyyy-MM-dd HH:mm
  bool used;
  String usedAt; // 空字串 = 尚未使用

  VoucherLog({
    required this.id,
    required this.rewardId,
    required this.childId,
    required this.redeemedAt,
    this.used = false,
    this.usedAt = '',
  });

  factory VoucherLog.fromJson(Map<String, dynamic> json) => VoucherLog(
    id: json['id'] as String,
    rewardId: json['reward_id'] as String,
    childId: json['child_id'] as String,
    redeemedAt:
        (json['redeemed_at'] as String?) ??
        (json['time'] as String? ?? ''), // 向下相容舊格式
    used: (json['used'] as bool?) ?? false,
    usedAt: (json['used_at'] as String?) ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'reward_id': rewardId,
    'child_id': childId,
    'redeemed_at': redeemedAt,
    'used': used,
    'used_at': usedAt,
  };
}

// 積分紀錄
class PointRecord {
  final String id;
  final String childId;
  final String time; // 格式 yyyy-MM-dd HH:mm
  final String reason;
  final int delta; // 正數加分、負數扣分
  final int total; // 變動後累積總分

  PointRecord({
    required this.id,
    required this.childId,
    required this.time,
    required this.reason,
    required this.delta,
    required this.total,
  });

  factory PointRecord.fromJson(Map<String, dynamic> json) => PointRecord(
    id: json['id'] as String,
    childId: json['child_id'] as String,
    time: json['time'] as String,
    reason: json['reason'] as String,
    delta: (json['delta'] as int?) ?? 0,
    total: (json['total'] as int?) ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'child_id': childId,
    'time': time,
    'reason': reason,
    'delta': delta,
    'total': total,
  };
}
