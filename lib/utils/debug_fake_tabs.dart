import 'package:flutter/material.dart';

class DebugFakeTabSpec {
  final String id;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;

  const DebugFakeTabSpec({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

const debugFakeTabSpecs = [
  // 記帳：決定不做（情緒分開原則，見 docs/roadmap.md §1/§9），不列入預覽。
  DebugFakeTabSpec(
    id: 'shop',
    label: '商城',
    subtitle: '道具、背景與裝飾',
    icon: Icons.storefront_rounded,
    color: Color(0xFFD58B32),
  ),
  DebugFakeTabSpec(
    id: 'quests',
    label: '任務',
    subtitle: '短期挑戰與活動',
    icon: Icons.flag_rounded,
    color: Color(0xFF5A88D8),
  ),
  DebugFakeTabSpec(
    id: 'stats',
    label: '統計',
    subtitle: '習慣趨勢與週報',
    icon: Icons.insights_rounded,
    color: Color(0xFF7C6BCF),
  ),
];
