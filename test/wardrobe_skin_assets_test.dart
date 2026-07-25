// 造型套完整性守門。
//
// 規則：**一套造型＝ core 的完整鏡像**。穿造型時 skinnedMascotAsset() 只做
// 路徑替換（/mascot/core/ → /mascot/<skin>/），少一張圖就會破圖；眨眼與摸頭
// 差分也改成找「同資料夾」的檔案，同樣少一張就沒反應。
//
// 所以每個造型資料夾的檔名清單必須跟 core 一模一樣。這條測試在造型進 repo
// 的當下就會擋下缺漏，不用等到實機穿上去才發現。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/utils/wardrobe_catalog.dart';

void main() {
  final mascotDir = Directory('assets/mascot');

  Set<String> pngNamesIn(Directory dir) => dir
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.endsWith('.png'))
      .toSet();

  test('core 有全部 12 個正式情緒的立繪', () {
    final core = pngNamesIn(Directory('${mascotDir.path}/core'));
    for (final e in MascotEmotion.values) {
      expect(
        core,
        contains('tumi_${e.assetKey}.png'),
        reason: '${e.name} 缺圖；MascotEmotion 是正式狀態的單一真相來源',
      );
    }
  });

  test('每套造型都是 core 的完整鏡像（缺一張就會破圖或差分失效）', () {
    final coreNames = pngNamesIn(Directory('${mascotDir.path}/core'));

    final skinDirs = mascotDir
        .listSync()
        .whereType<Directory>()
        .where((d) {
          final name = d.uri.pathSegments[d.uri.pathSegments.length - 2];
          // ref/ 是描圖參考圖，不是造型
          return name != 'core' && name != 'ref';
        })
        .toList();

    for (final dir in skinDirs) {
      final skin = dir.uri.pathSegments[dir.uri.pathSegments.length - 2];
      final names = pngNamesIn(dir);
      expect(
        names,
        containsAll(coreNames),
        reason:
            '造型「$skin」少了 ${coreNames.difference(names)}。'
            '一套造型必須跟 core 一樣完整，見 docs/pending_assets.md。',
      );
    }
  });

  test('catalog 宣告的 skinKey 都有對應資料夾', () {
    for (final outfit in outfitCatalog) {
      if (outfit.skinKey == 'core') continue;
      expect(
        Directory('${mascotDir.path}/${outfit.skinKey}').existsSync(),
        isTrue,
        reason: '造型「${outfit.name}」宣告了 skinKey=${outfit.skinKey}，但沒有對應資料夾',
      );
    }
  });

  test('穿造型時眨眼與摸頭差分會找同資料夾，不會退回原始造型', () {
    const skinned = 'assets/mascot/spring/tumi_neutral_front.png';
    expect(
      MascotEmotion.blinkAssetForPath(skinned),
      'assets/mascot/spring/tumi_neutral_front_blink.png',
      reason: '穿造型時眨眼要用同一套衣服的閉眼版，不能跳回 core',
    );
    // core 路徑仍然照舊
    expect(
      MascotEmotion.blinkAssetForPath(
        'assets/mascot/core/tumi_neutral_front.png',
      ),
      'assets/mascot/core/tumi_neutral_front_blink.png',
    );
    // 沒有眨眼差分的情緒仍然回 null（timer 照走但跳過）
    expect(
      MascotEmotion.blinkAssetForPath('assets/mascot/spring/tumi_happy.png'),
      isNull,
    );
  });
}
