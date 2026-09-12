import 'dart:async' show TimeoutException;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/dev/entry_preview_main.dart' as preview;
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('isolated native entry review', (tester) async {
    preview.main();
    await tester.pumpAndSettle();
    Future<void> pause([int ms = 650]) async {
      await tester.runAsync(
        () => Future<void>.delayed(Duration(milliseconds: ms)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    Future<void> tap(String key) async {
      final target = find.byKey(ValueKey(key));
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (target.evaluate().isEmpty) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('Control not ready: $key');
        }
        await pause(100);
      }
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      await pause();
    }

    final acknowledgments = await Directory.systemTemp.createTemp(
      'entry-review-',
    );
    Future<void> shot(String name) async {
      await pause();
      final ack = File('${acknowledgments.path}/$name.ready');
      debugPrint('ENTRY_CAPTURE $name ${ack.path}');
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (!await ack.exists()) {
          if (DateTime.now().isAfter(deadline)) {
            throw TimeoutException('Native screenshot not acknowledged: $name');
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        await ack.delete();
      });
    }

    Future<void> scenario(String value) async {
      await tap('scenarios');
      await tap('scenario-$value');
    }

    await tap('language');
    await tap('locale-zh');
    debugPrint('ENTRY_RECORD_START');
    await pause(1500);
    await shot('01-first-cover');
    await tap('apple');
    await shot('02-auth-simulation');
    await tap('auth-cancel');
    await tester.ensureVisible(find.byKey(const ValueKey('notice')));
    await tester.pumpAndSettle();
    await shot('03-canceled');
    await tap('google');
    await tap('auth-failed');
    await tester.ensureVisible(find.byKey(const ValueKey('notice')));
    await tester.pumpAndSettle();
    await shot('04-login-failed');
    await tap('guest');
    await shot('05-first-meeting');
    await tap('meet-next');
    await shot('06-optional-name');
    await tap('skip-name');
    await shot('07-room');
    await tap('room-action');
    await shot('08-room-action');
    await scenario('returningSignedIn');
    await shot('09-returning-signed-in');
    await tap('continue');
    await scenario('returningGuest');
    await shot('10-returning-guest');
    await tap('continue');
    await scenario('credentialsOnly');
    await tap('open-restore');
    await tap('restore-failure');
    await tester.ensureVisible(find.byKey(const ValueKey('notice')));
    await tester.pumpAndSettle();
    await shot('11-restore-unknown');
    await tap('restore-success');
    await shot('12-restored-room');
    await scenario('offline');
    await tap('apple');
    await tester.ensureVisible(find.byKey(const ValueKey('notice')));
    await tester.pumpAndSettle();
    await shot('13-offline');
    await tap('guest');
    await tap('skip-meeting');
    await shot('14-skipped-meeting');
    await scenario('initializationFailed');
    await shot('15-init-failure');
    await tap('init-retry');
    await shot('16-init-retried');
    await tap('scenarios');
    await tap('large-text');
    await tap('scenarios');
    await tap('reduce-motion');
    await shot('17-large-text-reduce-cover');
    await tester.ensureVisible(find.byKey(const ValueKey('guest')));
    await tester.pumpAndSettle();
    await shot('17b-large-text-actions');
    await tap('guest');
    await tap('skip-meeting');
    await shot('18-large-text-reduce-room');
    await tap('language');
    await tap('locale-en');
    await shot('19-english-large-room');
    await tap('scenarios');
    await tap('large-text');
    await tap('language');
    await tap('locale-zh');
    await scenario('firstUse');
    await tap('apple');
    await tap('auth-new');
    await tap('skip-meeting');
    await shot('20-apple-new-room');
    await scenario('firstUse');
    await tap('google');
    await tap('auth-existing');
    await tap('restore-success');
    await shot('21-google-restored-room');
    debugPrint('ENTRY_RECORD_STOP');
    await pause(1500);
  });
}
