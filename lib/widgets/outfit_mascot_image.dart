import 'package:flutter/material.dart';

import '../utils/wardrobe_catalog.dart';
import '../utils/wardrobe_store.dart';

/// 報到、問候及桌遊等靜態兔咪插圖，共用衣櫃目前選擇。
/// 原情緒、尺寸、語意與外層演出維持由呼叫端控制。
class OutfitMascotImage extends StatelessWidget {
  final String coreAsset;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final FilterQuality filterQuality;
  final String? semanticLabel;

  const OutfitMascotImage(
    this.coreAsset, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.filterQuality = FilterQuality.medium,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: WardrobeStore.selectedOutfit,
    builder: (_, outfitId, _) => Image.asset(
      skinnedMascotAsset(coreAsset, outfitById(outfitId).skinKey),
      width: width,
      height: height,
      fit: fit,
      filterQuality: filterQuality,
      semanticLabel: semanticLabel,
    ),
  );
}
