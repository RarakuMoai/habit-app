import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/utils/app_theme.dart';
import 'package:habit_app/widgets/app_touch_sparkles.dart';
import 'package:habit_app/widgets/entry_controls.dart';
import 'package:habit_app/widgets/entry_loading_scene.dart';

Widget _app(Widget child, {bool reduced = false, double scale = 1}) =>
    MaterialApp(
      theme: buildAppTheme(),
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduced,
          textScaler: TextScaler.linear(scale),
        ),
        child: AppTouchSparkles(child: child!),
      ),
      home: child,
    );

class _MountProbe extends StatefulWidget {
  const _MountProbe(this.onMount);
  final VoidCallback onMount;
  @override
  State<_MountProbe> createState() => _MountProbeState();
}

class _MountProbeState extends State<_MountProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('destination'));
}

void main() {
  testWidgets('blank touches bloom; buttons and scrolling retain ownership', (
    tester,
  ) async {
    var taps = 0;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Column(
            children: [
              TextButton(onPressed: () => taps++, child: const Text('action')),
              const SizedBox(height: 100),
              Expanded(
                child: ListView.builder(
                  controller: scroll,
                  itemCount: 30,
                  itemBuilder: (_, i) =>
                      SizedBox(height: 60, child: Text('row $i')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final state = tester.state<AppTouchSparklesState>(
      find.byType(AppTouchSparkles),
    );
    await tester.tapAt(const Offset(250, 90));
    expect(state.activeBurstCount, 1);
    expect(taps, 0);
    await tester.tap(find.text('action'));
    expect(taps, 1);
    expect(state.activeBurstCount, 2);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(state.activeBurstCount, 0);
    expect(state.motionRunning, isFalse);
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    expect(scroll.offset, greaterThan(100));
    expect(state.activeBurstCount, 0);
    await tester.pumpAndSettle();
  });

  testWidgets('cancelled drag, long press and pointer cancel do not bloom', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const Scaffold()));
    final state = tester.state<AppTouchSparklesState>(
      find.byType(AppTouchSparkles),
    );
    final drag = await tester.startGesture(const Offset(100, 100));
    await drag.moveBy(const Offset(25, 0));
    await drag.moveBy(const Offset(-25, 0));
    await drag.up();
    final long = await tester.startGesture(const Offset(100, 100));
    await long.up(timeStamp: const Duration(seconds: 1));
    final cancel = await tester.startGesture(const Offset(100, 100));
    await cancel.cancel();
    expect(state.activeBurstCount, 0);
    expect(state.motionRunning, isFalse);
  });

  testWidgets(
    'touch effects are bounded, clear on background and respect Reduce Motion',
    (tester) async {
      await tester.pumpWidget(_app(const Scaffold(), reduced: true));
      final state = tester.state<AppTouchSparklesState>(
        find.byType(AppTouchSparkles),
      );
      for (var i = 0; i < 12; i++) {
        await tester.tapAt(const Offset(100, 100));
      }
      expect(state.activeBurstCount, 8);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(state.activeBurstCount, 0);
      await tester.tapAt(const Offset(100, 100));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(state.activeBurstCount, 0);
      expect(state.motionRunning, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );

  for (final reduced in [false, true]) {
    testWidgets('entry curtain mounts destination once, reduced=$reduced', (
      tester,
    ) async {
      var mounts = 0;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                  EntryPageRoute<void>(
                    builder: (_) => _MountProbe(() => mounts++),
                  ),
                ),
                child: const Text('enter'),
              ),
            ),
          ),
          reduced: reduced,
        ),
      );
      await tester.tap(find.text('enter'));
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('destination'), findsOneWidget);
      expect(
        mounts,
        1,
        reason:
            'Transition must not remount the real room or restart its data/rewards.',
      );
      expect(find.byType(EntryLoadingScene), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [
    const Size(320, 568),
    const Size(375, 667),
    const Size(430, 932),
  ]) {
    testWidgets(
      'preparation fits $size, safe areas and 1.3 text; progress is not time-driven',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _app(
            const Scaffold(
              body: EntryLoadingScene(
                label: '正在準備房間…',
                detail: '房間與兔咪素材已隨 App 安裝，正在準備。',
                preparingRoom: true,
                progress: .4,
              ),
            ),
            scale: 1.3,
          ),
        );
        await tester.pump(const Duration(seconds: 8));
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .value,
          .4,
        );
        expect(find.text('正在準備房間…').hitTestable(), findsOneWidget);
        final loader = tester.getRect(find.text('載入中'));
        expect(loader.bottom, lessThanOrEqualTo(size.height - 34 - 24));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('wallpaper freezes in background, offstage and Reduce Motion', (
    tester,
  ) async {
    Widget scene({bool enabled = true, bool reduced = false}) => _app(
      Scaffold(
        body: TickerMode(
          enabled: enabled,
          child: const EntryLoadingScene(label: '載入中', preparingRoom: true),
        ),
      ),
      reduced: reduced,
    );
    await tester.pumpWidget(scene());
    final state = tester.state<EntryLoadingSceneState>(
      find.byType(EntryLoadingScene),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.motionSeconds, greaterThan(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(state.motionRunning, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(state.motionRunning, isTrue);
    await tester.pumpWidget(scene(enabled: false));
    expect(state.motionRunning, isFalse);
    await tester.pumpWidget(scene(reduced: true));
    expect(state.motionRunning, isFalse);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('startup status appears only after the real-wait threshold', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: EntryLoadingScene(
            label: '正在準備入口',
            statusDelay: EntrySceneMotion.loadingStatusDelay,
          ),
        ),
      ),
    );
    expect(find.text('載入中'), findsNothing);
    await tester.pump(
      EntrySceneMotion.loadingStatusDelay - const Duration(milliseconds: 1),
    );
    expect(find.text('載入中'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('載入中'), findsOneWidget);
  });

  test('brand entrance completes one visible motion beat', () {
    expect(EntrySceneMotion.entrance, const Duration(milliseconds: 1320));
    expect(EntrySceneMotion.paper, const Color(0xFFFFF1E5));
    expect(EntrySceneMotion.motifOpacity, greaterThanOrEqualTo(.45));
    expect(entryWallpaperMotifs, const [
      EntryMotif.bunny,
      EntryMotif.flower,
      EntryMotif.leaf,
    ]);
    expect(entryWallpaperMotifs, isNot(contains(EntryMotif.sparkle)));
    expect(EntrySceneMotion.motifFloat, greaterThan(2));
    expect(EntrySceneMotion.leafSwayRadians, greaterThan(.05));
    expect(
      EntrySceneMotion.entrance,
      greaterThan(EntrySceneMotion.loadingStatusDelay),
    );
  });

  test(
    'paper reveal fully covers at start and leaves no clipped corner at end',
    () {
      for (final size in [const Size(320, 568), const Size(430, 932)]) {
        final start = EntryPaperRevealClipper(0).getClip(size);
        final end = EntryPaperRevealClipper(1).getClip(size);
        for (final p in [
          const Offset(1, 1),
          Offset(size.width - 1, 1),
          Offset(1, size.height - 1),
          Offset(size.width - 1, size.height - 1),
          size.center(Offset.zero),
        ]) {
          expect(start.contains(p), isTrue);
          expect(end.contains(p), isFalse);
        }
      }
    },
  );
}
