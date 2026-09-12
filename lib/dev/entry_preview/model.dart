import 'package:flutter/foundation.dart';

/// Purely in-memory prototype. No repositories, credentials or preferences.
enum EntryStage {
  initializing,
  initializationFailed,
  cover,
  authorizing,
  restore,
  meeting,
  nickname,
  room,
}

enum EntryScenario {
  firstUse,
  returningSignedIn,
  returningGuest,
  credentialsOnly,
  offline,
  initializationFailed,
}

enum PreviewAuthResult {
  successNew,
  successExisting,
  canceled,
  failed,
  offline,
}

enum PreviewNotice {
  none,
  canceled,
  loginFailed,
  offline,
  restoreFailed,
  simulatedRestored,
}

class EntryPreviewModel extends ChangeNotifier {
  EntryPreviewModel({EntryScenario scenario = EntryScenario.firstUse}) {
    selectScenario(scenario);
  }
  EntryScenario scenario = EntryScenario.firstUse;
  EntryStage stage = EntryStage.initializing;
  PreviewNotice notice = PreviewNotice.none;
  bool hasJourney = false;
  bool hasCredential = false;
  bool firstMeetingDone = false;
  bool offline = false;
  bool failInitialization = false;
  String nickname = '';
  String? provider;
  int _epoch = 0;
  int get epoch => _epoch;
  String language = 'system';
  bool reduceMotion = false;
  double? textScale;

  void selectScenario(EntryScenario value) {
    _epoch++;
    scenario = value;
    hasJourney =
        value == EntryScenario.returningSignedIn ||
        value == EntryScenario.returningGuest;
    hasCredential =
        value == EntryScenario.returningSignedIn ||
        value == EntryScenario.credentialsOnly;
    firstMeetingDone = hasJourney;
    offline = value == EntryScenario.offline;
    failInitialization = value == EntryScenario.initializationFailed;
    nickname = hasJourney ? '小日' : '';
    provider = hasCredential ? 'Apple' : null;
    notice = PreviewNotice.none;
    stage = EntryStage.initializing;
    notifyListeners();
  }

  void initialized(int operation, {bool failed = false}) {
    if (operation != _epoch || stage != EntryStage.initializing) return;
    stage = (failed || failInitialization)
        ? EntryStage.initializationFailed
        : EntryStage.cover;
    notifyListeners();
  }

  void coldLaunch({bool retry = false}) {
    _epoch++;
    if (retry) failInitialization = false;
    stage = EntryStage.initializing;
    notice = PreviewNotice.none;
    notifyListeners();
  }

  void continueJourney() {
    if (stage != EntryStage.cover || !hasJourney) return;
    stage = firstMeetingDone ? EntryStage.room : EntryStage.meeting;
    notifyListeners();
  }

  void startGuest() {
    if (stage != EntryStage.cover || hasJourney) return;
    hasJourney = true;
    hasCredential = false;
    firstMeetingDone = false;
    provider = null;
    notice = PreviewNotice.none;
    stage = EntryStage.meeting;
    notifyListeners();
  }

  int? beginAuth(String value) {
    if (stage != EntryStage.cover || hasJourney) return null;
    if (offline) {
      notice = PreviewNotice.offline;
      notifyListeners();
      return null;
    }
    provider = value;
    stage = EntryStage.authorizing;
    notice = PreviewNotice.none;
    final operation = ++_epoch;
    notifyListeners();
    return operation;
  }

  void completeAuth(int operation, PreviewAuthResult result) {
    if (operation != _epoch || stage != EntryStage.authorizing) return;
    if (result == PreviewAuthResult.successNew ||
        result == PreviewAuthResult.successExisting) {
      hasCredential = true;
      if (result == PreviewAuthResult.successExisting) {
        stage = EntryStage.restore;
      } else {
        hasJourney = true;
        firstMeetingDone = false;
        stage = EntryStage.meeting;
      }
    } else {
      stage = EntryStage.cover;
      notice = switch (result) {
        PreviewAuthResult.canceled => PreviewNotice.canceled,
        PreviewAuthResult.offline => PreviewNotice.offline,
        _ => PreviewNotice.loginFailed,
      };
    }
    notifyListeners();
  }

  void openRestore() {
    if (!hasCredential || hasJourney || stage != EntryStage.cover) return;
    stage = EntryStage.restore;
    notifyListeners();
  }

  void restore({required bool success}) {
    if (stage != EntryStage.restore) return;
    if (!success || offline) {
      notice = offline ? PreviewNotice.offline : PreviewNotice.restoreFailed;
    } else {
      hasJourney = true;
      firstMeetingDone = true;
      nickname = '小日';
      notice = PreviewNotice.simulatedRestored;
      stage = EntryStage.room;
    }
    notifyListeners();
  }

  void finishMeeting({bool skip = false}) {
    if (stage != EntryStage.meeting) return;
    firstMeetingDone = true;
    stage = skip ? EntryStage.room : EntryStage.nickname;
    notifyListeners();
  }

  void finishName(String value) {
    if (stage != EntryStage.nickname) return;
    nickname = value.trim();
    stage = EntryStage.room;
    notifyListeners();
  }

  void back() {
    if (stage == EntryStage.authorizing) {
      completeAuth(_epoch, PreviewAuthResult.canceled);
    } else if (stage == EntryStage.meeting || stage == EntryStage.restore) {
      stage = EntryStage.cover;
      notifyListeners();
    } else if (stage == EntryStage.nickname) {
      stage = EntryStage.room;
      notifyListeners();
    }
  }

  void setLanguage(String value) {
    language = value;
    notifyListeners();
  }

  void setAccessibility({bool? motion, double? scale}) {
    if (motion != null) reduceMotion = motion;
    textScale = scale;
    notifyListeners();
  }
}
