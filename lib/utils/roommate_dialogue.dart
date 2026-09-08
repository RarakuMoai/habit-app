import 'package:flutter/foundation.dart';

import '../l10n/app_localizations.dart';
import 'mascot.dart';
import 'sfx_service.dart';

enum RoommateNode { hello, invitation, begin, rest, homesick, together, quiet }

class RoommateReply {
  final String id;
  final String label;
  final RoommateNode? next;
  const RoommateReply(this.id, this.label, this.next);
}

extension RoommateScript on RoommateNode {
  String subtitle(AppLocalizations l) => switch (this) {
    RoommateNode.hello => l.rdHello,
    RoommateNode.invitation => l.rdInvitation,
    RoommateNode.begin => l.rdBegin,
    RoommateNode.rest => l.rdRest,
    RoommateNode.homesick => l.rdHomesick,
    RoommateNode.together => l.rdTogether,
    RoommateNode.quiet => l.rdQuiet,
  };

  MascotEmotion get emotion => switch (this) {
    RoommateNode.hello => MascotEmotion.expect,
    RoommateNode.invitation => MascotEmotion.question,
    RoommateNode.begin => MascotEmotion.happy,
    RoommateNode.rest ||
    RoommateNode.together ||
    RoommateNode.quiet => MascotEmotion.smile,
    RoommateNode.homesick => MascotEmotion.neutralFront,
  };

  SfxCue get voice => switch (this) {
    RoommateNode.invitation => SfxCue.tumiQuestion,
    RoommateNode.begin || RoommateNode.together => SfxCue.tumiHappy,
    _ => SfxCue.tumiConfirm,
  };

  List<RoommateReply> replies(AppLocalizations l) => switch (this) {
    RoommateNode.hello => [
      RoommateReply('continue', l.rdContinue, RoommateNode.invitation),
    ],
    RoommateNode.invitation => [
      RoommateReply('begin', l.rdChooseBegin, RoommateNode.begin),
      RoommateReply('rest', l.rdChooseRest, RoommateNode.rest),
    ],
    RoommateNode.begin => [RoommateReply('finish', l.rdPickHabit, null)],
    RoommateNode.rest => [
      RoommateReply('home', l.rdAskHome, RoommateNode.homesick),
      RoommateReply('quiet', l.rdChooseQuiet, RoommateNode.quiet),
    ],
    RoommateNode.homesick => [
      RoommateReply('together', l.rdChooseTogether, RoommateNode.together),
    ],
    RoommateNode.together ||
    RoommateNode.quiet => [RoommateReply('finish', l.rdReturn, null)],
  };
}

/// 本次交談的進度；不寫習慣、不發獎，也不以字幕文字辨識分支。
/// expectedNode + ready 擋下排版前的連點與過期 callback。
class RoommateDialogueController extends ChangeNotifier {
  RoommateNode node = RoommateNode.hello;
  bool ready = false;
  bool finished = false;

  void reveal() {
    if (ready || finished) return;
    ready = true;
    notifyListeners();
  }

  bool choose(
    RoommateReply reply, {
    required RoommateNode expectedNode,
    required AppLocalizations l10n,
  }) {
    if (finished || !ready || node != expectedNode) return false;
    if (!node
        .replies(l10n)
        .any((r) => r.id == reply.id && r.next == reply.next)) {
      return false;
    }
    ready = false;
    if (reply.next case final next?) {
      node = next;
    } else {
      finished = true;
    }
    notifyListeners();
    return true;
  }
}
