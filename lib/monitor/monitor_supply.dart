import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'monitor_controller.dart';
import 'monitor_supply_models.dart';
import 'monitor_table.dart';
import 'monitor_widgets.dart';

/// Supply work as the shop keeps it: deliveries in, what is still on the floor,
/// the statements drawn up for each supplier, and what each of them is owed.
class MonitorSupplyTab extends StatefulWidget {
  const MonitorSupplyTab({super.key});

  @override
  State<MonitorSupplyTab> createState() => _MonitorSupplyTabState();
}

class _MonitorSupplyTabState extends State<MonitorSupplyTab> {
  int _view = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                label: Text('Deliveries'),
                icon: Icon(Icons.local_shipping_outlined, size: 18),
              ),
              ButtonSegment(
                value: 1,
                label: Text('On floor'),
                icon: Icon(Icons.layers_outlined, size: 18),
              ),
              ButtonSegment(
                value: 2,
                label: Text('Statements'),
                icon: Icon(Icons.description_outlined, size: 18),
              ),
              ButtonSegment(
                value: 3,
                label: Text('Owed'),
                icon: Icon(Icons.handshake_outlined, size: 18),
              ),
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
          child: switch (_view) {
            0 => const _DeliveriesView(),
            1 => const _ActiveLotsView(),
            2 => const _StatementsView(),
            _ => const _SupplierAccountsView(),
          },
        ),
      ],
    );
  }
}

// ── Deliveries ────────────────────────────────────────────────

class _DeliveriesView extends StatefulWidget {
  const _DeliveriesView();

  @override
  State<_DeliveriesView> createState() => _DeliveriesViewState();
}

class _DeliveriesViewState extends State<_DeliveriesView> {
  String _status = '';

  @override
  Widget build(BuildContext context) {
    final scope = context.watch<MonitorScope>();
    final repository = context.read<MonitorRepository>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
      children: [
        _FilterChips(
          value: _status,
          options: const {'': 'All', 'posted': 'Posted', 'draft': 'Being written'},
          onChanged: (value) => setState(() => _status = value),
        ),
        const SizedBox(height: 8),
        MonitorAsync<List<MonitorGoodsReceipt>>(
          reloadKey: '${scope.key}|$_status',
          height: 260,
          load: () => repository.goodsReceipts(scope, status: _status),
          builder: (context, rows) {
            if (rows.isEmpty) {
              return const MonitorCard(
                title: 'Goods received',
                child: MonitorEmpty(
                  message: 'No delivery was recorded in this period.',
                  icon: Icons.local_shipping_outlined,
                ),
              );
            }
            final value = rows.fold<double>(0, (sum, row) => sum + row.goodsValue);
            final drafts = rows.where((row) => row.isDraft).length;
            return MonitorCard(
              title: 'Goods received',
              subtitle: '${rows.length} note${rows.length == 1 ? '' : 's'} · '
                  '${Money.format(value)} of goods'
                  '${drafts > 0 ? ' · $drafts still being written' : ''}',
              child: Column(
                children: [
                  for (final grn in rows) ...[
                    MonitorRow(
                      leading: StatusPill(
                        label: grn.isDraft ? 'Draft' : prettyStatus(grn.status),
                        tone: grn.isDraft ? AppColors.stock : AppColors.cash,
                      ),
                      title: grn.supplierLabel,
                      subtitle: [
                        grn.grnNumber,
                        grn.businessDate,
                        grn.isOwned ? 'bought' : 'on consignment',
                        if (grn.vehicleNo != null) 'vehicle ${grn.vehicleNo}',
                      ].join(' · '),
                      trailing: grn.goodsValue > 0 ? Money.format(grn.goodsValue) : '—',
                      trailingHint: '${grn.lineCount} line${grn.lineCount == 1 ? '' : 's'}',
                      onTap: () => pushMonitorRoute(
                        context,
                        MonitorGrnScreen(nodeId: grn.nodeId, grnId: grn.grnId, title: grn.grnNumber),
                      ),
                    ),
                    if (grn != rows.last) monitorDivider,
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// One delivery note, line by line.
class MonitorGrnScreen extends StatelessWidget {
  const MonitorGrnScreen({
    super.key,
    required this.nodeId,
    required this.grnId,
    required this.title,
  });

  final String nodeId;
  final String grnId;
  final String title;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<MonitorRepository>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: MonitorAsync<MonitorGoodsReceiptDetail>(
        reloadKey: '$nodeId/$grnId',
        height: 320,
        load: () => repository.goodsReceipt(nodeId, grnId),
        builder: (context, detail) => ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            MonitorCard(
              title: detail.grn.supplierLabel,
              subtitle: '${detail.grn.grnNumber} · ${detail.grn.businessDate}'
                  '${detail.grn.vehicleNo == null ? '' : ' · vehicle ${detail.grn.vehicleNo}'}',
              action: StatusPill(
                label: detail.grn.isDraft ? 'Draft' : prettyStatus(detail.grn.status),
                tone: detail.grn.isDraft ? AppColors.stock : AppColors.cash,
              ),
              child: Column(
                children: [
                  AmountRow(
                    label: 'Agreement',
                    amount: detail.grn.isOwned ? 'Bought outright' : 'On consignment',
                  ),
                  AmountRow(label: 'Lines', amount: '${detail.lines.length}'),
                  monitorDivider,
                  AmountRow(
                    label: 'Goods value',
                    amount: Money.format(detail.total),
                    bold: true,
                  ),
                ],
              ),
            ),
            MonitorCard(
              title: 'What came in',
              subtitle: 'Both measures, and what each line is worth',
              child: detail.lines.isEmpty
                  ? const MonitorEmpty(
                      message: 'No lines were written on this note yet.',
                      icon: Icons.inventory_2_outlined,
                    )
                  : MonitorDataTable(
                      height: 360,
                      columns: const [
                        TableColumnSpec('Item', width: 150),
                        TableColumnSpec('Units', width: 96, numeric: true),
                        TableColumnSpec('Measured', width: 104, numeric: true),
                        TableColumnSpec('Cost', width: 90, numeric: true),
                        TableColumnSpec('Value', width: 104, numeric: true),
                      ],
                      rows: [
                        for (final line in detail.lines)
                          TableRowSpec([
                            line.productName,
                            '${Money.formatQty(line.handlingQty)} ${line.handlingUom}',
                            line.baseQty == null
                                ? '—'
                                : '${Money.formatQty(line.baseQty!)} ${line.baseUom ?? ''}',
                            Money.format(line.unitCost),
                            Money.format(line.lineValue),
                          ]),
                      ],
                      footer: TableRowSpec([
                        'Total',
                        '',
                        '',
                        '',
                        Money.format(detail.total),
                      ], emphasis: true),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── What is on the floor ──────────────────────────────────────

class _ActiveLotsView extends StatefulWidget {
  const _ActiveLotsView();

  @override
  State<_ActiveLotsView> createState() => _ActiveLotsViewState();
}

class _ActiveLotsViewState extends State<_ActiveLotsView> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _includeEmpty = false;

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
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search item, lot code or supplier',
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
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
          child: Row(
            children: [
              FilterChip(
                label: const Text('Include emptied lots'),
                selected: _includeEmpty,
                onSelected: (value) {
                  tapHaptic();
                  setState(() => _includeEmpty = value);
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
            children: [
              MonitorAsync<List<MonitorActiveLot>>(
                reloadKey: '${scope.placeKey}|$_query|$_includeEmpty',
                height: 260,
                load: () => repository.activeLots(
                  scope,
                  query: _query,
                  includeEmpty: _includeEmpty,
                ),
                builder: (context, lots) {
                  if (lots.isEmpty) {
                    return const MonitorCard(
                      title: 'Stock on the floor',
                      child: MonitorEmpty(
                        message: 'Nothing is open right now.',
                        icon: Icons.layers_outlined,
                      ),
                    );
                  }
                  final byItem = <String, List<MonitorActiveLot>>{};
                  for (final lot in lots) {
                    byItem.putIfAbsent(lot.productName, () => []).add(lot);
                  }
                  final names = byItem.keys.toList()..sort();
                  return Column(
                    children: [
                      MonitorCard(
                        title: 'Stock on the floor',
                        subtitle: '${lots.length} lot${lots.length == 1 ? '' : 's'} '
                            'across ${names.length} item${names.length == 1 ? '' : 's'}'
                            '${_includeEmpty ? ' · emptied ones included' : ''}',
                        child: const SizedBox.shrink(),
                      ),
                      for (final name in names)
                        _LotGroupCard(name: name, lots: byItem[name]!),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LotGroupCard extends StatelessWidget {
  const _LotGroupCard({required this.name, required this.lots});

  final String name;
  final List<MonitorActiveLot> lots;

  @override
  Widget build(BuildContext context) {
    final handling = lots.fold<double>(0, (sum, lot) => sum + lot.remainingHandling);
    final base = lots
        .where((lot) => lot.remainingBase != null)
        .fold<double>(0, (sum, lot) => sum + lot.remainingBase!);
    final uom = lots.first.handlingUom;
    final baseUom = lots.firstWhere(
      (lot) => lot.baseUom != null,
      orElse: () => lots.first,
    ).baseUom;
    return MonitorCard(
      title: name,
      subtitle: '${Money.formatQty(handling)} $uom'
          '${base > 0 ? ' · ${Money.formatQty(base)} ${baseUom ?? ''}' : ''} left '
          'in ${lots.length} lot${lots.length == 1 ? '' : 's'}',
      child: Column(
        children: [
          for (final lot in lots) ...[
            MonitorRow(
              leading: StatusPill(
                label: lot.lotTag ?? 'lot',
                tone: lot.isOwned ? AppColors.cash : AppColors.stock,
              ),
              title: lot.supplierName ?? 'Supplier not named',
              subtitle: [
                lot.isOwned ? 'bought' : 'on consignment',
                lot.ageText,
                'took in ${lot.receivedText}',
              ].join(' · '),
              trailing: lot.isEmpty ? 'empty' : lot.remainingText,
              trailingHint: lot.isEmpty ? null : 'still here',
              tone: lot.isEmpty ? AppColors.inkFaint : AppColors.ink,
            ),
            if (lot != lots.last) monitorDivider,
          ],
        ],
      ),
    );
  }
}

// ── Statements ────────────────────────────────────────────────

class _StatementsView extends StatefulWidget {
  const _StatementsView();

  @override
  State<_StatementsView> createState() => _StatementsViewState();
}

class _StatementsViewState extends State<_StatementsView> {
  String _status = '';

  @override
  Widget build(BuildContext context) {
    final scope = context.watch<MonitorScope>();
    final repository = context.read<MonitorRepository>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
      children: [
        _FilterChips(
          value: _status,
          options: const {
            '': 'All',
            'draft': 'Draft',
            'reviewed': 'Reviewed',
            'finalized': 'Finalized',
          },
          onChanged: (value) => setState(() => _status = value),
        ),
        const SizedBox(height: 8),
        MonitorAsync<List<MonitorStatement>>(
          reloadKey: '${scope.key}|$_status',
          height: 260,
          load: () => repository.statements(scope, status: _status),
          builder: (context, rows) {
            if (rows.isEmpty) {
              return const MonitorCard(
                title: 'Supplier statements',
                child: MonitorEmpty(
                  message: 'No statement was drawn up in this period.',
                  icon: Icons.description_outlined,
                ),
              );
            }
            final payable = rows
                .where((row) => row.status == 'finalized')
                .fold<double>(0, (sum, row) => sum + row.netPayable);
            return MonitorCard(
              title: 'Supplier statements',
              subtitle: '${rows.length} statement${rows.length == 1 ? '' : 's'}'
                  '${payable > 0 ? ' · ${Money.format(payable)} finalized' : ''}',
              child: Column(
                children: [
                  for (final statement in rows) ...[
                    MonitorRow(
                      leading: StatusPill(
                        label: prettyStatus(statement.status),
                        tone: statusTone(statement.status),
                      ),
                      title: statement.supplierLabel,
                      subtitle: [
                        statement.statementNumber,
                        statement.typeLabel,
                        statement.periodText,
                      ].join(' · '),
                      trailing: Money.format(statement.netPayable),
                      trailingHint: statement.commissionAmount > 0
                          ? 'commission ${Money.format(statement.commissionAmount)}'
                          : null,
                      tone: statement.isVoid ? AppColors.inkFaint : AppColors.ink,
                      onTap: () => pushMonitorRoute(
                        context,
                        MonitorStatementScreen(
                          nodeId: statement.nodeId,
                          statementId: statement.statementId,
                          title: statement.statementNumber,
                        ),
                      ),
                    ),
                    if (statement != rows.last) monitorDivider,
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// One statement, with its lines and its credits and deductions.
class MonitorStatementScreen extends StatelessWidget {
  const MonitorStatementScreen({
    super.key,
    required this.nodeId,
    required this.statementId,
    required this.title,
  });

  final String nodeId;
  final String statementId;
  final String title;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<MonitorRepository>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: MonitorAsync<MonitorStatementDetail>(
        reloadKey: '$nodeId/$statementId',
        height: 320,
        load: () => repository.statement(nodeId, statementId),
        builder: (context, detail) {
          final statement = detail.statement;
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
            children: [
              MonitorCard(
                title: statement.supplierLabel,
                subtitle: '${statement.typeLabel} · ${statement.periodText}',
                action: StatusPill(
                  label: prettyStatus(statement.status),
                  tone: statusTone(statement.status),
                ),
                child: Column(
                  children: [
                    AmountRow(
                      label: statement.isPurchase ? 'Purchase subtotal' : 'Sales subtotal',
                      amount: Money.format(statement.merchandiseSubtotal),
                    ),
                    if (statement.commissionAmount > 0)
                      AmountRow(
                        label: 'Commission (${Money.formatQty(statement.commissionRate)}%)',
                        amount: '− ${Money.format(statement.commissionAmount)}',
                        tone: AppColors.negative,
                      ),
                    if (detail.bagChargeTotal > 0)
                      AmountRow(
                        label: 'Packaging',
                        amount: Money.format(detail.bagChargeTotal),
                      ),
                    if (detail.wageChargeTotal > 0)
                      AmountRow(label: 'Wage', amount: Money.format(detail.wageChargeTotal)),
                    if (statement.adjustmentTotal != 0)
                      AmountRow(
                        label: 'Credits and deductions',
                        amount: Money.format(statement.adjustmentTotal),
                        tone: statement.adjustmentTotal < 0
                            ? AppColors.negative
                            : AppColors.positive,
                      ),
                    monitorDivider,
                    AmountRow(
                      label: 'Net payable',
                      amount: Money.format(statement.netPayable),
                      bold: true,
                    ),
                    if (detail.voidReason != null)
                      AmountRow(
                        label: 'Voided',
                        amount: detail.voidReason!,
                        tone: AppColors.negative,
                      ),
                  ],
                ),
              ),
              MonitorCard(
                title: 'Lines',
                subtitle: '${detail.lines.length} line${detail.lines.length == 1 ? '' : 's'} '
                    'behind this statement',
                child: detail.lines.isEmpty
                    ? const MonitorEmpty(
                        message: 'No lines are attached to this statement yet.',
                        icon: Icons.list_alt_outlined,
                      )
                    : MonitorDataTable(
                        height: 380,
                        columns: const [
                          TableColumnSpec('Item', width: 150),
                          TableColumnSpec('Kind', width: 100),
                          TableColumnSpec('Units', width: 88, numeric: true),
                          TableColumnSpec('Measured', width: 96, numeric: true),
                          TableColumnSpec('Rate', width: 90, numeric: true),
                          TableColumnSpec('Amount', width: 108, numeric: true),
                        ],
                        rows: [
                          for (final line in detail.lines)
                            TableRowSpec([
                              line.description,
                              line.kindLabel,
                              Money.formatQty(line.quantity),
                              line.kilos == null ? '—' : Money.formatQty(line.kilos!),
                              Money.format(line.unitPrice),
                              Money.format(line.amount),
                            ]),
                        ],
                        footer: TableRowSpec([
                          'Subtotal',
                          '',
                          '',
                          '',
                          '',
                          Money.format(statement.merchandiseSubtotal),
                        ], emphasis: true),
                      ),
              ),
              if (detail.adjustments.isNotEmpty)
                MonitorCard(
                  title: 'Credits and deductions',
                  subtitle: 'Line by line, as the statement shows them',
                  child: Column(
                    children: [
                      for (final adjustment in detail.adjustments) ...[
                        AmountRow(
                          label: adjustment.label,
                          hint: adjustment.note,
                          amount: Money.format(adjustment.amount),
                          tone: adjustment.isCredit
                              ? AppColors.positive
                              : AppColors.negative,
                        ),
                        if (adjustment != detail.adjustments.last) monitorDivider,
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ── What suppliers are owed ───────────────────────────────────

class _SupplierAccountsView extends StatelessWidget {
  const _SupplierAccountsView();

  @override
  Widget build(BuildContext context) {
    final scope = context.watch<MonitorScope>();
    final repository = context.read<MonitorRepository>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
      children: [
        MonitorAsync<List<MonitorSupplierAccount>>(
          reloadKey: scope.placeKey,
          height: 260,
          load: () => repository.supplierAccounts(scope),
          builder: (context, rows) {
            if (rows.isEmpty) {
              return const MonitorCard(
                title: 'Owed to suppliers',
                child: MonitorEmpty(
                  message: 'Nothing is owed to a supplier right now.',
                  icon: Icons.handshake_outlined,
                ),
              );
            }
            final owed = rows
                .where((row) => row.balance > 0)
                .fold<double>(0, (sum, row) => sum + row.balance);
            return MonitorCard(
              title: 'Owed to suppliers',
              subtitle: '${Money.format(owed)} across '
                  '${rows.where((row) => row.balance > 0).length} supplier'
                  '${rows.where((row) => row.balance > 0).length == 1 ? '' : 's'} · '
                  'not tied to the dates above',
              child: Column(
                children: [
                  for (final account in rows) ...[
                    MonitorRow(
                      title: account.supplierName,
                      subtitle: [
                        if (account.supplierCode != null) account.supplierCode!,
                        '${account.statements} statement${account.statements == 1 ? '' : 's'}',
                        if (account.lastPayment != null) 'last paid ${account.lastPayment}',
                      ].join(' · '),
                      trailing: Money.format(account.balance.abs()),
                      trailingHint: account.isSettled
                          ? 'settled'
                          : account.theyOweUs
                          ? 'they owe us'
                          : 'to pay',
                      tone: account.isSettled
                          ? AppColors.inkFaint
                          : account.theyOweUs
                          ? AppColors.positive
                          : AppColors.stock,
                      onTap: () => pushMonitorRoute(
                        context,
                        MonitorSupplierAccountScreen(
                          supplierId: account.supplierId,
                          title: account.supplierName,
                        ),
                      ),
                    ),
                    if (account != rows.last) monitorDivider,
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// One supplier's account, as the running sheet the desktop prints.
class MonitorSupplierAccountScreen extends StatelessWidget {
  const MonitorSupplierAccountScreen({
    super.key,
    required this.supplierId,
    required this.title,
  });

  final String supplierId;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scope = context.watch<MonitorScope>();
    final repository = context.read<MonitorRepository>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: MonitorAsync<MonitorAccountSheet>(
        reloadKey: '${scope.placeKey}|$supplierId',
        height: 320,
        load: () => repository.supplierAccountSheet(scope, supplierId),
        builder: (context, sheet) => ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            MonitorCard(
              title: sheet.supplierName,
              subtitle: sheet.supplierCode ?? 'Everything owed and paid, from the start',
              child: Column(
                children: [
                  AmountRow(
                    label: 'Owed from statements',
                    amount: Money.format(sheet.totalOwed),
                  ),
                  AmountRow(
                    label: 'Paid and deducted',
                    amount: '− ${Money.format(sheet.totalPaid)}',
                    tone: AppColors.positive,
                  ),
                  monitorDivider,
                  AmountRow(
                    label: sheet.balance < 0 ? 'They owe us' : 'Still to pay',
                    amount: Money.format(sheet.balance.abs()),
                    bold: true,
                    tone: sheet.balance < 0 ? AppColors.positive : AppColors.stock,
                  ),
                ],
              ),
            ),
            MonitorCard(
              title: 'Account sheet',
              subtitle: 'Oldest first, with the running balance',
              child: sheet.lines.isEmpty
                  ? const MonitorEmpty(
                      message: 'Nothing has been recorded on this account yet.',
                      icon: Icons.receipt_long_outlined,
                    )
                  : MonitorDataTable(
                      height: 420,
                      columns: const [
                        TableColumnSpec('Date', width: 92),
                        TableColumnSpec('Reference', width: 150),
                        TableColumnSpec('What it is', width: 170),
                        TableColumnSpec('Owed', width: 104, numeric: true),
                        TableColumnSpec('Paid', width: 104, numeric: true),
                        TableColumnSpec('Balance', width: 110, numeric: true),
                      ],
                      rows: [
                        for (final line in sheet.lines)
                          TableRowSpec(
                            [
                              line.date,
                              line.reference,
                              line.detail == null || line.detail!.isEmpty
                                  ? line.description
                                  : '${line.description} · ${line.detail}',
                              line.owed > 0 ? Money.format(line.owed) : '',
                              line.paid > 0 ? Money.format(line.paid) : '',
                              Money.format(line.balance),
                            ],
                            struckThrough: line.reversed,
                          ),
                      ],
                      footer: TableRowSpec([
                        'Totals',
                        '',
                        '',
                        Money.format(sheet.totalOwed),
                        Money.format(sheet.totalPaid),
                        Money.format(sheet.balance),
                      ], emphasis: true),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared ────────────────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final entry in options.entries)
          ChoiceChip(
            label: Text(entry.value),
            selected: value == entry.key,
            onSelected: (_) {
              tapHaptic();
              onChanged(entry.key);
            },
          ),
      ],
    );
  }
}
