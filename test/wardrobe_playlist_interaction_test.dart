import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/wardrobe_page.dart';
import 'package:habit_app/utils/audio_settings_service.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/wardrobe_catalog.dart';
import 'package:habit_app/utils/wardrobe_store.dart';
import 'package:habit_app/widgets/reorder_jiggle.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

const _firstTrack = 'bgm_main';
const _secondTrack = 'bgm_aquamarine';
const _thirdTrack = 'bgm_bed_merry';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpMusicBox(
    WidgetTester tester, {
    bool muted = true,
    List<String> ownedTracks = const [_firstTrack, _secondTrack],
    List<String> playlist = const [_firstTrack, _secondTrack],
    double width = 390,
    double height = 2400,
  }) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.bgmOwnedTracks: ownedTracks,
      PrefsKeys.bgmPlaylist: playlist,
      PrefsKeys.bgmSelectedTrack: playlist.first,
    });
    WardrobeStore.reset();
    AudioSettingsService.musicMuted.value = muted;
    addTearDown(() => AudioSettingsService.musicMuted.value = false);
    // 一般 iPhone 寬度；標題右側的完整解鎖文案也必須放得下。
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(l10nTestApp(home: const WardrobePage()));
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.text('完成排序'), findsOneWidget);
    expect(find.byIcon(Icons.drag_indicator_rounded), findsNothing);
    expect(tester.getSize(row), normalSize);

    await tester.tap(find.byKey(const ValueKey('playlist-sort-done-action')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('完成排序'), findsNothing);
  });

  testWidgets('碰下當幀顯示光暈，短按不留下選取也不切歌', (tester) async {
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
    expect(ink.onTap, isNotNull, reason: '歌曲內容仍需接收單點手勢');
    expect(ink.onDoubleTap, isNotNull, reason: '雙點曲目列必須能開啟詳細資訊');
    expect(tester.getSize(rowInk).height, 48);
    expect(tester.getSize(rowInk).width, lessThan(tester.getSize(row).width));
    expect(
      find.descendant(of: rowInk, matching: find.byTooltip('更多')),
      findsNothing,
      reason: '列內按鈕不能被歌曲內容的雙點辨識器包住',
    );
    expect(
      find.descendant(of: rowInk, matching: find.byTooltip('播放並解除靜音')),
      findsNothing,
      reason: '播放按鈕不能被歌曲內容的雙點辨識器包住',
    );

    final ripple = find.byKey(const ValueKey('playlist-ripple-$_secondTrack'));
    expect(ripple, findsOneWidget);
    final pointerListener = find
        .descendant(of: ripple, matching: find.byType(Listener))
        .first;
    final listener = tester.widget<Listener>(pointerListener);
    expect(listener.onPointerDown, isNotNull);
    expect(listener.onPointerUp, isNotNull);

    final gesture = await tester.startGesture(tester.getCenter(title));
    await tester.pump();
    await gesture.up();
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

  testWidgets('雙點曲目列開啟詳細資訊且不切換歌曲', (tester) async {
    await pumpMusicBox(tester);

    final row = find.byKey(const ValueKey('playlist-row-$_secondTrack'));
    final title = find.descendant(
      of: row,
      matching: find.text(trackById(_secondTrack).title),
    );
    await tester.tap(title);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(title);
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

  testWidgets('加入雙點後長按仍能直接進入拖曳排序', (tester) async {
    await pumpMusicBox(tester);

    final row = find.byKey(const ValueKey('playlist-row-$_secondTrack'));
    final title = find.descendant(
      of: row,
      matching: find.text(trackById(_secondTrack).title),
    );
    final gesture = await tester.startGesture(tester.getCenter(title));
    await tester.pump(kReorderHoldDelay + const Duration(milliseconds: 80));
    await gesture.moveBy(const Offset(0, -34));
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.moveBy(const Offset(0, -34));
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.up();
    // 排序模式會持續抖動，不能 pumpAndSettle。
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.text('完成排序'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('排序模式左側歌曲區可即時拖曳', (tester) async {
    const playlist = [_firstTrack, _secondTrack, _thirdTrack];
    await pumpMusicBox(tester, ownedTracks: playlist, playlist: playlist);

    final firstRow = find.byKey(const ValueKey('playlist-row-$_firstTrack'));
    await tester.tap(
      find.descendant(of: firstRow, matching: find.byTooltip('更多')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('移動'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    final dragArea = find.byKey(
      const ValueKey('playlist-drag-area-$_firstTrack'),
    );
    await tester.timedDrag(
      dragArea,
      const Offset(0, 150),
      const Duration(milliseconds: 600),
    );
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(WardrobeStore.playlist.value.indexOf(_firstTrack), greaterThan(0));
  });

  testWidgets('排序模式只讓封面與歌名拖曳，歌名後方空白可上下捲動', (tester) async {
    final shortestTrack = trackCatalog.firstWhere(
      (track) => track.title == 'Nothing',
    );
    final playlist = [
      shortestTrack.id,
      for (final track in trackCatalog)
        if (track.id != shortestTrack.id) track.id,
    ].take(10).toList();
    await pumpMusicBox(
      tester,
      ownedTracks: playlist,
      playlist: playlist,
      height: 844,
    );

    final firstRow = find.byKey(ValueKey('playlist-row-${playlist.first}'));
    await tester.tap(
      find.descendant(of: firstRow, matching: find.byTooltip('更多')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('移動'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    final dragArea = find.byKey(
      ValueKey('playlist-drag-area-${playlist.first}'),
    );
    final rowRect = tester.getRect(firstRow);
    final dragRect = tester.getRect(dragArea);
    final oldWideAreaRight = rowRect.right - 94;
    expect(
      dragRect.width,
      greaterThanOrEqualTo(112),
      reason: '短歌名仍應保留容易抓取的最低拖曳寬度',
    );
    expect(
      oldWideAreaRight - dragRect.right,
      greaterThan(24),
      reason: '一般寬度下，歌名後方應釋出明確可用的中間滑動區',
    );

    final reorderList = find.byKey(const ValueKey('playlist-reorder-list'));
    final innerScrollable = find
        .descendant(of: reorderList, matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(innerScrollable).position;
    final initialOrder = List<String>.of(WardrobeStore.playlist.value);
    await tester.dragFrom(
      Offset((dragRect.right + oldWideAreaRight) / 2, rowRect.center.dy),
      const Offset(0, -150),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(position.pixels, greaterThan(0), reason: '歌名後方的中間空白應能上下捲動清單');
    expect(
      WardrobeStore.playlist.value,
      initialOrder,
      reason: '從中間空白捲動不能誤觸歌曲重排',
    );
  });

  testWidgets('播放清單到頂或到底後，繼續滑動會接力捲動衣櫃外層', (tester) async {
    final playlist = [for (final track in trackCatalog.take(10)) track.id];
    await pumpMusicBox(
      tester,
      ownedTracks: playlist,
      playlist: playlist,
      height: 844,
    );

    final firstRow = find.byKey(ValueKey('playlist-row-${playlist.first}'));
    await tester.tap(
      find.descendant(of: firstRow, matching: find.byTooltip('更多')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('移動'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    final reorderList = find.byKey(const ValueKey('playlist-reorder-list'));
    final innerScrollable = find
        .descendant(of: reorderList, matching: find.byType(Scrollable))
        .first;
    final innerPosition = tester
        .state<ScrollableState>(innerScrollable)
        .position;
    final outerList = find.byType(ListView).first;
    final outerScrollable = find
        .descendant(of: outerList, matching: find.byType(Scrollable))
        .first;
    final outerPosition = tester
        .state<ScrollableState>(outerScrollable)
        .position;
    final scrollRegionRect = tester.getRect(
      find.byKey(const ValueKey('playlist-scroll-region')),
    );
    final handoffPoint = Offset(
      scrollRegionRect.right - 18,
      scrollRegionRect.center.dy,
    );

    innerPosition.jumpTo(innerPosition.maxScrollExtent);
    await tester.pump();
    final outerBeforeBottomHandoff = outerPosition.pixels;
    await tester.dragFrom(handoffPoint, const Offset(0, -140));
    await tester.pump(const Duration(milliseconds: 100));
    expect(innerPosition.pixels, innerPosition.maxScrollExtent);
    expect(
      outerPosition.pixels,
      greaterThan(outerBeforeBottomHandoff),
      reason: '播放清單到底後繼續往上滑，應接力往下瀏覽外層曲庫',
    );

    innerPosition.jumpTo(innerPosition.minScrollExtent);
    await tester.pump();
    final outerBeforeTopHandoff = outerPosition.pixels;
    expect(outerBeforeTopHandoff, greaterThan(0));
    await tester.dragFrom(handoffPoint, const Offset(0, 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(innerPosition.pixels, innerPosition.minScrollExtent);
    expect(
      outerPosition.pixels,
      lessThan(outerBeforeTopHandoff),
      reason: '播放清單到頂後繼續往下滑，應接力回到外層上方內容',
    );
  });

  testWidgets('播放清單邊界接力保留甩動速度與外層慣性', (tester) async {
    final playlist = [for (final track in trackCatalog.take(10)) track.id];
    await pumpMusicBox(
      tester,
      ownedTracks: playlist,
      playlist: playlist,
      height: 844,
    );

    final firstRow = find.byKey(ValueKey('playlist-row-${playlist.first}'));
    await tester.tap(
      find.descendant(of: firstRow, matching: find.byTooltip('更多')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('移動'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    final reorderList = find.byKey(const ValueKey('playlist-reorder-list'));
    final innerScrollable = find
        .descendant(of: reorderList, matching: find.byType(Scrollable))
        .first;
    final innerPosition = tester
        .state<ScrollableState>(innerScrollable)
        .position;
    final outerList = find.byType(ListView).first;
    final outerScrollable = find
        .descendant(of: outerList, matching: find.byType(Scrollable))
        .first;
    final outerPosition = tester
        .state<ScrollableState>(outerScrollable)
        .position;

    innerPosition.jumpTo(innerPosition.maxScrollExtent);
    outerPosition.jumpTo(outerPosition.minScrollExtent);
    await tester.pump();
    final scrollRegionRect = tester.getRect(
      find.byKey(const ValueKey('playlist-scroll-region')),
    );
    await tester.flingFrom(
      Offset(scrollRegionRect.right - 18, scrollRegionRect.center.dy),
      const Offset(0, -90),
      1600,
    );
    final outerAtFingerUp = outerPosition.pixels;
    expect(
      outerPosition.maxScrollExtent - outerAtFingerUp,
      greaterThan(10),
      reason: '測試必須替離手慣性保留足夠的外層可滑距離',
    );
    // 接力刻意排到內層 ScrollEnd 所在幀完整收尾後才啟動，避免它自己的
    // goBallistic(0) 蓋掉外層速度；先刷新 post-frame callback 與首幀。
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      outerPosition.pixels,
      greaterThan(outerAtFingerUp),
      reason: '手指放開後外層仍應依甩動速度繼續滑行，不能只接位移',
    );
  });

  testWidgets('歌曲過多時完成排序仍固定在畫面內且可直接點擊', (tester) async {
    final longPlaylist = [for (final track in trackCatalog.take(10)) track.id];
    await pumpMusicBox(
      tester,
      ownedTracks: longPlaylist,
      playlist: longPlaylist,
      width: 320,
      height: 844,
    );

    final firstRow = find.byKey(ValueKey('playlist-row-${longPlaylist.first}'));
    await tester.tap(
      find.descendant(of: firstRow, matching: find.byTooltip('更多')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('移動'));
    // 排序模式會持續抖動，不用 pumpAndSettle。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    final doneAction = find.byKey(const ValueKey('playlist-sort-done-action'));
    expect(doneAction, findsOneWidget);
    final doneLabel = tester.widget<Text>(
      find.descendant(of: doneAction, matching: find.text('完成排序')),
    );
    expect(doneLabel.style?.color, Colors.white, reason: '主要完成動作應使用醒目實心樣式');
    final rect = tester.getRect(doneAction);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(tester.view.physicalSize.height));

    final scrollRegion = find.byKey(const ValueKey('playlist-scroll-region'));
    expect(
      tester.getSize(scrollRegion).height,
      lessThan(longPlaylist.length * 60),
      reason: '長清單應在卡片內獨立捲動，不再無限撐長卡片',
    );

    final reorderList = find.byKey(const ValueKey('playlist-reorder-list'));
    final innerScrollable = find
        .descendant(of: reorderList, matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(innerScrollable).position;

    final initialOrder = List<String>.of(WardrobeStore.playlist.value);
    final firstRowRect = tester.getRect(firstRow);
    await tester.dragFrom(
      Offset(firstRowRect.right - 18, firstRowRect.center.dy),
      const Offset(0, -150),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(position.pixels, greaterThan(0), reason: '排序模式的右側空白區應讓使用者捲到後面歌曲');
    expect(WardrobeStore.playlist.value, initialOrder, reason: '在右側捲動不能誤觸歌曲重排');

    position.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 100));
    final secondDragArea = find.byKey(
      ValueKey('playlist-drag-area-${longPlaylist[1]}'),
    );
    final reorderGesture = await tester.startGesture(
      tester.getCenter(secondDragArea),
    );
    await tester.pump(const Duration(milliseconds: 40));
    for (var step = 0; step < 4; step++) {
      await reorderGesture.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(
      find.byKey(const ValueKey('playlist-drag-proxy')),
      findsOneWidget,
      reason: '左側區域應啟動歌曲拖曳代理層',
    );
    await reorderGesture.moveBy(const Offset(0, -60));
    await tester.pump(const Duration(milliseconds: 60));
    await reorderGesture.up();
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      WardrobeStore.playlist.value.first,
      longPlaylist[1],
      reason: '左側封面與歌名區仍要能直接拖曳排序',
    );

    position.jumpTo(position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.getRect(doneAction),
      rect,
      reason: '捲到播放清單最後時，標題列的完成排序不能跟著移動',
    );
    expect(
      find.byKey(ValueKey('playlist-row-${longPlaylist.last}')),
      findsOneWidget,
    );

    await tester.tap(doneAction);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(doneAction, findsNothing);
  });

  testWidgets('列內更多按鈕抬手後立即回應，不等待雙點判定', (tester) async {
    await pumpMusicBox(tester);

    final row = find.byKey(const ValueKey('playlist-row-$_secondTrack'));
    final more = find.descendant(of: row, matching: find.byTooltip('更多'));
    final gesture = await tester.startGesture(tester.getCenter(more));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pump();

    expect(find.text('移動'), findsOneWidget);
    expect(find.text('詳細資訊'), findsOneWidget);
  });

  testWidgets('列內播放按鈕抬手後立即回應，不等待雙點判定', (tester) async {
    await pumpMusicBox(tester);

    final row = find.byKey(const ValueKey('playlist-row-$_firstTrack'));
    final play = find.descendant(of: row, matching: find.byTooltip('播放並解除靜音'));
    expect(AudioSettingsService.musicMuted.value, isTrue);

    final gesture = await tester.startGesture(tester.getCenter(play));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pump();

    expect(AudioSettingsService.musicMuted.value, isFalse);
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
