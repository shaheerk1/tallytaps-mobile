import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/category_spec.dart';
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
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TallyStore>();
    final filtered = _filterList(store.actions);

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
          if (store.unsynced.isNotEmpty)
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
                hintText: 'Search entries…',
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
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
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

  Widget _filterChip(ActionType? type, String label) {
    final selected = _filter == type;
    final color = type == null ? AppColors.brand : CategorySpec.of(type).color;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          tapHaptic();
          setState(() => _filter = selected ? null : type);
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

  void _openDetail(TallyAction action) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DetailSheet(action: action),
    );
  }

  Future<void> _pushAll(BuildContext context) async {
    final store = context.read<TallyStore>();
    final messenger = ScaffoldMessenger.of(context);
    final pending = store.unsynced.toList();
    if (pending.isEmpty) return;
    if (!store.isConnected) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SyncSetupScreen()),
      );
      return;
    }
    final count = await store.syncPending();
    if (mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            count == pending.length
                ? 'Synced $count ${count == 1 ? 'entry' : 'entries'} to your server.'
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
// Empty state
// ---------------------------------------------------------------------------
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasFilter});

  final bool hasFilter;

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
            hasFilter ? 'Nothing matches' : 'No entries yet',
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
