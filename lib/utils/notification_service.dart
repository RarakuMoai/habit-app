// 本機通知服務（計時頁：專注計時 / 運動間歇的階段結束鈴）。
//
// 設計：
//   - App 啟動時呼叫 [init]，初始化 plugin + timezone
//   - 第一次需要排程通知時呼叫 [ensurePermission]，跳系統 dialog
//   - 計時按下開始 → [scheduleAt(endTime)] 把通知排到結束時刻
//   - 暫停 / 重設 / 跳過 → [cancel] 取消已排程通知
//
// 限制：iOS 開靜音/勿擾會被擋；通知音量 = 系統通知音量，不是媒體音量。
// 第三方 app 無法穿透靜音（這是 Apple 給系統 AlarmManager 的特權）。

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// App 啟動時呼叫一次。設定 plugin + timezone。
  /// 不會跳權限 dialog（保留到第一次真的要排通知時）。
  static Future<void> init() async {
    if (_initialized) return;
    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    // iOS：先不要要權限，第一次排通知時才 ensurePermission()
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );
    _initialized = true;
  }

  /// 確保有通知權限。第一次呼叫會跳系統 dialog。
  /// 回傳 true = 有權限可發通知；false = 使用者拒絕或未授權。
  static Future<bool> ensurePermission() async {
    await init();
    // iOS
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      final granted = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }
    // Android
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      final notifGranted =
          await android.requestNotificationsPermission() ?? false;
      // Android 12+ 排精確時間需要 exact alarm 權限
      await android.requestExactAlarmsPermission();
      return notifGranted;
    }
    return false;
  }

  /// 把通知排到 [when]（絕對時間）。同 id 會覆蓋舊的。
  /// [channelName] / [channelDescription]：Android 通知頻道在系統設定裡的
  /// 顯示名稱與說明，由有 context 的呼叫端用 l10n 給。
  static Future<void> scheduleAt(
    DateTime when, {
    required int id,
    required String title,
    required String body,
    required String channelName,
    required String channelDescription,
  }) async {
    await init();
    final zonedTime = tz.TZDateTime.from(when, tz.local);
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: zonedTime,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          // id 保留 pomodoro_channel：改 id 會孤立舊頻道與使用者既有通知偏好。
          // 顯示名稱/說明是「計時」，因為專注與運動的階段通知都走這條。
          'pomodoro_channel',
          channelName,
          channelDescription: channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: false,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  /// 取消指定 id 的排程通知。
  static Future<void> cancel(int id) async {
    await init();
    await _plugin.cancel(id: id);
  }
}
