import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/water_page.dart';
import 'package:habit_app/utils/sfx_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('一般加水播泡泡，跨過今日目標改播完成音', () {
    expect(
      waterAddFeedbackCue(wasReached: false, isReached: false),
      SfxCue.waterAdd,
    );
    expect(
      waterAddFeedbackCue(wasReached: false, isReached: true),
      SfxCue.waterGoal,
    );
    expect(
      waterAddFeedbackCue(wasReached: true, isReached: true),
      SfxCue.waterAdd,
    );
  });

  test('喝水泡泡與達標音已收入 asset bundle', () async {
    for (final cue in [SfxCue.waterAdd, SfxCue.waterGoal]) {
      final data = await rootBundle.load(cue.assetPath);
      expect(data.lengthInBytes, greaterThan(1000), reason: cue.assetPath);
    }
  });
}
