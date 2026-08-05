import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_style.dart';
import '../../widgets/app_waiting.dart';
import 'family_auth.dart';
import 'family_models.dart';
import 'family_store.dart';

// ── 獎勵 Tab ──

class RewardTab extends StatefulWidget {
  final ChildData child;
  final VoidCallback onPointsChanged;

  const RewardTab({
    super.key,
    required this.child,
    required this.onPointsChanged,
  });

  @override
  State<RewardTab> createState() => _RewardTabState();
}

class _RewardTabState extends State<RewardTab> {
  AppLocalizations get _l10n => AppLocalizations.of(context);

  List<RewardItem> _rewards = [];
  List<VoucherLog> _vouchers = [];
  bool _loaded = false;
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    final allRewards = await loadRewards(_prefs!);
    final allVouchers = await loadVouchers(_prefs!);
    setState(() {
      _rewards = allRewards
          .where((r) => r.childIds.contains(widget.child.id))
          .toList();
      _vouchers = allVouchers
          .where((v) => v.childId == widget.child.id)
          .toList();
      _loaded = true;
    });
  }

  String _rewardName(String rewardId) {
    final r = _rewards.where((r) => r.id == rewardId).firstOrNull;
    return r?.name ?? _l10n.rtDeletedReward;
  }

  Future<void> _redeem(RewardItem r) async {
    if (!mounted) return;
    if (widget.child.points < r.pointsCost) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_l10n.rtNotEnoughPoints)));
      return;
    }

    var qty = 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setS) => AlertDialog(
          title: Text(_l10n.rtRedeemTitle(r.name)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _l10n.rtCostPerVoucher(r.pointsCost),
                style: TextStyle(fontSize: 13, color: AppInk.soft),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: qty > 1 ? () => setS(() => qty--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      _l10n.rtVoucherCount(qty),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.child.points >= r.pointsCost * (qty + 1)
                        ? () => setS(() => qty++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _l10n.rtTotalCost(
                  r.pointsCost * qty,
                  widget.child.points - r.pointsCost * qty,
                ),
                style: TextStyle(fontSize: 13, color: AppInk.soft),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                _l10n.commonCancel,
                style: TextStyle(color: AppInk.soft),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(_l10n.rtConfirmRedeem),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final prefs = _prefs!;
    final newPoints = await applyPoints(
      prefs: prefs,
      child: widget.child,
      delta: -(r.pointsCost * qty),
      reason: _l10n.rtReasonRedeem(r.name, qty),
    );
    final allVouchers = await loadVouchers(prefs);
    final now = nowStr();
    for (var i = 0; i < qty; i++) {
      final v = VoucherLog(
        id: genId(),
        rewardId: r.id,
        childId: widget.child.id,
        redeemedAt: now,
      );
      allVouchers.add(v);
      _vouchers.add(v);
    }
    await saveVouchers(prefs, allVouchers);
    setState(() => widget.child.points = newPoints);
    widget.onPointsChanged();
  }

  Future<void> _useVoucher(VoucherLog v) async {
    if (!mounted) return;
    final ok = await verifyParentPinIfNeeded(
      context,
      title: _l10n.rtPinUseVoucher,
    );
    if (!ok || !mounted) return;
    final rewardName = _rewardName(v.rewardId);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_l10n.rtUseVoucherTitle),
        content: Text(_l10n.rtUseVoucherMessage(rewardName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              _l10n.commonCancel,
              style: TextStyle(color: AppInk.soft),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_l10n.rtConfirmUse),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    v.used = true;
    v.usedAt = nowStr();
    final prefs = _prefs!;
    final allVouchers = await loadVouchers(prefs);
    final idx = allVouchers.indexWhere((x) => x.id == v.id);
    if (idx >= 0) {
      allVouchers[idx].used = true;
      allVouchers[idx].usedAt = v.usedAt;
    }
    await saveVouchers(prefs, allVouchers);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const AppPageWaiting();

    final pendingVouchers = _vouchers.where((v) => !v.used).toList()
      ..sort((a, b) => b.redeemedAt.compareTo(a.redeemedAt));
    final usedVouchers = _vouchers.where((v) => v.used).toList()
      ..sort((a, b) => b.usedAt.compareTo(a.usedAt));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 我的票券 ──
          _SectionHeader(
            icon: Icons.confirmation_num_outlined,
            label: _l10n.rtMyVouchers,
            color: Colors.purple.shade400,
            trailing: pendingVouchers.isEmpty
                ? null
                : _l10n.rtVoucherCount(pendingVouchers.length),
          ),
          if (pendingVouchers.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                _l10n.rtNoVouchers,
                style: TextStyle(fontSize: 13, color: AppInk.faint),
              ),
            )
          else
            ...pendingVouchers.map(
              (v) => _VoucherCard(
                voucher: v,
                rewardName: _rewardName(v.rewardId),
                onUse: () => _useVoucher(v),
              ),
            ),

          const SizedBox(height: 8),

          // ── 可兌換獎勵 ──
          _SectionHeader(
            icon: Icons.card_giftcard_outlined,
            label: _l10n.rtAvailableRewards,
            color: Colors.amber.shade700,
          ),
          if (_rewards.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                _l10n.rtNoRewards,
                style: TextStyle(fontSize: 13, color: AppInk.faint),
              ),
            )
          else
            ..._rewards.map((r) {
              final canAfford = widget.child.points >= r.pointsCost;
              return _RewardCard(
                reward: r,
                canAfford: canAfford,
                onRedeem: () => _redeem(r),
              );
            }),

          const SizedBox(height: 8),

          // ── 兌換紀錄（已使用票券） ──
          if (usedVouchers.isNotEmpty)
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                leading: Icon(Icons.history, color: AppInk.soft, size: 20),
                title: Text(
                  _l10n.rtHistoryTitle(usedVouchers.length),
                  style: TextStyle(fontSize: 14, color: AppInk.soft),
                ),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                children: usedVouchers.map((v) {
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: Colors.green.shade400,
                    ),
                    title: Text(
                      _rewardName(v.rewardId),
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      _l10n.rtHistoryLine(v.redeemedAt, v.usedAt),
                      style: TextStyle(fontSize: 11, color: AppInk.faint),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String? trailing;

  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.color,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                trailing!,
                style: TextStyle(fontSize: 11, color: color),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VoucherCard extends StatelessWidget {
  final VoucherLog voucher;
  final String rewardName;
  final VoidCallback onUse;

  const _VoucherCard({
    required this.voucher,
    required this.rewardName,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.confirmation_num,
              size: 32,
              color: Colors.purple.shade300,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rewardName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppLocalizations.of(
                      context,
                    ).rtRedeemedAt(voucher.redeemedAt),
                    style: TextStyle(fontSize: 11, color: AppInk.soft),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: onUse,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade400,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                textStyle: const TextStyle(fontSize: 13),
              ),
              child: Text(AppLocalizations.of(context).rtUse),
            ),
          ],
        ),
      ),
    );
  }
}

class _RewardCard extends StatelessWidget {
  final RewardItem reward;
  final bool canAfford;
  final VoidCallback onRedeem;

  const _RewardCard({
    required this.reward,
    required this.canAfford,
    required this.onRedeem,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.card_giftcard, color: primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reward.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.star, size: 12, color: Colors.amber.shade600),
                      const SizedBox(width: 2),
                      Text(
                        AppLocalizations.of(
                          context,
                        ).pmRewardCost(reward.pointsCost),
                        style: TextStyle(fontSize: 12, color: AppInk.soft),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: canAfford ? onRedeem : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppSurfaces.divider,
                disabledForegroundColor: AppInk.faint,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                textStyle: const TextStyle(fontSize: 13),
              ),
              child: Text(
                canAfford
                    ? AppLocalizations.of(context).rtRedeem
                    : AppLocalizations.of(context).rtCantAfford,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
