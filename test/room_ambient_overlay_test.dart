import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/home/room_ambient_overlay.dart';

void main() {
  group('首頁四時段窗光可視強度', () {
    test('早晨與白天固定場景不會退化成肉眼不可見的微光', () {
      expect(homeSunShaftStrength(7.5), greaterThanOrEqualTo(0.25));
      expect(homeSunShaftStrength(13.0), greaterThanOrEqualTo(0.35));
    });

    test('黃昏保留明確斜光，夜晚保留冷色月光', () {
      expect(homeDuskIntensity(17.8), greaterThanOrEqualTo(0.95));
      expect(homeMoonShaftStrength(23.0), greaterThanOrEqualTo(0.60));
    });

    test('沒有日光的時間不誤畫太陽光束', () {
      expect(homeSunShaftStrength(5.5), 0);
      expect(homeSunShaftStrength(17.8), 0);
      expect(homeSunShaftStrength(23.0), 0);
    });
  });
}
