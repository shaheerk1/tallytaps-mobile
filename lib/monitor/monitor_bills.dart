import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'monitor_controller.dart';
import 'monitor_models.dart';
import 'monitor_widgets.dart';

/// Every finalized bill, searchable by invoice number, receipt number or
/// customer code, with the original lines one tap away.
class MonitorBillsTab extends StatefulWidget {
  const MonitorBillsTab({super.key});

  @override
  State<MonitorBillsTab> createState() => _MonitorBillsTabState();
}

class _MonitorBillsTabState extends State<MonitorBillsTab> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  Timer? _debounce;

  String _query = '';
  bool _outstandingOnly = false;
  /// 'hide' leaves out bills that came back in full — they are reversed sales,
  /// not sales. A part-returned bill always stays, marked, at its net value.
  String _returned = 'hide';
  String _loadedKey = '';
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  MonitorInvoicePage _page = MonitorInvoicePage.empty;
  final List<MonitorInvoice> _rows = [];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _key {
    final scope = context.read<MonitorScope>();
    return '${scope.key}|$_query|$_outstandingOnly|$_returned';
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loadingMore || !_page.hasMore) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
      unawaited(_loadMore());
    }
  }

  Future<void> _load() async {
    final key = _key;
    setState(() {
      _loading = true;
      _error = null;
      _loadedKey = key;
    });
    try {
      final page = await context.read<MonitorRepository>().invoices(
        context.read<MonitorScope>(),
        query: _query,
        outstandingOnly: _outstandingOnly,
        returned: _returned,
      );
      if (!mounted || key != _key) return;
      setState(() {
        _page = page;
        _rows
          ..clear()
          ..addAll(page.rows);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final page = await context.read<MonitorRepository>().invoices(
        context.read<MonitorScope>(),
        query: _query,
        outstandingOnly: _outstandingOnly,
        returned: _returned,
        offset: _rows.length,
      );
      if (!mounted) return;
      setState(() {
        _page = page;
        _rows.addAll(page.rows);
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<MonitorScope>();
    // Reload when the period, POS, search text or filter changes.
    if (_loadedKey != _key && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _loadedKey != _key) unawaited(_load());
      });
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Bill number, receipt number or customer',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
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
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
          child: Row(
            children: [
              FilterChip(
                label: const Text('Unpaid only'),
                selected: _outstandingOnly,
                onSelected: (value) {
                  tapHaptic();
                  setState(() => _outstandingOnly = value);
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Returned bills'),
                tooltip: 'Bills returned in full are hidden by default. '
                    'Bills where only part came back always stay in the list.',
                selected: _returned != 'hide',
                onSelected: (value) {
                  tapHaptic();
                  setState(() => _returned = value ? 'show' : 'hide');
                },
              ),
              const Spacer(),
              if (!_loading)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${_page.total} bill${_page.total == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.inkFaint,
                      ),
                    ),
                    Text(
                      _page.hasReturns
                          ? '${Money.format(_page.netTotal)} net · '
                                '${Money.format(_page.returnedTotal)} returned'
                          : '${Money.format(_page.netTotal)} net',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.inkSoft),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (_rows.isEmpty) {
      return const MonitorEmpty(
        message: 'No bills match this period and search.',
        icon: Icons.receipt_long_outlined,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
        itemCount: _rows.length + (_page.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index >= _rows.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              ),
            );
          }
          return _BillTile(invoice: _rows[index]);
        },
      ),
    );
  }
}

class _BillTile extends StatelessWidget {
  const _BillTile({required this.invoice});

  final MonitorInvoice invoice;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(kMonitorRadius),
        boxShadow: cardShadow,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: MonitorRow(
        title: invoice.invoiceNumber,
        subtitle: '${invoice.businessDate} · ${invoice.terminal} · '
            '${invoice.customerCode}',
        // A returned bill shows what it is now worth, not what it once was.
        trailing: Money.format(invoice.netTotal),
        trailingHint: invoice.isReturned
            ? '${invoice.returnLabel} of ${Money.format(invoice.grandTotal)}'
            : invoice.hasBalance
            ? '${Money.format(invoice.balance)} unpaid'
            : 'settled',
        tone: invoice.isFullyReturned
            ? AppColors.inkFaint
            : invoice.hasBalance
            ? AppColors.stock
            : AppColors.ink,
        leading: StatusPill(
          label: invoice.isReturned
              ? invoice.returnLabel
              : prettyStatus(invoice.status),
          tone: invoice.isReturned ? AppColors.negative : statusTone(invoice.status),
        ),
        onTap: () => pushMonitorRoute(
          context,
          MonitorInvoiceScreen(
            nodeId: invoice.nodeId,
            invoiceId: invoice.invoiceId,
            title: invoice.invoiceNumber,
          ),
        ),
      ),
    );
  }
}

/// A bill exactly as the POS recorded it, including both measures on every
/// line and how it was settled.
class MonitorInvoiceScreen extends StatelessWidget {
  const MonitorInvoiceScreen({
    super.key,
    required this.nodeId,
    required this.invoiceId,
    required this.title,
  });

  final String nodeId;
  final String invoiceId;
  final String title;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<MonitorRepository>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: MonitorAsync<MonitorInvoiceDetail>(
        reloadKey: '$nodeId/$invoiceId',
        height: 320,
        load: () => repository.invoice(nodeId, invoiceId),
        builder: (context, detail) => ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            MonitorCard(
              title: 'Bill',
              subtitle: '${detail.invoice.businessDate} · '
                  '${detail.invoice.terminal} · receipt ${detail.invoice.receiptNo}',
              action: StatusPill(
                label: prettyStatus(detail.invoice.status),
                tone: statusTone(detail.invoice.status),
              ),
              child: Column(
                children: [
                  AmountRow(
                    label: 'Customer',
                    amount: detail.invoice.customerCode,
                  ),
                  monitorDivider,
                  AmountRow(label: 'Subtotal', amount: Money.format(detail.subtotal)),
                  if (detail.bagChargeTotal > 0)
                    AmountRow(
                      label: 'Packaging',
                      amount: Money.format(detail.bagChargeTotal),
                    ),
                  if (detail.wageChargeTotal > 0)
                    AmountRow(
                      label: 'Wage',
                      amount: Money.format(detail.wageChargeTotal),
                    ),
                  if (detail.discountTotal > 0)
                    AmountRow(
                      label: 'Discount',
                      amount: '− ${Money.format(detail.discountTotal)}',
                      tone: AppColors.negative,
                    ),
                  monitorDivider,
                  AmountRow(
                    label: 'Total',
                    amount: Money.format(detail.invoice.grandTotal),
                    bold: true,
                  ),
                  AmountRow(
                    label: 'Paid',
                    amount: Money.format(detail.invoice.paidTotal),
                    tone: AppColors.cash,
                  ),
                  if (detail.invoice.hasBalance)
                    AmountRow(
                      label: 'Still owed',
                      amount: Money.format(detail.invoice.balance),
                      tone: AppColors.stock,
                      bold: true,
                    ),
                ],
              ),
            ),
            MonitorCard(
              title: 'Items',
              subtitle: '${detail.lines.length} line'
                  '${detail.lines.length == 1 ? '' : 's'}',
              child: detail.lines.isEmpty
                  ? const MonitorEmpty(message: 'No item lines were archived for this bill.')
                  : Column(
                      children: [
                        for (final line in detail.lines) ...[
                          _LineRow(line: line),
                          if (line != detail.lines.last) monitorDivider,
                        ],
                      ],
                    ),
            ),
            MonitorCard(
              title: 'Settlement',
              child: detail.payments.isEmpty
                  ? const MonitorEmpty(
                      message: 'No payment was recorded against this bill.',
                      icon: Icons.payments_outlined,
                    )
                  : Column(
                      children: [
                        for (final payment in detail.payments)
                          AmountRow(
                            label: _methodName(payment.method),
                            hint: payment.chequeNumber == null
                                ? null
                                : 'Cheque ${payment.chequeNumber}'
                                    '${payment.chequeBank == null ? '' : ' · ${payment.chequeBank}'}',
                            amount: Money.format(payment.amount),
                          ),
                        if (detail.changeAmt > 0) ...[
                          monitorDivider,
                          AmountRow(
                            label: 'Change given',
                            amount: Money.format(detail.changeAmt),
                            tone: AppColors.inkSoft,
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _methodName(String method) => switch (method) {
    'cash' => 'Cash',
    'card' => 'Card',
    'cheque' => 'Cheque',
    'advance' => 'Customer advance',
    'pending' => 'Left on credit',
    _ => prettyStatus(method),
  };
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line});

  final MonitorInvoiceLine line;

  @override
  Widget build(BuildContext context) {
    final rate = '${Money.format(line.unitPrice)} per '
        '${line.pricingBasis == 'kilos' ? (line.baseUom ?? 'kg') : line.handlingUom}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                line.description,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
            Text(
              Money.format(line.total),
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          '${measureText(
            handlingQty: line.handlingQty,
            handlingUom: line.handlingUom,
            baseQty: line.baseQty,
            baseUom: line.baseUom,
          )}  ·  $rate',
          style: const TextStyle(
            fontSize: 11.5,
            color: AppColors.inkFaint,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (line.bagChargeTotal > 0 || line.wageChargeTotal > 0)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              [
                if (line.bagChargeTotal > 0)
                  'packaging ${Money.format(line.bagChargeTotal)}',
                if (line.wageChargeTotal > 0)
                  'wage ${Money.format(line.wageChargeTotal)}',
              ].join('  ·  '),
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.stock,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}
