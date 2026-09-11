/// A one-shot navigation intent. No user data or progress is stored here.
abstract final class AppEntryIntent {
  static int? restoringRevision;
  static String? restoringUid;
  static bool openBackup = false;
  static bool consumeBackup() {
    final result = openBackup;
    openBackup = false;
    return result;
  }
}
