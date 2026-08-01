// 首頁台詞的「這句話是誰的」。
//
// 首頁上會冒出台詞的來源不只一種（開場問候、點兔咪、打卡、撤銷、里程碑），
// 每一種都各自排了一個延後清除的 timer。沒有身分標記時，**先排的 timer 會清掉
// 後來的台詞**——例如點兔咪三秒後的清除，把兩秒後才出現的打卡台詞一起收掉。
//
// 這裡只做一件事：讓每一段台詞帶著 (來源, generation, 事件序號)，
// 清除／過期／收尾一律先驗證「現在這句還是不是我的」再動手。
// 這不是全 app 的狀態機，只服務 home_page 的台詞欄位。

import 'package:flutter/foundation.dart';

/// 台詞來源。決定「誰有資格清掉它」，也決定 silent beat 能不能保留它。
enum HomeSpeechSource {
  /// 開場問候／跨日回中性等，由 [MascotPersona] 自己帶進來、首頁沒有主張
  /// 擁有權的台詞。打卡的中間拍**只允許保留這一種**。
  opening,

  /// 使用者點兔咪。
  tap,

  /// 完成一件普通每日習慣。
  completion,

  /// 撤銷打卡。
  undo,

  /// 過半／全完成／連勝這類里程碑。
  milestone,
}

/// 一段首頁台詞的擁有權憑證。
///
/// 相等 = 同一段台詞。三個欄位缺一不可：
/// - [source] 分開不同互動；
/// - [generation] 讓離開首頁／跨日之後的舊 timer 一律失效；
/// - [eventId] 讓同一種互動的第 n 次與第 n+1 次不會互相清除。
@immutable
class HomeSpeechToken {
  final HomeSpeechSource source;
  final int generation;
  final int eventId;

  const HomeSpeechToken(this.source, this.generation, this.eventId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HomeSpeechToken &&
          source == other.source &&
          generation == other.generation &&
          eventId == other.eventId;

  @override
  int get hashCode => Object.hash(source, generation, eventId);

  @override
  String toString() => 'HomeSpeechToken(${source.name}#$generation.$eventId)';
}
