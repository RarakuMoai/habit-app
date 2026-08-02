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

/// 這一次寫入 persona 要用哪一句話。
///
/// Dart 的具名參數分不出「沒有指定」與「明確不要文字」——兩者都是 `null`。
/// 首頁曾經靠額外的 `inheritSpeech` 旗標補救，但只要有一個呼叫端漏傳，
/// 已經沒有擁有者的本地台詞就會被 `speech ?? _transientSpeech` 帶回畫面上
/// （external 接手之後最明顯：那句話早就不該再出現了）。
/// 改成三選一之後，每個呼叫端都必須表態。
enum HomeSpeechMode {
  /// 沿用首頁**目前仍然擁有**的那句話；沒有擁有者就等於沒有文字。
  inherit,

  /// 明確不要文字。情境本身會不會從台詞池抽一句由 [MascotLines.speaksFor]
  /// 決定——這裡只保證「不從首頁的本地狀態帶東西過去」。
  silence,

  /// 用 [HomeSpeechIntent.text] 那一句。
  say,
}

@immutable
class HomeSpeechIntent {
  final HomeSpeechMode mode;
  final String? text;

  const HomeSpeechIntent._(this.mode, this.text);

  static const HomeSpeechIntent inherit = HomeSpeechIntent._(
    HomeSpeechMode.inherit,
    null,
  );

  static const HomeSpeechIntent silence = HomeSpeechIntent._(
    HomeSpeechMode.silence,
    null,
  );

  /// [text] 為 null 時等同 [silence]——呼叫端算出「這次沒有台詞」時
  /// 不必再自己分支。
  factory HomeSpeechIntent.say(String? text) =>
      text == null ? silence : HomeSpeechIntent._(HomeSpeechMode.say, text);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HomeSpeechIntent && mode == other.mode && text == other.text;

  @override
  int get hashCode => Object.hash(mode, text);

  @override
  String toString() =>
      'HomeSpeechIntent(${mode.name}${text == null ? '' : ': $text'})';
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
