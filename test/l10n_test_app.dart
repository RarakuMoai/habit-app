// 測試用的 MaterialApp 包裝：掛上 AppLocalizations delegates。
//
// 頁面遷移 i18n 後會呼叫 AppLocalizations.of(context)，測試若用裸
// MaterialApp(home: ...) 會拿不到 localizations 而 crash。改用這裡的
// l10nTestApp；鎖定 zh-TW 與 main.dart 目前的 locale 一致，測試裡的
// 中文 find.text 不受影響。
import 'package:flutter/material.dart';
import 'package:habit_app/l10n/app_localizations.dart';

Widget l10nTestApp({
  required Widget home,
  List<NavigatorObserver> navigatorObservers = const [],
}) {
  return MaterialApp(
    locale: const Locale('zh', 'TW'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    navigatorObservers: navigatorObservers,
    home: home,
  );
}
