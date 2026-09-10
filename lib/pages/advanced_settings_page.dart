import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_style.dart';
import '../widgets/settings_ui.dart';
import 'data_deletion_page.dart';

class AdvancedSettingsPage extends StatelessWidget {
  const AdvancedSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsSectionAdvanced),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppSurfaces.fill,
              borderRadius: BorderRadius.circular(AppCardStyle.radius),
              border: Border.all(color: AppSurfaces.divider),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppInk.soft.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    color: AppInk.soft,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.advancedInfoTitle,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF5F4331),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.advancedInfoBody,
                        style: const TextStyle(
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
          const SizedBox(height: 24),
          SettingsTileCard(
            icon: Icons.delete_forever_outlined,
            iconColor: AppInk.danger,
            title: l10n.dataDeletionTitle,
            subtitle: l10n.dataDeletionEntrySubtitle,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DataDeletionPage(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
