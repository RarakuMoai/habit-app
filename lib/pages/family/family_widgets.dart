// 育兒模式共用小元件：空狀態邀請、持續時間對話框、調整按鈕、頻率 Chip
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/app_feedback.dart';
import '../../utils/app_style.dart';

class FamilyEmptyInvite extends StatelessWidget {
  final Color accent;
  final VoidCallback onAdd;
  final String title;
  final String subtitle;
  final String buttonLabel;

  const FamilyEmptyInvite({
    super.key,
    required this.accent,
    required this.onAdd,
    this.title = '先新增一位小孩',
    this.subtitle = '兔咪會幫你們記小任務和積分。',
    this.buttonLabel = '新增小孩',
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 390),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0.96),
              const Color(0xFFFFF3E6).withValues(alpha: 0.94),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.16)),
          boxShadow: AppShadows.flat,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _FamilyEmptyIcon(accent: accent),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: AppInk.strong,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                            color: AppInk.soft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: Text(buttonLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(44),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FamilyEmptyIcon extends StatelessWidget {
  final Color accent;
  const _FamilyEmptyIcon({required this.accent});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.child_care_rounded, size: 31, color: accent),
            ),
          ),
          Positioned(
            right: -4,
            top: -4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E3),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.add_rounded,
                  size: 14,
                  color: const Color(0xFFE5A327),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 持續時間（分鐘）輸入對話框
Future<int?> showFamilyMinutesDialog(BuildContext context, int current) async {
  final ctrl = TextEditingController(text: current > 0 ? '$current' : '');
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('持續時間'),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      content: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        autofocus: true,
        decoration: InputDecoration(
          suffixText: '分鐘',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
        onSubmitted: (v) {
          final n = int.tryParse(v.trim());
          if (n != null && n > 0) Navigator.pop(ctx, n.clamp(1, 999));
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('取消', style: TextStyle(color: AppInk.soft)),
        ),
        TextButton(
          onPressed: () {
            final n = int.tryParse(ctrl.text.trim());
            if (n != null && n > 0) Navigator.pop(ctx, n.clamp(1, 999));
          },
          child: const Text('確定'),
        ),
      ],
    ),
  );
}

// 調整按鈕（＋ / −）
class AdjustBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const AdjustBtn({
    super.key,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: enabled ? Colors.white : AppSurfaces.fill,
        border: Border.all(
          color: enabled ? Colors.orange.shade300 : AppSurfaces.divider,
          width: 1.5,
        ),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: Colors.orange.withValues(alpha: 0.15),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          splashColor: Colors.orange.withValues(alpha: 0.18),
          highlightColor: Colors.orange.withValues(alpha: 0.08),
          onTap: enabled ? onTap : null,
          child: Icon(
            icon,
            size: 16,
            color: enabled ? Colors.orange.shade700 : AppInk.faint,
          ),
        ),
      ),
    );
  }
}

// 頻率切換 Chip（每日 / 每週）
class FreqChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const FreqChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: selected ? Colors.orange : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? Colors.orange : AppSurfaces.divider,
          width: 1.5,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: Colors.orange.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          splashColor: Colors.orange.withValues(alpha: 0.18),
          highlightColor: Colors.orange.withValues(alpha: 0.08),
          onTap: () {
            playHaptic(HapticLevel.selection);
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppInk.soft,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
