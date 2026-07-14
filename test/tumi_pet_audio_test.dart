import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/sfx_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('摸頭音只保留最前方的短毛茸循環素材', () async {
    final data = await rootBundle.load(SfxCue.tumiPet.assetPath);

    expect(
      data.lengthInBytes,
      inInclusiveRange(100000, 160000),
      reason: '避免把原始素材後段的違和聲重新帶回循環',
    );
  });
}
