import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'monitor_controller.dart';
import 'monitor_models.dart';
import 'monitor_operations.dart';
import 'monitor_widgets.dart';

/// The answer to "how is the business doing", in one screen.
///
/// Figures split into two groups on purpose: what happened in the chosen
/// period, and what the business is currently carrying regardless of period.
class MonitorOverviewTab extends StatelessWidget {
  const MonitorOverviewTab({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = context.watch<MonitorScope>();
    final repository = context.read<MonitorRepository>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      children: [
        MonitorAsync<MonitorOverview>(
          reloadKey: scope.key,
          height: 320,
          load: () => repository.overview(scope),
          builder: (context, data) => Column(
            children: [
              _TradingCard(data: data, scope: scope),
              _TenderCard(data: data),
              _PositionCard(data: data),
              if (data.refundCount > 0) _RefundCard(data: data),
            ],
          ),
        ),
        _FleetCard(scope: scope),
      ],
    );
  }
}

class _TradingCard extends StatelessWidget {
  const _TradingCard({required this.data, required this.scope});

  final MonitorOverview data;
  final MonitorScope scope;

  @override
  Widget build(BuildContext context) {
    return MonitorCard(
      title: 'Trading',
      subtitle: '${scope.rangeLabel} · ${scope.nodeLabel}',
      child: Column(
        children: [
          MetricGrid(
            tiles: [
              MetricTile(
                label: 'Net sales',
                value: Money.format(data.net),
                hint: data.refundTotal > 0
                    ? 'after ${Money.format(data.refundTotal)} returned'
                    : '${data.invoiceCount} bills',
                tone: AppColors.brand,
                emphasis: true,
              ),
              MetricTile(
                label: 'Collected',
                value: Money.format(data.collected),
                hint: 'tender taken in',
                tone: AppColors.cash,
              ),
              MetricTile(
                label: 'Cash taken',
                value: Money.format(data.cashCollected),
                hint: 'of all tender',
                tone: AppColors.ink,
              ),
              MetricTile(
                label: 'Given on credit',
                value: Money.format(data.credit),
                hint: data.credit > 0 ? 'added to what is owed' : 'nothing unpaid',
                tone: data.credit > 0 ? AppColors.stock : AppColors.inkFaint,
              ),
            ],
          ),
          if (data.bagCharge > 0 || data.wageCharge > 0 || data.discount > 0) ...[
            monitorDivider,
            if (data.bagCharge > 0)
              AmountRow(label: 'Packaging charged', amount: Money.format(data.bagCharge)),
            if (data.wageCharge > 0)
              AmountRow(label: 'Wage charged', amount: Money.format(data.wageCharge)),
            if (data.discount > 0)
              AmountRow(
                label: 'Discount given',
                amount: '− ${Money.format(data.discount)}',
                tone: AppColors.negative,
              ),
          ],
        ],
      ),
    );
  }
}

class _TenderCard extends StatelessWidget {
  const _TenderCard({required this.data});

  final MonitorOverview data;

  @override
  Widget build(BuildContext context) {
    if (data.tenders.isEmpty) {
      return const MonitorCard(
        title: 'How customers paid',
        child: MonitorEmpty(
          message: 'No payments were taken in this period.',
          icon: Icons.payments_outlined,
        ),
      );
    }
    final max = data.tenders
        .map((tender) => tender.total)
        .fold<double>(0, (a, b) => a > b ? a : b);
    return MonitorCard(
      title: 'How customers paid',
      subtitle: 'Tender recorded against bills in this period',
      child: Column(
        children: [
          for (final tender in data.tenders)
            ComparisonBar(
              label: _tenderName(tender.label),
              value: tender.total,
              max: max,
              amount: Money.format(tender.total),
              hint: '${tender.count} payment${tender.count == 1 ? '' : 's'}',
              tone: _tenderTone(tender.label),
            ),
        ],
      ),
    );
  }

  static String _tenderName(String method) => switch (method) {
    'cash' => 'Cash',
    'card' => 'Card',
    'cheque' => 'Cheque',
    'advance' => 'Customer advance',
    'pending' => 'Left on credit',
    _ => prettyStatus(method),
  };

  static Color _tenderTone(String method) => switch (method) {
    'cash' => AppColors.cash,
    'card' => AppColors.card,
    'cheque' => AppColors.note,
    'advance' => AppColors.brand,
    _ => AppColors.stock,
  };
}

/// What the business is carrying right now. These ignore the period filter,
/// because a balance owed does not belong to a date range.
class _PositionCard extends StatelessWidget {
  const _PositionCard({required this.data});

  final MonitorOverview data;

  @override
  Widget build(BuildContext context) {
    return MonitorCard(
      title: 'Current position',
      subtitle: 'Standing balances, not limited to the selected dates',
      child: MetricGrid(
        tiles: [
          MetricTile(
            label: 'Owed by customers',
            value: Money.format(data.outstandingTotal),
            hint: '${data.outstandingInvoices} unpaid bills',
            tone: data.outstandingTotal > 0 ? AppColors.stock : AppColors.inkFaint,
            emphasis: data.outstandingTotal > 0,
            onTap: () => pushMonitorRoute(
              context,
              const MonitorReceivablesScreen(),
            ),
          ),
          MetricTile(
            label: 'Cheques not cleared',
            value: Money.format(data.chequesInFlight),
            hint: 'received or banked',
            tone: data.chequesInFlight > 0 ? AppColors.note : AppColors.inkFaint,
            emphasis: data.chequesInFlight > 0,
            onTap: () => pushMonitorRoute(
              context,
              const MonitorChequesScreen(),
            ),
          ),
          MetricTile(
            label: 'Cash in open drawers',
            value: Money.format(data.expectedCash),
            hint: data.openShifts == 0
                ? 'no shift open'
                : '${data.openShifts} shift${data.openShifts == 1 ? '' : 's'} open',
            tone: AppColors.ink,
          ),
          MetricTile(
            label: 'Advance held',
            value: Money.format(data.advanceHeld),
            hint: 'customer money not yet used',
            tone: data.advanceHeld > 0 ? AppColors.brand : AppColors.inkFaint,
          ),
        ],
      ),
    );
  }
}

class _RefundCard extends StatelessWidget {
  const _RefundCard({required this.data});

  final MonitorOverview data;

  @override
  Widget build(BuildContext context) {
    return MonitorCard(
      title: 'Returns',
      child: AmountRow(
        label: '${data.refundCount} return${data.refundCount == 1 ? '' : 's'}',
        hint: 'already deducted from net sales',
        amount: '− ${Money.format(data.refundTotal)}',
        tone: AppColors.negative,
        bold: true,
      ),
    );
  }
}

/// Which tills reported, and whether any trading day is still open.
class _FleetCard extends StatelessWidget {
  const _FleetCard({required this.scope});

  final MonitorScope scope;

  @override
  Widget build(BuildContext context) {
    final fleet = scope.fleet;
    if (fleet.nodes.isEmpty) {
      return const MonitorCard(
        title: 'Connected POS systems',
        child: MonitorEmpty(
          message: 'No POS has uploaded to this host yet.',
          icon: Icons.point_of_sale_outlined,
        ),
      );
    }
    return MonitorCard(
      title: 'Connected POS systems',
      subtitle: '${fleet.terminals.length} till'
          '${fleet.terminals.length == 1 ? '' : 's'} reporting',
      child: Column(
        children: [
          for (final node in fleet.nodes) ...[
            MonitorRow(
              leading: const Icon(Icons.point_of_sale_rounded,
                  color: AppColors.inkFaint, size: 20),
              title: node.name,
              subtitle: _tills(fleet, node.id),
              trailing: _lastSeen(node.lastSeenAt),
              trailingHint: 'last upload',
            ),
            if (node != fleet.nodes.last) monitorDivider,
          ],
          if (fleet.openDays.isNotEmpty) ...[
            monitorDivider,
            for (final day in fleet.openDays)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    StatusPill(
                      label: prettyStatus(day.status),
                      tone: statusTone(day.status),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${day.locCode} is trading on ${day.businessDate}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.inkSoft,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _tills(MonitorFleet fleet, String nodeId) {
    final tills = fleet.terminals.where((terminal) => terminal.nodeId == nodeId);
    return tills.isEmpty
        ? 'No tills reported yet'
        : tills.map((terminal) => terminal.label).join(' · ');
  }

  String _lastSeen(DateTime? at) {
    if (at == null) return 'never';
    final minutes = DateTime.now().difference(at).inMinutes;
    if (minutes < 1) return 'now';
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    if (hours < 24) return '${hours}h';
    return '${hours ~/ 24}d';
  }
}

/// Sales broken down the way the owner wants to look at them.
class MonitorSalesTab extends StatefulWidget {
  const MonitorSalesTab({super.key});

  @override
  State<MonitorSalesTab> createState() => _MonitorSalesTabState();
}

class _MonitorSalesTabState extends State<MonitorSalesTab> {
  static const _groups = {
    'day': 'By day',
    'terminal': 'By till',
    'customer': 'By customer',
    'status': 'By status',
  };
  String _groupBy = 'day';

  @override
  Widget build(BuildContext context) {
    final scope = context.watch<MonitorScope>();
    final repository = context.read<MonitorRepository>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final entry in _groups.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(entry.value),
                    selected: _groupBy == entry.key,
                    onSelected: (_) {
                      tapHaptic();
                      setState(() => _groupBy = entry.key);
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        MonitorAsync<MonitorSales>(
          reloadKey: '${scope.key}|$_groupBy',
          height: 260,
          load: () => repository.sales(scope, _groupBy),
          builder: (context, data) => Column(
            children: [
              _BreakdownCard(data: data),
              _TopItemsCard(items: data.items),
            ],
          ),
        ),
      ],
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.data});

  final MonitorSales data;

  @override
  Widget build(BuildContext context) {
    if (data.buckets.isEmpty) {
      return MonitorCard(
        title: data.label,
        child: const MonitorEmpty(
          message: 'No bills were finalized in this period.',
          icon: Icons.receipt_long_outlined,
        ),
      );
    }
    final max = data.buckets
        .map((bucket) => bucket.gross)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final total = data.buckets.fold<double>(0, (sum, b) => sum + b.gross);
    return MonitorCard(
      title: data.label,
      subtitle: '${Money.format(total)} across ${data.buckets.length} '
          '${data.buckets.length == 1 ? 'group' : 'groups'}',
      child: Column(
        children: [
          for (final bucket in data.buckets)
            ComparisonBar(
              label: bucket.bucket,
              value: bucket.gross,
              max: max,
              amount: Money.format(bucket.gross),
              hint: bucket.credit > 0
                  ? '${bucket.invoiceCount} bills · ${Money.format(bucket.credit)} on credit'
                  : '${bucket.invoiceCount} bills',
              tone: AppColors.brand,
            ),
        ],
      ),
    );
  }
}

class _TopItemsCard extends StatelessWidget {
  const _TopItemsCard({required this.items});

  final List<MonitorSalesItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const MonitorCard(
        title: 'What sold',
        child: MonitorEmpty(
          message: 'No item lines in this period.',
          icon: Icons.local_grocery_store_outlined,
        ),
      );
    }
    return MonitorCard(
      title: 'What sold',
      subtitle: 'Highest value first, in both units of measure',
      child: Column(
        children: [
          for (final item in items) ...[
            MonitorRow(
              title: item.description,
              subtitle: measureText(
                handlingQty: item.handlingQty,
                handlingUom: item.handlingUom,
                baseQty: item.baseQty > 0 ? item.baseQty : null,
                baseUom: item.baseUom,
              ),
              trailing: Money.format(item.total),
              trailingHint: '${item.lineCount} lines',
            ),
            if (item != items.last) monitorDivider,
          ],
        ],
      ),
    );
  }
}
