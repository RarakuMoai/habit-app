import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../utils/account_service.dart';
import '../utils/app_entry_intent.dart';
import '../utils/app_restart.dart';
import '../utils/app_style.dart';
import '../utils/backup_archive.dart';
import '../utils/backup_restore.dart';
import '../utils/logical_day_coordinator.dart';
import '../utils/storage_snapshot_gate.dart';
import '../widgets/app_waiting.dart';
import '../widgets/settings_ui.dart';

class AccountBackupPage extends StatefulWidget {
  const AccountBackupPage({
    super.key,
    this.atEntry = false,
    this.offerContinue = false,
  });
  final bool atEntry;
  final bool offerContinue;
  @override
  State<AccountBackupPage> createState() => _AccountBackupPageState();
}

class _AccountBackupPageState extends State<AccountBackupPage> {
  final _account = AccountService.instance;
  bool _working = false;
  String? _notice;
  bool _error = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_working || _account.busy) return;
    setState(() {
      _working = true;
      _notice = null;
      _error = false;
    });
    try {
      await action();
    } on FormatException {
      if (mounted) {
        setState(() {
          _notice = AppLocalizations.of(context).backupInvalid;
          _error = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _notice = AppLocalizations.of(context).accountError;
          _error = true;
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<BackupArchive> _capture() => StorageSnapshotGate.snapshot(
    () => LogicalDayCoordinator.instance.synchronizeStorage(() async {
      final prefs = await SharedPreferences.getInstance();
      return BackupArchive.create(prefs);
    }),
  );

  void _accountResult(bool success, {String? notice}) {
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    setState(() {
      _error =
          !success &&
          _account.errorCode != 'cancelled' &&
          _account.errorCode != 'backup-pending';
      _notice = success
          ? notice
          : _account.errorCode == 'cancelled'
          ? null
          : _account.errorCode == 'backup-pending'
          ? l.accountBackupPending
          : l.accountError;
    });
  }

  Future<bool> _confirm(String title, String body, String action) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(AppLocalizations.of(context).commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _export() async {
    final archive = await _capture();
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final date = DateFormat(
      'yyyyMMdd-HHmm',
    ).format(archive.createdAt.toLocal());
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(archive.encode())),
            mimeType: 'application/json',
            name: 'tumi-backup-$date.json',
          ),
        ],
        fileNameOverrides: ['tumi-backup-$date.json'],
        title: l.backupExport,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
    // A completed share sheet is not proof that a file was saved to Files.
  }

  Future<void> _import() async {
    const types = XTypeGroup(
      label: 'Tumi backup',
      extensions: ['json'],
      uniformTypeIdentifiers: ['public.json'],
    );
    final file = await openFile(acceptedTypeGroups: [types]);
    if (file == null) return;
    if (await file.length() > BackupArchive.maxBytes) {
      throw const FormatException('Too large');
    }
    final archive = BackupArchive.decode(await file.readAsString());
    await _restore(archive);
  }

  Future<void> _restore(
    BackupArchive archive, {
    int? revision,
    String? uid,
  }) async {
    if (!widget.atEntry || !mounted) return;
    final l = AppLocalizations.of(context);
    final saved = DateFormat.yMd().add_Hm().format(archive.createdAt.toLocal());
    if (!await _confirm(
      l.backupRestoreTitle,
      '${l.accountSavedOn}: $saved\n\n${l.backupRestoreBody}',
      l.backupRestoreConfirm,
    )) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await BackupRestore(prefs: prefs).stage(archive);
    if (!mounted) return;
    AppEntryIntent.restoringUid = uid;
    AppEntryIntent.restoringRevision = revision;
    RootRestart.restart(context);
  }

  Future<void> _cloudRestore() async {
    final saved = _account.latestBackup;
    if (saved == null) return;
    await _restore(
      BackupArchive.decode(saved.encodedArchive),
      revision: saved.revision,
      uid: _account.user?.uid,
    );
  }

  Future<void> _backup({bool replace = false}) async {
    final l = AppLocalizations.of(context);
    if (replace &&
        !await _confirm(
          l.accountReplaceCloudTitle,
          l.accountReplaceCloudBody,
          l.accountKeepLocal,
        )) {
      return;
    }
    final archive = await _capture();
    final result = replace
        ? await _account.keepLocal(archive.encode())
        : await _account.backupNow(archive.encode());
    _accountResult(result, notice: l.accountBackupDone);
  }

  Widget _provider(AccountProvider provider, bool busy, {bool link = false}) {
    final l = AppLocalizations.of(context);
    final apple = provider == AccountProvider.apple;
    final enabled = _account.availableProviders.contains(provider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedButton(
        key: ValueKey('account-${provider.name}'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 54),
          backgroundColor: AppSurfaces.card,
          foregroundColor: AppInk.strong,
          side: BorderSide(color: AppInk.faint.withValues(alpha: .6)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: busy || !enabled
            ? null
            : () => _run(() async {
                _accountResult(
                  link
                      ? await _account.linkProvider(provider)
                      : await _account.signIn(provider),
                );
              }),
        child: Row(
          children: [
            if (apple)
              const Icon(Icons.apple, size: 23)
            else
              Image.asset(
                'assets/icon/ui/google_sign_in.png',
                width: 22,
                height: 22,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.account_circle_outlined, size: 22),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                apple ? l.accountApple : l.accountGoogle,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 34),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _account,
      builder: (context, _) {
        final busy = _working || _account.busy;
        final user = _account.user;
        final hasCloud = user != null;
        final pending = _account.errorCode == 'backup-pending';
        final notice = pending ? l.accountBackupPending : _notice;
        return PopScope(
          canPop: !busy,
          child: Scaffold(
            appBar: AppBar(title: Text(l.accountTitle)),
            body: Stack(
              children: [
                AbsorbPointer(
                  absorbing: busy,
                  child: ListView(
                    key: const ValueKey('account-backup-list'),
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                    children: [
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(22),
                          decoration: const BoxDecoration(
                            color: AppPalette.habitLight,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.bookmark_added_outlined,
                            size: 36,
                            color: AppPalette.habitInk,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        hasCloud
                            ? (user.displayName ?? l.accountLinked)
                            : l.entryAccountNote,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        hasCloud
                            ? (user.email ?? l.accountLinked)
                            : l.entryGuestNote,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppInk.soft, height: 1.6),
                      ),
                      const SizedBox(height: 28),
                      if (!hasCloud) ...[
                        _provider(AccountProvider.apple, busy),
                        _provider(AccountProvider.google, busy),
                        if (!_account.configured)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 12),
                            child: Text(
                              l.accountUnavailable,
                              style: const TextStyle(
                                color: AppInk.soft,
                                height: 1.6,
                              ),
                            ),
                          ),
                      ],
                      if (widget.offerContinue) ...[
                        TextButton(
                          key: const ValueKey('account-continue'),
                          onPressed: () => Navigator.of(context).pop(true),
                          child: Text(
                            hasCloud ? l.accountContinue : l.entryGuest,
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (notice != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Text(
                            notice,
                            key: const ValueKey('account-notice'),
                            style: TextStyle(
                              color: _error && !pending
                                  ? AppInk.danger
                                  : AppPalette.habitInk,
                              height: 1.6,
                            ),
                          ),
                        ),
                      if (hasCloud) ...[
                        _heading(l.accountCloud),
                        Text(
                          l.accountCloudNote,
                          style: const TextStyle(
                            color: AppInk.soft,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (!pending)
                          Text(
                            _account.lastSuccessfulBackupAt == null
                                ? l.accountNoBackup
                                : '${l.accountLastBackup} · ${DateFormat.yMd().add_Hm().format(_account.lastSuccessfulBackupAt!.toLocal())}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              height: 1.5,
                            ),
                          ),
                        const SizedBox(height: 16),
                        if (_account.needsReconciliation && !pending) ...[
                          Text(
                            l.accountCloudFound,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l.accountCloudFoundNote,
                            style: const TextStyle(
                              color: AppInk.soft,
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (_account.latestBackup != null && widget.atEntry)
                            FilledButton(
                              onPressed: () => _run(_cloudRestore),
                              child: Text(l.accountUseCloud),
                            ),
                          if (!widget.atEntry)
                            TextButton(
                              onPressed: _returnToEntry,
                              child: Text(l.backupRestoreEntry),
                            ),
                          OutlinedButton(
                            onPressed: () => _run(() => _backup(replace: true)),
                            child: Text(l.accountKeepLocal),
                          ),
                        ] else
                          FilledButton.icon(
                            onPressed: pending ? null : () => _run(_backup),
                            icon: const Icon(Icons.cloud_upload_outlined),
                            label: Text(l.accountBackupNow),
                          ),
                        if (_account.phase == AccountPhase.error)
                          TextButton(
                            onPressed: () => _run(
                              () async => _accountResult(
                                await _account.refreshBackup(),
                              ),
                            ),
                            child: Text(l.accountRefresh),
                          ),
                        const SizedBox(height: 28),
                      ],
                      _heading(l.backupFiles),
                      Text(
                        l.backupFilesNote,
                        style: const TextStyle(color: AppInk.soft, height: 1.6),
                      ),
                      const SizedBox(height: 16),
                      SettingsTileCard(
                        icon: Icons.ios_share_rounded,
                        iconColor: AppPalette.habit,
                        title: l.backupExport,
                        onTap: () => _run(_export),
                      ),
                      const SizedBox(height: 10),
                      SettingsTileCard(
                        icon: Icons.restore_page_outlined,
                        iconColor: AppPalette.habit,
                        title: widget.atEntry
                            ? l.backupImport
                            : l.backupRestoreEntry,
                        subtitle: widget.atEntry
                            ? null
                            : l.backupRestoreEntryNote,
                        onTap: widget.atEntry
                            ? () => _run(_import)
                            : _returnToEntry,
                      ),
                      if (hasCloud) ...[
                        if (_account.latestBackup != null &&
                            widget.atEntry &&
                            !_account.needsReconciliation &&
                            !pending)
                          TextButton(
                            onPressed: () => _run(_cloudRestore),
                            child: Text(l.accountUseCloud),
                          ),
                        const SizedBox(height: 28),
                        _heading(l.accountLinkOther),
                        for (final provider in AccountProvider.values)
                          if (!user.providers.contains(provider))
                            _provider(provider, busy, link: true),
                        TextButton(
                          onPressed: () => _run(() async {
                            if (await _confirm(
                              l.accountSignOut,
                              l.accountSignOutNote,
                              l.accountSignOut,
                            )) {
                              _accountResult(await _account.signOut());
                            }
                          }),
                          child: Text(l.accountSignOut),
                        ),
                      ],
                    ],
                  ),
                ),
                if (busy)
                  Positioned.fill(
                    child: ColoredBox(
                      color: AppSurfaces.canvas.withValues(alpha: .72),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 96, child: AppLoadingBar()),
                            const SizedBox(height: 16),
                            Text(l.accountBusy),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
    ),
  );

  void _returnToEntry() {
    AppEntryIntent.openBackup = true;
    RootRestart.restart(context);
  }
}
