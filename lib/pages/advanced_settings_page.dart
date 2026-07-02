import 'package:flutter/material.dart';

import '../utils/app_style.dart';
import 'data_deletion_page.dart';

class AdvancedSettingsPage extends StatelessWidget {
  const AdvancedSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('進階'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8ED),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFFD7A8)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    color: Colors.orange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '較少使用的設定',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF5F4331),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '這裡放影響範圍比較大的操作，進入前可以先確認自己真的需要。',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: AppInk.soft,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppSurfaces.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppInk.danger.withValues(alpha: 0.20)),
              boxShadow: AppShadows.flat,
            ),
            child: ListTile(
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppInk.danger.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_forever_outlined,
                  color: AppInk.danger,
                  size: 20,
                ),
              ),
              title: const Text(
                '資料刪除',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppInk.strong,
                ),
              ),
              subtitle: const Text(
                '清除體重、喝水、家庭資料，或重置全部',
                style: TextStyle(fontSize: 12, color: AppInk.soft),
              ),
              trailing: const Icon(Icons.chevron_right, color: AppInk.iconFaint),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DataDeletionPage(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
