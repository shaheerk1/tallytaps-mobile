import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'monitor_controller.dart';
import 'monitor_models.dart';
import 'monitor_widgets.dart';

/// Drawer sessions and where the cash moved.
class MonitorCashTab extends StatelessWidget {
  const MonitorCashTab({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = context.watch<MonitorScope>();
    final repository = context.read<MonitorRepository>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      children: [
        MonitorAsync<MonitorCash>(
          reloadKey: scope.key,
          height: 300,
          load: () => repository.cash(scope),
          builder: (context, data) => Column(
            children: [
              _ShiftsCard(shifts: data.shifts),
              _MovementsCard(movements: data.movements),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShiftsCard extends StatelessWidget {
  const _ShiftsCard({required this.shifts});

  final List<MonitorShift> shifts;

  @override
  Widget build(BuildContext context) {
    if (shifts.isEmpty) {
      return const MonitorCard(
        title: 'Cashier shifts',
        child: MonitorEmpty(
          message: 'No drawer was opened in this period.',
          icon: Icons.account_balance_wallet_outlined,
        ),
      );
    }
    final withVariance = shifts.where((shift) => shift.hasVariance).length;
    return MonitorCard(
      title: 'Cashier shifts',
      subtitle: withVariance == 0
          ? 'Every closed shift reconciled'
          : '$withVariance shift${withVariance == 1 ? '' : 's'} closed with a difference',
      child: Column(
        children: [
          for (final shift in shifts) ...[
            _ShiftRow(shift: shift),
            if (shift != shifts.last) monitorDivider,
          ],
        ],
      ),
    );
  }
}

class _ShiftRow extends StatelessWidget {
  const _ShiftRow({required this.shift});

  final MonitorShift shift;

  @override
  Widget build(BuildContext context) {
    final variance = shift.varianceTotal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            StatusPill(
              label: prettyStatus(shift.status),
              tone: statusTone(shift.status),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Shift ${shift.shiftNo} · ${shift.terminal}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
            Text(
              shift.businessDate,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.inkFaint,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        MetricGrid(
          columns: 3,
          tiles: [
            MetricTile(
              label: 'Float',
              value: Money.format(shift.openingTotal),
            ),
            MetricTile(
              label: shift.isOpen ? 'Expected now' : 'Expected',
              value: Money.format(shift.expectedTotal),
              tone: AppColors.ink,
            ),
            MetricTile(
              label: 'Counted',
              value: shift.declaredTotal == null
                  ? '—'
                  : Money.format(shift.declaredTotal!),
              tone: AppColors.inkSoft,
            ),
          ],
        ),
        if (variance != null && shift.hasVariance) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: (variance < 0 ? AppColors.negative : AppColors.stock)
                  .withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  variance < 0
                      ? '${Money.format(variance.abs())} short'
                      : '${Money.format(variance)} over',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: variance < 0 ? AppColors.negative : AppColors.stock,
                  ),
                ),
                if (shift.varianceReason?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      shift.varianceReason!,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MovementsCard extends StatelessWidget {
  const _MovementsCard({required this.movements});

  final List<MonitorTotal> movements;

  @override
  Widget build(BuildContext context) {
    if (movements.isEmpty) {
      return const MonitorCard(
        title: 'Cash movements',
        child: MonitorEmpty(
          message: 'No cash moved in or out in this period.',
          icon: Icons.swap_vert_rounded,
        ),
      );
    }
    final max = movements
        .map((row) => row.total)
        .fold<double>(0, (a, b) => a > b ? a : b);
    return MonitorCard(
      title: 'Cash movements',
      subtitle: 'What moved through the drawers, by reason',
      child: Column(
        children: [
          for (final movement in movements)
            ComparisonBar(
              label: _movementName(movement.label),
              value: movement.total,
              max: max,
              amount: Money.format(movement.total),
              hint: '${movement.count} entries',
              tone: AppColors.cash,
            ),
        ],
      ),
    );
  }

  static String _movementName(String type) => switch (type) {
    'opening_float' => 'Opening float',
    'sale_cash' => 'Cash from sales',
    'change_given' => 'Change given',
    'refund_cash' => 'Cash refunded',
    'receivable_collection_cash' => 'Balance collected',
    'customer_advance_cash' => 'Advance received',
    'customer_advance_refund_cash' => 'Advance returned',
    'supplier_settlement_cash' => 'Paid to supplier',
    'safe_drop' => 'Moved to safe',
    'bank_drop' => 'Banked',
    'cash_in' => 'Other cash in',
    'cash_out' => 'Other cash out',
    _ => prettyStatus(type),
  };
}

/// Item stock, received batches and goods received notes.
class MonitorStockTab extends StatefulWidget {
  const MonitorStockTab({super.key});

  @override
  State<MonitorStockTab> createState() => _MonitorStockTabState();
}

class _MonitorStockTabState extends State<MonitorStockTab> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  int _view = 0;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = context.watch<MonitorScope>();
    final repository = context.read<MonitorRepository>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Items'), icon: Icon(Icons.inventory_2_outlined, size: 18)),
              ButtonSegment(value: 1, label: Text('Batches'), icon: Icon(Icons.layers_outlined, size: 18)),
              ButtonSegment(value: 2, label: Text('Received'), icon: Icon(Icons.local_shipping_outlined, size: 18)),
            ],
            selected: {_view},
            showSelectedIcon: false,
            onSelectionChanged: (value) {
              tapHaptic();
              setState(() => _view = value.first);
            },
          ),
        ),
        if (_view == 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search items',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.line),
                ),
              ),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
            children: [
              if (_view == 0)
                MonitorAsync<List<MonitorStockItem>>(
                  reloadKey: '${scope.key}|$_query',
                  height: 240,
                  load: () => repository.stock(scope, query: _query),
                  builder: (context, items) => _StockItemsCard(items: items),
                )
              else if (_view == 1)
                MonitorAsync<List<MonitorLot>>(
                  reloadKey: scope.key,
                  height: 240,
                  load: () => repository.lots(scope),
                  builder: (context, lots) => _LotsCard(lots: lots),
                )
              else
                MonitorAsync<List<MonitorGrn>>(
                  reloadKey: scope.key,
                  height: 240,
                  load: () => repository.goodsReceipts(scope),
                  builder: (context, rows) => _GrnCard(rows: rows),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StockItemsCard extends StatelessWidget {
  const _StockItemsCard({required this.items});

  final List<MonitorStockItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const MonitorCard(
        title: 'Items on hand',
        child: MonitorEmpty(
          message: 'No items match, or this POS has not published its catalog yet.',
          icon: Icons.inventory_2_outlined,
        ),
      );
    }
    return MonitorCard(
      title: 'Items on hand',
      subtitle: 'Live quantity from each POS, in every unit it is kept in',
      child: Column(
        children: [
          for (final item in items) ...[
            MonitorRow(
              title: item.name,
              subtitle: item.category?.isNotEmpty == true
                  ? '${item.category} · ${item.nodeName}'
                  : item.nodeName,
              trailing: measureText(
                handlingQty: item.handlingQty,
                handlingUom: item.handlingUom,
                baseQty: item.baseQty,
                baseUom: item.baseUom,
              ),
              trailingHint: '${Money.format(item.unitPrice)} rate',
              tone: item.handlingQty <= 0 ? AppColors.negative : AppColors.ink,
            ),
            if (item != items.last) monitorDivider,
          ],
        ],
      ),
    );
  }
}

class _LotsCard extends StatelessWidget {
  const _LotsCard({required this.lots});

  final List<MonitorLot> lots;

  @override
  Widget build(BuildContext context) {
    if (lots.isEmpty) {
      return const MonitorCard(
        title: 'Received batches',
        child: MonitorEmpty(
          message: 'No stock batches were received in this period.',
          icon: Icons.layers_outlined,
        ),
      );
    }
    return MonitorCard(
      title: 'Received batches',
      subtitle: 'What is left of each delivery, traced to its GRN',
      child: Column(
        children: [
          for (final lot in lots) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        lot.productName,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    if (lot.isConsignment)
                      const StatusPill(label: 'consignment', tone: AppColors.note),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (lot.grnNo != null) 'GRN ${lot.grnNo}',
                    if (lot.supplierName != null) lot.supplierName!,
                    lot.businessDate,
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.inkFaint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 9),
                MetricGrid(
                  tiles: [
                    MetricTile(
                      label: 'Received',
                      value: measureText(
                        handlingQty: lot.receivedHandling,
                        handlingUom: lot.handlingUom,
                        baseQty: lot.receivedBase,
                        baseUom: lot.baseUom,
                      ),
                    ),
                    MetricTile(
                      label: 'Still in stock',
                      value: measureText(
                        handlingQty: lot.remainingHandling,
                        handlingUom: lot.handlingUom,
                        baseQty: lot.remainingBase,
                        baseUom: lot.baseUom,
                      ),
                      tone: lot.remainingHandling <= 0
                          ? AppColors.inkFaint
                          : AppColors.brand,
                      emphasis: lot.remainingHandling > 0,
                    ),
                  ],
                ),
              ],
            ),
            if (lot != lots.last) monitorDivider,
          ],
        ],
      ),
    );
  }
}

class _GrnCard extends StatelessWidget {
  const _GrnCard({required this.rows});

  final List<MonitorGrn> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const MonitorCard(
        title: 'Goods received',
        child: MonitorEmpty(
          message: 'No deliveries were recorded in this period.',
          icon: Icons.local_shipping_outlined,
        ),
      );
    }
    return MonitorCard(
      title: 'Goods received',
      subtitle: '${rows.length} delivery note${rows.length == 1 ? '' : 's'}',
      child: Column(
        children: [
          for (final grn in rows) ...[
            MonitorRow(
              leading: StatusPill(
                label: prettyStatus(grn.status),
                tone: statusTone(grn.status),
              ),
              title: grn.supplierName ?? grn.grnNumber,
              subtitle: [
                grn.grnNumber,
                grn.businessDate,
                if (grn.vehicleNo?.isNotEmpty == true) 'vehicle ${grn.vehicleNo}',
              ].join(' · '),
            ),
            if (grn != rows.last) monitorDivider,
          ],
        ],
      ),
    );
  }
}

/// Who owes the business money, largest first.
class MonitorReceivablesScreen extends StatelessWidget {
  const MonitorReceivablesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = context.watch<MonitorScope>();
    final repository = context.read<MonitorRepository>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Owed by customers',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          MonitorAsync<List<MonitorReceivable>>(
            reloadKey: scope.nodeId ?? 'all',
            height: 260,
            load: () => repository.receivables(scope),
            builder: (context, rows) {
              if (rows.isEmpty) {
                return const MonitorCard(
                  title: 'Outstanding balances',
                  child: MonitorEmpty(
                    message: 'Every bill is settled. Nothing is owed.',
                    icon: Icons.verified_outlined,
                  ),
                );
              }
              final total = rows.fold<double>(0, (sum, row) => sum + row.balance);
              return MonitorCard(
                title: 'Outstanding balances',
                subtitle: '${Money.format(total)} across ${rows.length} '
                    'customer${rows.length == 1 ? '' : 's'}',
                child: Column(
                  children: [
                    for (final row in rows) ...[
                      MonitorRow(
                        title: row.title,
                        subtitle: [
                          row.customerCode,
                          '${row.invoiceCount} unpaid bill${row.invoiceCount == 1 ? '' : 's'}',
                          'oldest ${row.oldest}',
                          if (row.customerMobile != null) row.customerMobile!,
                        ].join(' · '),
                        trailing: Money.format(row.balance),
                        tone: AppColors.stock,
                        trailingAction: row.customerMobile == null
                            ? null
                            : _CustomerCallButton(
                                customerName: row.title,
                                mobile: row.customerMobile!,
                              ),
                      ),
                      if (row != rows.last) monitorDivider,
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CustomerCallButton extends StatelessWidget {
  const _CustomerCallButton({
    required this.customerName,
    required this.mobile,
  });

  final String customerName;
  final String mobile;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: 'Call $customerName',
      onPressed: () => _openDialer(context),
      style: IconButton.styleFrom(
        foregroundColor: AppColors.cash,
        backgroundColor: AppColors.cashSoft,
      ),
      icon: const Icon(Icons.call_rounded, size: 20),
    );
  }

  Future<void> _openDialer(BuildContext context) async {
    tapHaptic();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final opened = await launchUrl(Uri(scheme: 'tel', path: mobile.trim()));
      if (!opened && context.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not open the phone dialer.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not open the phone dialer.')),
        );
      }
    }
  }
}

/// Cheques held from customers and cheques written to others.
class MonitorChequesScreen extends StatefulWidget {
  const MonitorChequesScreen({super.key});

  @override
  State<MonitorChequesScreen> createState() => _MonitorChequesScreenState();
}

class _MonitorChequesScreenState extends State<MonitorChequesScreen> {
  int _view = 0;

  @override
  Widget build(BuildContext context) {
    final scope = context.watch<MonitorScope>();
    final repository = context.read<MonitorRepository>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Cheques', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('From customers')),
                ButtonSegment(value: 1, label: Text('Written by us')),
              ],
              selected: {_view},
              showSelectedIcon: false,
              onSelectionChanged: (value) {
                tapHaptic();
                setState(() => _view = value.first);
              },
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
              children: [
                MonitorAsync<MonitorCheques>(
                  reloadKey: scope.nodeId ?? 'all',
                  height: 260,
                  load: () => repository.cheques(scope),
                  builder: (context, data) {
                    final rows = _view == 0 ? data.incoming : data.issued;
                    if (rows.isEmpty) {
                      return MonitorCard(
                        title: _view == 0 ? 'Cheques received' : 'Cheques issued',
                        child: const MonitorEmpty(
                          message: 'No cheques recorded.',
                          icon: Icons.receipt_outlined,
                        ),
                      );
                    }
                    final total = rows.fold<double>(0, (sum, row) => sum + row.amount);
                    return MonitorCard(
                      title: _view == 0 ? 'Cheques received' : 'Cheques issued',
                      subtitle: '${Money.format(total)} across ${rows.length} '
                          'cheque${rows.length == 1 ? '' : 's'}',
                      child: Column(
                        children: [
                          for (final cheque in rows) ...[
                            MonitorRow(
                              leading: StatusPill(
                                label: prettyStatus(cheque.status),
                                tone: statusTone(cheque.status),
                              ),
                              title: cheque.partyName,
                              subtitle: [
                                'No. ${cheque.chequeNumber}',
                                if (cheque.bankName?.isNotEmpty == true) cheque.bankName!,
                                if (cheque.chequeDate.isNotEmpty) cheque.chequeDate,
                              ].join(' · '),
                              trailing: Money.format(cheque.amount),
                            ),
                            if (cheque != rows.last) monitorDivider,
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
