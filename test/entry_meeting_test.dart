import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/utils/app_theme.dart';
import 'package:habit_app/utils/onboarding_story.dart';
import 'package:habit_app/widgets/entry_controls.dart';
import 'package:habit_app/widgets/entry_meeting.dart';

void main() {
  for (final accessibleNavigation in [false, true]) {
    testWidgets(
      'reduced meeting loads taller dialogue without layout animation '
      '(accessibleNavigation=$accessibleNavigation)',
      (tester) async {
        tester.view.physicalSize = const Size(375, 667);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final step = ValueNotifier<int>(0);
        addTearDown(step.dispose);
        var nextCalls = 0;
        var skipCalls = 0;
        final hello = onboardingStoryScenes[1].text.resolve('zh');
        final together = onboardingStoryScenes.last.text.resolve('zh');
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            locale: const Locale('zh', 'TW'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                // Exercise both supported ways the meeting suppresses motion.
                disableAnimations: !accessibleNavigation,
                accessibleNavigation: accessibleNavigation,
                textScaler: TextScaler.linear(1.3),
                padding: const EdgeInsets.only(top: 20),
              ),
              child: child!,
            ),
            home: ValueListenableBuilder<int>(
              valueListenable: step,
              builder: (context, value, _) => EntryMeeting(
                text: value == 2 ? together : hello,
                last: value == 2,
                ready: value > 0,
                failed: false,
                busy: false,
                onNext: () {
                  nextCalls++;
                  step.value = 2;
                },
                onSkip: () => skipCalls++,
                onRetry: () =>
                    fail('No retry is expected in a successful load'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final dialogue = find.byKey(const ValueKey('entry-meeting-hello'));
        final primary = find.byKey(const ValueKey('onboarding-primary'));
        final skip = find.byKey(const ValueKey('onboarding-skip'));
        final loadingHeight = tester.getSize(dialogue).height;
        expect(tester.widget<EntryPrimaryAction>(primary).onPressed, isNull);
        expect(tester.widget<TextButton>(skip).onPressed, isNull);
        expect(find.byType(AnimatedSize), findsNothing);
        expect(tester.takeException(), isNull);

        // Rebuild the same constrained meeting, as the real async name load
        // replaces a one-line loading label with the approved hello dialogue.
        step.value = 1;
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(tester.getSize(dialogue).height, greaterThan(loadingHeight));
        expect(find.text(hello), findsOneWidget);
        expect(find.byType(AnimatedSize), findsNothing);
        expect(skip.hitTestable(), findsOneWidget);
        expect(primary.hitTestable(), findsOneWidget);
        await tester.tap(skip);
        await tester.pump();
        expect(skipCalls, 1);
        await tester.tap(primary);
        await tester.pumpAndSettle();
        expect(nextCalls, 1);
        expect(find.text(together), findsOneWidget);
        expect(find.text('走進我們的日常'), findsOneWidget);
        expect(find.byType(AnimatedSize), findsNothing);
        expect(tester.takeException(), isNull);
        expect(primary.hitTestable(), findsOneWidget);
        await tester.tap(primary);
        await tester.pumpAndSettle();
        expect(nextCalls, 2);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
