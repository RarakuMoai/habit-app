import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/wardrobe_page.dart';
import 'package:habit_app/utils/audio_settings_service.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/wardrobe_catalog.dart';
import 'package:habit_app/utils/wardrobe_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _firstTrack = 'bgm_main';
const _secondTrack = 'bgm_aquamarine';
const _thirdTrack = 'bgm_bed_merry';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpMusicBox(
    WidgetTester tester, {
    bool muted = true,
    List<String> ownedTracks = const [_firstTrack, _secondTrack],
    double height = 2400,
  }) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.bgmOwnedTracks: ownedTracks,
      PrefsKeys.bgmPlaylist: [_firstTrack, _secondTrack],
      PrefsKeys.bgmSelectedTrack: _firstTrack,
    });
    WardrobeStore.reset();
    AudioSettingsService.musicMuted.value = muted;
    addTearDown(() => AudioSettingsService.musicMuted.value = false);
    // 一般 iPhone 寬度；標題右側的完整解鎖文案也必須放得下。
    tester.view.physicalSize = Size(390, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: WardrobePage()));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('音樂盒'));
    await tester.pump(const Duration(milliseconds: 220));
  }

  testWidgets('播放清單排序維持列尺寸與原排版，不插入拖曳圖示', (tester) async {
    await pumpMusicBox(tester);

    expect(
      find.text(
        '已解鎖 ${WardrobeStore.ownedTracks.value.length} / ${trackCatalog.length} 首',
      ),
      findsOneWidget,
    );
    final row = find.byKey(const ValueKey('playlist-row-$_firstTrack'));
    final normalSize = tester.getSize(row);
    expect(normalSize.height, 60);
    expect(find.byIcon(Icons.drag_indicator_rounded), findsNothing);

    await tester.tap(find.descendant(of: row, matching: find.byTooltip('更多')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移動'));
    // 排序抖動不會 settle，以固定幀推進。
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.text('完成排序'), findsOneWidget);
    expect(find.byIcon(Icons.drag_indicator_rounded), findsNothing);
    expect(tester.getSize(row), normalSize);

    await tester.tap(find.text('完成排序'));
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('完成排序'), findsNothing);
  });

  testWidgets('短按曲目顯示 InkWell 漣漪，不留下選取也不切歌', (tester) async {
    await pumpMusicBox(tester);

    final row = find.byKey(const ValueKey('playlist-row-$_secondTrack'));
    final title = find.descendant(
      of: row,
      matching: find.text(trackById(_secondTrack).title),
    );
    final rowInk = find
        .ancestor(of: title, matching: find.byType(InkWell))
        .first;
    final ink = tester.widget<InkWell>(rowInk);
    expect(ink.onTap, isNotNull, reason: '單點必須啟用 InkWell 才會有 Material 漣漪');
    expect(ink.onDoubleTap, isNull, reason: '不能等待雙擊，否則單點回饋會延遲');
    expect(tester.getSize(rowInk).height, 58);
    expect(tester.getSize(rowInk).width, tester.getSize(row).width - 2);

    await tester.tap(title);
    await tester.pumpAndSettle();

    final titleWidget = tester.widget<Text>(title);
    expect(titleWidget.style?.fontWeight, FontWeight.w800);
    final animatedRow = tester.widget<AnimatedContainer>(
      find.descendant(of: row, matching: find.byType(AnimatedContainer)).first,
    );
    final decoration = animatedRow.decoration! as BoxDecoration;
    expect(decoration.border?.top.color, Colors.transparent);
    expect(decoration.color, Colors.white);
    expect(WardrobeStore.currentTrackId.value, _firstTrack);
  });

  testWidgets('詳細資訊仍可從更多選單開啟', (tester) async {
    await pumpMusicBox(tester);

    final row = find.byKey(const ValueKey('playlist-row-$_secondTrack'));
    await tester.tap(find.descendant(of: row, matching: find.byTooltip('更多')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('詳細資訊'));
    await tester.pumpAndSettle();

    final detailSheet = find.byType(BottomSheet);
    expect(detailSheet, findsOneWidget);
    expect(
      find.descendant(
        of: detailSheet,
        matching: find.text(trackById(_secondTrack).title),
      ),
      findsOneWidget,
    );
    expect(WardrobeStore.currentTrackId.value, _firstTrack);
  });

  testWidgets('現在播放音柱只在未靜音時動畫化', (tester) async {
    await pumpMusicBox(tester, muted: false);

    expect(
      find.byKey(const ValueKey('music-playback-equalizer-moving')),
      findsOneWidget,
    );

    AudioSettingsService.musicMuted.value = true;
    await tester.pump();

    expect(
      find.byKey(const ValueKey('music-playback-equalizer-still')),
      findsOneWidget,
    );
  });

  testWidgets('從曲庫加入或移除曲目時，正在看的曲目卡不會被播放清單推動', (tester) async {
    await pumpMusicBox(
      tester,
      ownedTracks: const [_firstTrack, _secondTrack, _thirdTrack],
      height: 844,
    );

    final card = find.byKey(const ValueKey('track-grid-$_thirdTrack'));
    await tester.scrollUntilVisible(
      card,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final beforeAdd = tester.getTopLeft(card).dy;
    await tester.tap(find.descendant(of: card, matching: find.text('加入')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(card).dy, closeTo(beforeAdd, 0.1));

    final beforeRemove = tester.getTopLeft(card).dy;
    await tester.tap(find.descendant(of: card, matching: find.text('移除')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(card).dy, closeTo(beforeRemove, 0.1));
  });
}
