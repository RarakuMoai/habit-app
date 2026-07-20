import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/wardrobe_page.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/wardrobe_catalog.dart';
import 'package:habit_app/utils/wardrobe_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _firstTrack = 'bgm_main';
const _secondTrack = 'bgm_aquamarine';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpMusicBox(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.bgmOwnedTracks: [_firstTrack, _secondTrack],
      PrefsKeys.bgmPlaylist: [_firstTrack, _secondTrack],
      PrefsKeys.bgmSelectedTrack: _firstTrack,
    });
    WardrobeStore.reset();
    tester.view.physicalSize = const Size(800, 2400);
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

    final row = find.byKey(const ValueKey('playlist-row-$_firstTrack'));
    final normalSize = tester.getSize(row);
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
    await tester.pumpAndSettle();
  });

  testWidgets('短按曲目只留下低存在感臨時標記', (tester) async {
    await pumpMusicBox(tester);

    final row = find.byKey(const ValueKey('playlist-row-$_secondTrack'));
    final title = find.descendant(
      of: row,
      matching: find.text(trackById(_secondTrack).title),
    );
    await tester.tap(title);
    await tester.pump(const Duration(milliseconds: 180));

    final titleWidget = tester.widget<Text>(title);
    expect(titleWidget.style?.fontWeight, FontWeight.w800);
    final animatedRow = tester.widget<AnimatedContainer>(
      find.descendant(of: row, matching: find.byType(AnimatedContainer)).first,
    );
    final decoration = animatedRow.decoration! as BoxDecoration;
    expect(decoration.border?.top.color, Colors.transparent);
    expect(decoration.color, isNot(Colors.white));
  });
}
