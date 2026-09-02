import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/category_spec.dart';
import '../models/mobile_bill.dart';
import '../models/tally_action.dart';
import '../state/tally_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'detail_sheet.dart';
import 'sync_setup_screen.dart';

/// Separate view for past entries so it never interrupts recording a new one.
/// Lists every action grouped by day, filterable by category and searchable.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  ActionType? _filter;
  bool _showBills = false;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TallyStore>();
    final filtered = _filterList(store.actions);
    final filteredBills = _filterBills(store.mobileBills);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
        title: const Text(
          'History',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Server setup',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SyncSetupScreen()),
            ),
            icon: Icon(
              store.isConnected
                  ? Icons.settings_input_component_rounded
                  : Icons.settings_outlined,
            ),
          ),
          if (store.unsynced.isNotEmpty || store.pendingBillCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: store.syncing ? null : () => _pushAll(context),
                icon: store.syncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_rounded, size: 18),
                label: const Text('Push all'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brand,
                  backgroundColor: AppColors.brand.withValues(alpha: 0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: _showBills ? 'Search bills…' : 'Search entries…',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppColors.inkFaint,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              children: [
                _filterChip(null, 'All'),
                for (final spec in CategorySpec.all)
                  _filterChip(spec.type, spec.label),
                _billFilterChip(store.mobileBills.length),
              ],
            ),
          ),
          Expanded(
            child: _showBills
                ? filteredBills.isEmpty
                      ? _EmptyState(
                          hasFilter: _query.isNotEmpty,
                          bills: true,
                        )
                      : _BillGroupedList(
                          bills: filteredBills,
                          onTap: _openBillDetail,
                        )
                : filtered.isEmpty
                ? _EmptyState(hasFilter: _filter != null || _query.isNotEmpty)
                : _GroupedList(actions: filtered, onTap: _openDetail),
          ),
        ],
      ),
    );
  }

  List<TallyAction> _filterList(List<TallyAction> all) {
    return all.where((a) {
      if (_filter != null && a.type != _filter) return false;
      if (_query.isEmpty) return true;
      return a.title.toLowerCase().contains(_query) ||
          (a.note?.toLowerCase().contains(_query) ?? false);
    }).toList();
  }

  List<MobileBill> _filterBills(List<MobileBill> all) {
    if (_query.isEmpty) return all;
    return all.where((bill) {
      return (bill.customerName?.toLowerCase().contains(_query) ?? false) ||
          (bill.customerMobile?.toLowerCase().contains(_query) ?? false) ||
          (bill.note?.toLowerCase().contains(_query) ?? false) ||
          bill.clientBillId.toLowerCase().contains(_query) ||
          bill.lines.any(
            (line) => line.item.name.toLowerCase().contains(_query),
          );
    }).toList();
  }

  Widget _filterChip(ActionType? type, String label) {
    final selected = !_showBills && _filter == type;
    final color = type == null ? AppColors.brand : CategorySpec.of(type).color;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          tapHaptic();
          setState(() {
            _showBills = false;
            _filter = selected ? null : type;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: selected ? color : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? color : AppColors.line),
          ),
          child: Row(
            children: [
              if (type != null) ...[
                Icon(
                  CategorySpec.of(type).icon,
                  size: 16,
                  color: selected ? Colors.white : color,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _billFilterChip(int count) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          tapHaptic();
          setState(() => _showBills = true);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: _showBills ? AppColors.brand : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _showBills ? AppColors.brand : AppColors.line,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.receipt_long_rounded,
                size: 16,
                color: _showBills ? Colors.white : AppColors.brand,
              ),
              const SizedBox(width: 6),
              Text(
                count == 0 ? 'Bills' : 'Bills $count',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _showBills ? Colors.white : AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDetail(TallyAction action) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DetailSheet(action: action),
    );
  }

  void _openBillDetail(MobileBill bill) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MobileBillDetailSheet(bill: bill),
    );
  }

  Future<void> _pushAll(BuildContext context) async {
    final store = context.read<TallyStore>();
    final messenger = ScaffoldMessenger.of(context);
    final pendingEntries = store.unsynced.length;
    final pendingBills = store.pendingBillCount;
    final pending = pendingEntries + pendingBills;
    if (pending == 0) return;
    if (!store.isConnected) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SyncSetupScreen()),
      );
      return;
    }
    final entryCount = await store.syncPending();
    final billCount = await store.syncPendingBills();
    final count = entryCount + billCount;
    if (mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            count == pending
                ? 'Synced $count ${count == 1 ? 'item' : 'items'} to your server.'
                : store.lastSyncError ?? 'Some entries are still waiting to sync.',
          ),
        ),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Grouped list
// ---------------------------------------------------------------------------
class _GroupedList extends StatelessWidget {
  const _GroupedList({required this.actions, required this.onTap});

  final List<TallyAction> actions;
  final ValueChanged<TallyAction> onTap;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<TallyAction>>{};
    for (final a in actions) {
      groups.putIfAbsent(_dayLabel(a.createdAt), () => []).add(a);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
            child: Text(
              entry.key,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.inkFaint,
                letterSpacing: 0.3,
              ),
            ),
          ),
          for (final action in entry.value)
            _ActionTile(action: action, onTap: () => onTap(action)),
        ],
      ],
    );
  }

  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'TODAY';
    if (diff == 1) return 'YESTERDAY';
    return DateFormat('EEEE, d MMM').format(d).toUpperCase();
  }
}

// ---------------------------------------------------------------------------
// One entry row
// ---------------------------------------------------------------------------
class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action, required this.onTap});

  final TallyAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final spec = CategorySpec.of(action.type);
    final isIn = action.direction == ActionDirection.incoming;
    final valueColor = isIn ? AppColors.positive : AppColors.negative;
    final sign = isIn ? '+' : '−';
    final time = DateFormat('h:mm a').format(action.createdAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        elevation: 1,
        child: InkWell(
          onTap: () {
            tapHaptic();
            onTap();
          },
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: spec.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(spec.icon, color: spec.color, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        action.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            time,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.inkFaint,
                            ),
                          ),
                          if (action.qtyLabel.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              action.qtyLabel,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.inkSoft,
                              ),
                            ),
                          ],
                          if (action.imagePaths.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.photo_outlined,
                              size: 13,
                              color: AppColors.inkFaint,
                            ),
                            Text(
                              '${action.imagePaths.length}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.inkFaint,
                              ),
                            ),
                          ],
                          if (action.voicePath != null) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.mic_none_rounded,
                              size: 13,
                              color: AppColors.inkFaint,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (action.type == ActionType.stock)
                      Text(
                        action.qtyLabel.isEmpty ? '—' : action.qtyLabel,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: valueColor,
                        ),
                      )
                    else
                      Text(
                        '$sign${Money.format(action.amount)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: valueColor,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Icon(
                      action.synced
                          ? Icons.cloud_done_rounded
                          : Icons.cloud_upload_rounded,
                      size: 16,
                      color: action.synced
                          ? AppColors.positive
                          : AppColors.stock,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mobile-created bills
// ---------------------------------------------------------------------------
class _BillGroupedList extends StatelessWidget {
  const _BillGroupedList({required this.bills, required this.onTap});

  final List<MobileBill> bills;
  final ValueChanged<MobileBill> onTap;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<MobileBill>>{};
    for (final bill in bills) {
      groups.putIfAbsent(_dayLabel(bill.createdAt), () => []).add(bill);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
            child: Text(
              entry.key,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.inkFaint,
                letterSpacing: 0.3,
              ),
            ),
          ),
          for (final bill in entry.value)
            _BillTile(bill: bill, onTap: () => onTap(bill)),
        ],
      ],
    );
  }

  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'TODAY';
    if (diff == 1) return 'YESTERDAY';
    return DateFormat('EEEE, d MMM').format(d).toUpperCase();
  }
}

class _BillTile extends StatelessWidget {
  const _BillTile({required this.bill, required this.onTap});

  final MobileBill bill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = _billStatus(bill);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        elevation: 1,
        child: InkWell(
          onTap: () {
            tapHaptic();
            onTap();
          },
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: AppColors.brand,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bill.customerName ?? 'Walk-in customer',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${DateFormat('h:mm a').format(bill.createdAt)}  ·  '
                        '${bill.lines.length} ${bill.lines.length == 1 ? 'item' : 'items'}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Money.format(bill.grandTotal),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(status.icon, size: 14, color: status.color),
                        const SizedBox(width: 4),
                        Text(
                          status.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: status.color,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileBillDetailSheet extends StatelessWidget {
  const _MobileBillDetailSheet({required this.bill});

  final MobileBill bill;

  @override
  Widget build(BuildContext context) {
    final current = context.watch<TallyStore>().mobileBills.firstWhere(
      (saved) => saved.clientBillId == bill.clientBillId,
      orElse: () => bill,
    );
    final status = _billStatus(current);
    final merchandise = current.lines.fold<double>(
      0,
      (sum, line) => sum + line.merchandiseTotal,
    );
    final packaging = current.lines.fold<double>(
      0,
      (sum, line) => sum + line.bagChargeTotal,
    );
    final wages = current.lines.fold<double>(
      0,
      (sum, line) => sum + line.wageChargeTotal,
    );

    return FractionallySizedBox(
      heightFactor: 0.9,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Container(
                width: 42,
                height: 5,
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 12, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Mobile bill',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    _BillSection(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: status.color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      status.icon,
                                      size: 16,
                                      color: status.color,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      status.detailLabel,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: status.color,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              Text(
                                DateFormat(
                                  'd MMM yyyy · h:mm a',
                                ).format(current.createdAt),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.inkFaint,
                                ),
                              ),
                            ],
                          ),
                          if (!current.synced && current.lastError != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Last attempt: ${current.lastError}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.negative,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _BillSection(
                      child: Column(
                        children: [
                          _detailRow(
                            'Customer',
                            current.customerName ?? 'Walk-in customer',
                          ),
                          if (current.customerMobile != null)
                            _detailRow('Mobile', current.customerMobile!),
                          _detailRow(
                            'Payment',
                            _friendlyPayment(current.paymentMethod),
                          ),
                          _detailRow(
                            'Send to',
                            current.deliveryScope == 'selected'
                                ? '${current.targetPosNodeIds.length} selected POS'
                                : 'All connected POS terminals',
                            last: current.note == null,
                          ),
                          if (current.note != null)
                            _detailRow('Note', current.note!, last: true),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 18, 4, 8),
                      child: Text(
                        'ITEMS',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.inkFaint,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    for (final line in current.lines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _BillSection(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      line.item.name,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    Money.format(line.lineTotal),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _lineMeasure(line),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.inkSoft,
                                ),
                              ),
                              if (line.bagChargeTotal > 0 ||
                                  line.wageChargeTotal > 0) ...[
                                const SizedBox(height: 6),
                                Text(
                                  [
                                    if (line.bagChargeTotal > 0)
                                      'Packaging ${Money.format(line.bagChargeTotal)}',
                                    if (line.wageChargeTotal > 0)
                                      'Wage ${Money.format(line.wageChargeTotal)}',
                                  ].join('  ·  '),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.inkFaint,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 2),
                    _BillSection(
                      child: Column(
                        children: [
                          _detailRow('Items total', Money.format(merchandise)),
                          if (packaging > 0)
                            _detailRow(
                              'Packaging charges',
                              Money.format(packaging),
                            ),
                          if (wages > 0)
                            _detailRow('Wage charges', Money.format(wages)),
                          const Divider(height: 22),
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Total',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Text(
                                Money.format(current.grandTotal),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.brand,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!current.synced) ...[
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed:
                            context.watch<TallyStore>().isConnected &&
                                !context.watch<TallyStore>().syncing
                            ? () => context
                                  .read<TallyStore>()
                                  .syncPendingBills()
                            : null,
                        icon: const Icon(Icons.cloud_upload_rounded),
                        label: Text(
                          context.watch<TallyStore>().isConnected
                              ? 'Try syncing now'
                              : 'Connect to sync this bill',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _detailRow(String label, String value, {bool last = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.inkFaint,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BillSection extends StatelessWidget {
  const _BillSection({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: child,
    );
  }
}

({String label, String detailLabel, IconData icon, Color color}) _billStatus(
  MobileBill bill,
) {
  if (bill.synced) {
    return (
      label: 'Sent',
      detailLabel: 'Sent to POS',
      icon: Icons.cloud_done_rounded,
      color: AppColors.positive,
    );
  }
  if (bill.lastError != null) {
    return (
      label: 'Retry',
      detailLabel: 'Needs retry',
      icon: Icons.error_outline_rounded,
      color: AppColors.negative,
    );
  }
  return (
    label: 'Waiting',
    detailLabel: 'Waiting to sync',
    icon: Icons.cloud_upload_outlined,
    color: AppColors.stock,
  );
}

String _friendlyPayment(String value) {
  if (value.isEmpty) return 'Unpaid';
  return '${value[0].toUpperCase()}${value.substring(1)}';
}

String _lineMeasure(MobileBillLine line) {
  final handling = '${_plainNumber(line.quantity)} ${line.item.handlingUom}';
  final measured = line.kilos == null
      ? ''
      : ' · ${_plainNumber(line.kilos!)} ${line.item.baseUom ?? 'measured'}';
  return '$handling$measured  @  ${Money.format(line.unitPrice)} / ${line.item.priceUom}';
}

String _plainNumber(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasFilter, this.bills = false});

  final bool hasFilter;
  final bool bills;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppColors.line.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inbox_rounded,
              color: AppColors.inkFaint,
              size: 44,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            hasFilter
                ? 'Nothing matches'
                : bills
                ? 'No mobile bills yet'
                : 'No entries yet',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasFilter
                ? 'Try a different filter or search.'
                : bills
                ? 'Bills you create on this phone will show up here.'
                : 'Your recorded actions will show up here.',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}
