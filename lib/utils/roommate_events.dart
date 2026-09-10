import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import 'prefs_keys.dart';
import 'roommate_dialogue.dart';

enum RoommateEvent {
  firstMeet,
  smallWin,
  dayComplete;

  RoommateNode get firstNode => switch (this) {
    firstMeet => RoommateNode.hello,
    smallWin => RoommateNode.smallWin,
    dayComplete => RoommateNode.dayComplete,
  };

  String invitation(AppLocalizations l) => switch (this) {
    firstMeet => l.rdInviteFirst,
    smallWin => l.rdInviteProgress,
    dayComplete => l.rdInviteComplete,
  };
}

/// Invitation frequency only. Dialogue replies never become a stored profile.
class RoommateEventHistory {
  final bool firstMeetHandled;
  final String? handledDay;
  const RoommateEventHistory({this.firstMeetHandled = false, this.handledDay});

  factory RoommateEventHistory.read(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(PrefsKeys.roommateEventHistory);
      if (raw == null) return const RoommateEventHistory();
      final value = jsonDecode(raw);
      if (value is! Map) return const RoommateEventHistory();
      return RoommateEventHistory(
        firstMeetHandled: value['firstMeetHandled'] == true,
        handledDay: value['handledDay'] is String
            ? value['handledDay'] as String
            : null,
      );
    } on FormatException {
      return const RoommateEventHistory();
    } on TypeError {
      return const RoommateEventHistory();
    }
  }

  RoommateEvent? eligible({
    required String day,
    required int completed,
    required int total,
  }) {
    if (handledDay == day) return null;
    if (!firstMeetHandled) return RoommateEvent.firstMeet;
    if (total <= 0 || completed <= 0) return null;
    return completed >= total
        ? RoommateEvent.dayComplete
        : RoommateEvent.smallWin;
  }

  RoommateEventHistory handling(RoommateEvent event, String day) =>
      RoommateEventHistory(
        firstMeetHandled: firstMeetHandled || event == RoommateEvent.firstMeet,
        handledDay: day,
      );

  Future<bool> save(SharedPreferences prefs) => prefs.setString(
    PrefsKeys.roommateEventHistory,
    jsonEncode({
      'firstMeetHandled': firstMeetHandled,
      'handledDay': handledDay,
    }),
  );
}
