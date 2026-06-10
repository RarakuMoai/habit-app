import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/parent_pin.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('未設定 PIN：hasPin false、verify false', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    expect(await ParentPin.hasPin(prefs), isFalse);
    expect(await ParentPin.verify(prefs, '1234'), isFalse);
  });

  test('save 後只存雜湊，verify 正確/錯誤 PIN', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await ParentPin.save(prefs, '1234');

    expect(prefs.getString('parent_pin'), isNull);
    final stored = prefs.getString('parent_pin_hash');
    expect(stored, isNotNull);
    expect(stored, isNot(contains('1234')));
    expect(stored, startsWith('v1:'));

    expect(await ParentPin.hasPin(prefs), isTrue);
    expect(await ParentPin.verify(prefs, '1234'), isTrue);
    expect(await ParentPin.verify(prefs, '0000'), isFalse);
  });

  test('舊版明文 parent_pin 自動遷移成雜湊並刪除明文', () async {
    SharedPreferences.setMockInitialValues({'parent_pin': '5678'});
    final prefs = await SharedPreferences.getInstance();

    expect(await ParentPin.hasPin(prefs), isTrue);
    expect(prefs.getString('parent_pin'), isNull);
    expect(prefs.getString('parent_pin_hash'), isNotNull);
    expect(await ParentPin.verify(prefs, '5678'), isTrue);
    expect(await ParentPin.verify(prefs, '1234'), isFalse);
  });

  test('雜湊紀錄損毀時 verify 回傳 false 不丟例外', () async {
    SharedPreferences.setMockInitialValues({'parent_pin_hash': 'garbage'});
    final prefs = await SharedPreferences.getInstance();
    expect(await ParentPin.verify(prefs, '1234'), isFalse);
  });

  test('同一 PIN 兩次 save 產生不同鹽與雜湊', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await ParentPin.save(prefs, '1234');
    final first = prefs.getString('parent_pin_hash');
    await ParentPin.save(prefs, '1234');
    expect(prefs.getString('parent_pin_hash'), isNot(equals(first)));
    expect(await ParentPin.verify(prefs, '1234'), isTrue);
  });
}
