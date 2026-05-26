#!/usr/bin/env bash
#
# 防呆檢查：禁止在 lib/ 直接硬寫顯示單位字串。
#
# 規則：禁止以下「字面上的單位」出現在 Dart 字串字面值中
#   ' kg', ' cm', ' ml', ' lb', ' oz', ' ft', ' in'
# （前置空白避免抓到 cupMl/weightKg/userInput 這種變數名；
#  尾端不接 [a-zA-Z0-9_]，避免抓到 ' kgalore' 之類虛假命中。）
#
# 顯示一律走 UnitFormat.weight/volume/height；
# 輸入一律 UnitConvert.lbToKg/flOzToMl/ftInToCm 轉公制再處理。
#
# 例外（自動跳過）：
#   - lib/utils/units.dart 本身（定義單位的家）
#   - 註解行（// 開頭）
#   - 行尾標 `// units-ok` 的行（顯式豁免）
#   - 不含任何引號的行（不可能是字串字面值）

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$ROOT/lib"

if [ ! -d "$TARGET" ]; then
  echo "check_units: lib/ not found at $TARGET" >&2
  exit 0
fi

# 抓「空白 + 單位 + 非字母數字」並要求該行有引號（字串字面值徵兆）
violations=$(
  grep -RHnE " (kg|cm|ml|lb|oz|ft|in)([^a-zA-Z0-9_]|$)" "$TARGET" \
    --include='*.dart' 2>/dev/null \
  | grep -v '/lib/utils/units.dart:' \
  | grep -v '// *units-ok' \
  | awk -F: '
      {
        code = $0
        # 去掉「檔名:行號:」剩下程式碼本體
        sub(/^[^:]+:[0-9]+:/, "", code)
        trimmed = code
        sub(/^[ \t]+/, "", trimmed)
        # 純註解行跳過
        if (substr(trimmed, 1, 2) == "//") next
        # 沒有任何引號的行不可能是字串字面值
        if (index(code, "\x27") == 0 && index(code, "\"") == 0) next
        print $0
      }
    '
)

if [ -n "$violations" ]; then
  echo "" >&2
  echo "❌ 發現硬寫的單位字串，請改走 UnitFormat / UnitConvert：" >&2
  echo "" >&2
  echo "$violations" >&2
  echo "" >&2
  echo "  → 顯示：UnitFormat.weight(kg, unit) / UnitFormat.volume(ml, unit) / UnitFormat.height(cm, unit)" >&2
  echo "  → 輸入：UnitConvert.lbToKg / flOzToMl / ftInToCm" >&2
  echo "  → 確實要保留（例：log、固定常數）請在行尾加 // units-ok" >&2
  echo "" >&2
  exit 1
fi

exit 0
