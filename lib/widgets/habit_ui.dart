// 習慣清單共用 UI 元件（首頁與家庭頁共用）：
// 區段標題（圖示底框 + 名稱 + 完成計數膠囊）、每週習慣 ± 調整鈕
import 'package:flutter/material.dart';

import '../utils/app_style.dart';

// 區段標題：圖示底框 + 名稱 + 計數膠囊，全完成時轉綠＋勾。
// done/total 不傳就不顯示膠囊（給沒有完成概念的區段用，例如體重頁）。
class HabitSectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final int? done;
  final int? total;

  const HabitSectionHeader({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    this.done,
    this.total,
  });

  @override
  Widget build(BuildContext context) {
    final hasCount = done != null && total != null;
    final allDone = hasCount && total! > 0 && done == total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 8, left: 2),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.8,
            ),
          ),
          if (hasCount) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: allDone
                    ? Colors.green.shade50
                    : color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$done / $total',
                style: AppType.digits(
                  color: allDone ? Colors.green.shade700 : color,
                ),
              ),
            ),
          ],
          if (allDone) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.check_circle_rounded,
              size: 14,
              color: Colors.green.shade400,
            ),
          ],
          // 右側漸隱細線：把標題行視覺上「收」到右緣，留出呼吸感
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    color.withValues(alpha: 0.25),
                    color.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 每週習慣的 ⊖ / ⊕ 調整鈕（onTap 為 null 時呈灰色停用）
class WeeklyAdjustBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;

  const WeeklyAdjustBtn({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    final active = onTap != null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? Colors.indigo.shade50 : AppSurfaces.fill,
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          splashColor: Colors.indigo.withValues(alpha: 0.18),
          highlightColor: Colors.indigo.withValues(alpha: 0.08),
          onTap: onTap,
          child: Icon(
            icon,
            size: size * 0.53,
            color: active ? Colors.indigo.shade500 : AppInk.iconFaint,
          ),
        ),
      ),
    );
  }
}
