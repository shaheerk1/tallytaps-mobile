import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'supply_check_models.dart';
import 'supply_statement_sheet.dart';

/// One statement that can be sent: a day of it, or the whole thing.
class _Sheet {
  const _Sheet({required this.tab, required this.heading, required this.group, required this.file});

  final String tab, heading, file;
  final SupplyCheckGroup group;
}

/// Handing a supplier what their goods came to.
///
/// Broken into days, each day is its own statement, because that is how a
/// supply is usually settled -- and there is one for the whole range beside
/// them, for when it is settled in one go.
class SupplyStatementExportScreen extends StatefulWidget {
  const SupplyStatementExportScreen({
    super.key,
    required this.lines,
    required this.commissionPercent,
    required this.groupByDate,
    required this.fromDate,
    required this.toDate,
  });

  final List<SaleLine> lines;
  final double commissionPercent;
  final bool groupByDate;
  final String fromDate, toDate;

  @override
  State<SupplyStatementExportScreen> createState() => _SupplyStatementExportScreenState();
}

class _SupplyStatementExportScreenState extends State<SupplyStatementExportScreen> {
  final _boundary = GlobalKey();
  int _chosen = 0;
  bool _busy = false;

  String get _rangeLabel =>
      widget.fromDate == widget.toDate ? widget.fromDate : '${widget.fromDate} to ${widget.toDate}';

  /// Every sheet on offer: a day each, and the whole range together.
  List<_Sheet> get _sheets {
    final whole = SupplyCheckSummary.of(
      widget.lines,
      commissionPercent: widget.commissionPercent,
    ).groups;
    final all = _Sheet(
      tab: 'All together',
      heading: _rangeLabel,
      group: whole.isEmpty
          ? const SupplyCheckGroup(label: '', rows: [], merchandise: 0, commission: 0, netPayable: 0)
          : whole.single,
      file: 'statement-${widget.fromDate}-to-${widget.toDate}',
    );
    if (!widget.groupByDate) return [all];

    final byDay = SupplyCheckSummary.of(
      widget.lines,
      commissionPercent: widget.commissionPercent,
      groupByDate: true,
    ).groups;
    return [
      for (final day in byDay)
        _Sheet(tab: day.label, heading: day.label, group: day, file: 'statement-${day.label}'),
      // The whole range last: a day is what is usually sent.
      if (byDay.length > 1) all,
    ];
  }

  Future<void> _share({required bool everything}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final sheets = _sheets;
      if (everything && sheets.length > 1) {
        // Each sheet has to be drawn before it can be caught, so they go one
        // after another, with the screen showing each as it is taken.
        for (var index = 0; index < sheets.length; index += 1) {
          setState(() => _chosen = index);
          await Future<void>.delayed(const Duration(milliseconds: 60));
          if (!mounted) return;
          await _shareOne(sheets[index]);
        }
      } else {
        await _shareOne(sheets[_chosen]);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareOne(_Sheet sheet) async {
    final png = await captureSheet(_boundary);
    if (png == null || !mounted) return;
    await shareSheet(png, sheet.file, message: 'Sale · ${sheet.heading}');
  }

  @override
  Widget build(BuildContext context) {
    final sheets = _sheets;
    final chosen = sheets[_chosen.clamp(0, sheets.length - 1)];
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Send a statement'),
            Text(
              'Goods and money only — no names, no codes',
              style: TextStyle(
                color: AppColors.inkSoft,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (sheets.length > 1)
            SizedBox(
              height: 50,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
                itemCount: sheets.length,
                separatorBuilder: (_, _) => const SizedBox(width: 7),
                itemBuilder: (context, index) => ChoiceChip(
                  key: ValueKey('statement-tab-$index'),
                  label: Text(sheets[index].tab),
                  selected: index == _chosen,
                  showCheckmark: false,
                  onSelected: (_) {
                    tapHaptic();
                    setState(() => _chosen = index);
                  },
                ),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Center(
                // Drawn at the sheet's own width, then scaled to the phone, so
                // what is caught is the whole sheet rather than what fitted.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: RepaintBoundary(
                    key: _boundary,
                    child: SupplyStatementSheet(
                      heading: chosen.heading,
                      group: chosen.group,
                      commissionPercent: widget.commissionPercent,
                      footnote: widget.commissionPercent > 0
                          ? null
                          : 'Goods only. No commission has been taken off.',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 14)],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('share-this-statement'),
                  onPressed: _busy ? null : () => _share(everything: false),
                  icon: const Icon(Icons.ios_share_rounded),
                  label: Text(_busy ? 'Working…' : 'Send this one'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              if (sheets.length > 1) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const ValueKey('share-every-statement'),
                  onPressed: _busy ? null : () => _share(everything: true),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Send each'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
