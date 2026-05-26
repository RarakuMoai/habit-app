# Claude Code 任務：修正喝水頁水瓶與水位對齊

## 目標

修正 `lib/pages/water_page.dart` 中水位動畫與水瓶圖片無法完美吻合的問題。

目前水位是用類似 `size.width * 0.xxx` 的 magic number 估算瓶身內部區域。這種方式在不同裝置、不同圖片比例、不同顯示尺寸下容易位移，不適合長期使用。

請改成更穩定的分層或遮罩架構。

## 核心要求

請不要繼續靠手調 magic number 對齊水位。

請改成：

```text
固定 AspectRatio 的水瓶元件
+ 所有瓶身圖層與水位共用同一個 Stack 座標系
+ 水位只在明確定義的瓶內區域顯示
```

## 推薦方案 A：分層瓶身

最佳架構：

```text
assets/images/water/bottle_back.png
assets/images/water/bottle_front.png
```

Flutter 結構：

```dart
AspectRatio(
  aspectRatio: bottleWidth / bottleHeight,
  child: Stack(
    fit: StackFit.expand,
    children: [
      Image.asset('assets/images/water/bottle_back.png', fit: BoxFit.contain),
      CustomPaint(painter: WaterFillPainter(progress)),
      Image.asset('assets/images/water/bottle_front.png', fit: BoxFit.contain),
    ],
  ),
)
```

重點：

- `bottle_back.png` 和 `bottle_front.png` 必須同尺寸。
- 水位 painter 使用同一個 Stack 的座標系。
- 水位不要放在獨立尺寸 widget 中。
- 不要使用 `BoxFit.cover`。
- 不要讓不同層使用不同尺寸或 padding。

## 推薦方案 B：水位遮罩

如果無法取得乾淨的 back/front 分層素材，請改用 mask：

```text
assets/images/water/bottle_overlay.png
assets/images/water/bottle_water_mask.png
```

`bottle_water_mask.png` 規則：

- 與瓶身圖同尺寸
- 白色區域代表水可以顯示
- 黑色/透明區域代表水不可顯示

Flutter 結構可使用：

- `ShaderMask`
- `ClipPath`
- 或自訂 painter 讀取 mask 後限制水位區域

如果讀取圖片 mask 太複雜，請至少建立一個固定比例的 `CustomClipper<Path>`，且該 clipper 必須根據瓶身素材比例設計，而不是根據裝置亂猜。

## 目前可用素材

目前專案已有：

```text
assets/images/water/bottle_overlay.png
assets/images/water/bottle_src.png
```

實際 App 目前使用：

```text
assets/images/water/bottle_overlay.png
```

`bottle_src.png` 是綠幕原圖，可視情況刪除或保留。若需要重新生成/替換素材，請不要直接覆蓋 `bottle_overlay.png`，先建立新檔名：

```text
bottle_front.png
bottle_back.png
bottle_water_mask.png
```

## 如果沒有新素材怎麼辦

若暫時沒有分層素材，請先做工程結構修正：

1. 建立 `_LayeredWaterBottle` 元件。
2. 使用固定 `AspectRatio`，例如根據圖片比例 `1024 / 1536`。
3. 所有圖層與水位都放在同一個 `StackFit.expand` 中。
4. 水位 clip 區域只依照這個固定座標系計算。
5. 把所有水位比例集中在一個地方，例如：

```dart
class _BottleGeometry {
  static const bodyLeft = 0.24;
  static const bodyTop = 0.34;
  static const bodyWidth = 0.52;
  static const bodyHeight = 0.50;
}
```

這不是最完美，但比散落 magic number 穩定。

## 驗收標準

請完成後確認：

- 水位在 0%、25%、50%、75%、100% 都位於瓶身內。
- 水位不會蓋到瓶蓋、提繩、瓶外區域。
- 換不同手機寬度時，水位仍與瓶身對齊。
- 水瓶元件使用固定 aspect ratio。
- `flutter analyze` 通過。
- `flutter test` 通過。
- 不破壞喝水設定與首頁習慣連動。

## 不要做的事

- 不要繼續用零散 magic number 到處試。
- 不要為了對齊而改整頁 layout。
- 不要改資料 key。
- 不要移除目前 ml 設定功能。
- 不要改首頁、家庭頁、體重頁。

## 補充說明

這次重點不是把某一台手機「看起來差不多」，而是建立一個之後換素材、換裝置也不容易跑掉的水瓶架構。

若需要取捨，優先順序是：

1. 對齊穩定
2. 水位可見
3. 視覺自然
4. 動畫流暢
