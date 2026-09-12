import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_locale_settings.dart';
import '../utils/app_style.dart';

Future<void> showAppLanguageSheet(
  BuildContext context, {
  AppLocaleSettings? settings,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: AppSurfaces.card,
  showDragHandle: true,
  builder: (_) =>
      _AppLanguageSheet(settings: settings ?? AppLocaleSettings.instance),
);

/// Visible cover control; Settings can open the same sheet from its own row.
class AppLanguageButton extends StatelessWidget {
  const AppLanguageButton({super.key, this.settings});

  final AppLocaleSettings? settings;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    key: const ValueKey('app-language'),
    onPressed: () => showAppLanguageSheet(context, settings: settings),
    icon: const Icon(Icons.language_rounded, size: 18),
    label: Text(AppLocalizations.of(context).appLanguageTitle),
  );
}

class _AppLanguageSheet extends StatefulWidget {
  const _AppLanguageSheet({required this.settings});
  final AppLocaleSettings settings;

  @override
  State<_AppLanguageSheet> createState() => _AppLanguageSheetState();
}

class _AppLanguageSheetState extends State<_AppLanguageSheet> {
  bool _saving = false;
  bool _failed = false;

  Future<void> _select(AppLanguagePreference preference) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.settings.select(preference);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.appLanguageTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: l.commonClose,
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _choice(
              AppLanguagePreference.automatic,
              l.appLanguageAutomatic,
              subtitle: l.appLanguageAutomaticNote,
            ),
            _choice(
              AppLanguagePreference.traditionalChinese,
              l.appLanguageTraditionalChinese,
            ),
            const SizedBox(height: 20),
            Text(
              l.appLanguageIncompleteNote,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppInk.soft, height: 1.6),
            ),
            if (_failed) ...[
              const SizedBox(height: 16),
              Text(
                l.appLanguageSaveError,
                key: const ValueKey('app-language-error'),
                style: const TextStyle(color: AppInk.danger),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _choice(
    AppLanguagePreference value,
    String label, {
    String? subtitle,
  }) {
    final selected = widget.settings.preference == value;
    return ListTile(
      key: ValueKey('app-language-${value.name}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppCardStyle.radius),
      ),
      selected: selected,
      selectedColor: AppPalette.habitInk,
      selectedTileColor: AppPalette.habitLight,
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: selected ? const Icon(Icons.check_rounded) : null,
      enabled: !_saving,
      onTap: () => _select(value),
    );
  }
}
