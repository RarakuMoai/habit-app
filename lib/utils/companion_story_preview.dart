import 'package:flutter/foundation.dart';
import 'feature_flags.dart';

/// In-memory inspection only. Never saved or used to calculate story progress.
class CompanionStoryPreview {
  static final ValueNotifier<bool> enabled = ValueNotifier(false);
  static bool get active => kDevToolsEnabled && enabled.value;
  static void setEnabled(bool value) {
    enabled.value = kDevToolsEnabled && value;
  }
}
