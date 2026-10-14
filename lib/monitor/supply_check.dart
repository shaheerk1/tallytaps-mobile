import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../data/supply_check_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'monitor_controller.dart';
import 'monitor_widgets.dart';
import 'supply_check_models.dart';
import 'supply_statement_export.dart';

/// Checking a supply against the sales it went out on.
///
/// The shop bills goods with a supply code typed on the line. Days later
/// somebody has to work out what one supply came to -- across several days,
/// several codes, and the odd code typed wrongly. So this lists the lines
/// themselves, lets a person pick the ones that really belong, and adds them up
/// the way a statement does: by item, by the rate it went out at.
///
/// Nothing here writes to the shop. A check is working out, not a statement:
/// lines are never locked, and the same line can be used in two checks on
/// purpose, because one day's goods are often looked at from two angles.
class SupplyCheckView extends StatefulWidget {
  const SupplyCheckView({super.key});

  @override
  State<SupplyCheckView> createState() => _SupplyCheckViewState();
}

/// Supply codes as somebody types them.
///
/// Only a comma separates one from the next, because a good many codes hold
/// spaces -- "SBT IO BEST" is one code, not three. Spacing inside a code is
/// tidied so a stray double space is not a different code, which is the same
/// tidying the server does before it compares.
List<String> supplyCodesOf(String typed) => typed
    .split(',')
    .map((code) => code.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase())
    .where((code) => code.isNotEmpty)
    .toSet()
    .toList();

class _SupplyCheckViewState extends State<SupplyCheckView> {
  final _supplyController = TextEditingController();
  final _checks = SupplyCheckRepository();
  Timer? _debounce;

  List<String> _supplierCodes = const [];
  List<String> _itemCodes = const [];
  final Set<String> _selected = {};
  Map<String, int> _usage = const {};

  SaleLinePage _page = SaleLinePage.empty;
  bool _loading = false;
  String? _error;
  String _loadedKey = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _supplyController.dispose();
    super.dispose();
  }

  /// Everything the list depends on, so a change to any of it reloads once.
  String _key(MonitorScope scope) =>
      '${scope.key}|${_supplierCodes.join(',')}|${_itemCodes.join(',')}';

  Future<void> _load(MonitorScope scope, MonitorRepository repository) async {
    final key = _key(scope);
    setState(() {
      _loading = true;
      _error = null;
      _loadedKey = key;
    });
    try {
      final page = await repository.saleLines(
        scope,
        itemCodes: _itemCodes,
        supplierCodes: _supplierCodes,
      );
      if (!mounted || _loadedKey != key) return;
      setState(() {
        _page = page;
        _loading = false;
        // A line that is no longer listed cannot stay picked.
        final listed = page.lines.map((line) => line.id).toSet();
        _selected.removeWhere((id) => !listed.contains(id));
      });
      await _loadUsage(key, page);
    } catch (error) {
      if (!mounted || _loadedKey != key) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  /// How often each line has been counted already.
  ///
  /// A hint beside a line, nothing more, so it is fetched after the lines are
  /// on screen and a failure to read it leaves the lines exactly where they are.
  Future<void> _loadUsage(String key, SaleLinePage page) async {
    try {
      final usage = await _checks.usage(page.lines.map((line) => line.id));
      if (mounted && _loadedKey == key) setState(() => _usage = usage);
    } catch (_) {
      // No hint this time; the lines matter more.
    }
  }

  void _onSupplyCodesChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      final codes = supplyCodesOf(value);
      if (codes.join(',') == _supplierCodes.join(',')) return;
      setState(() => _supplierCodes = codes);
    });
  }

  List<SaleLine> get _chosen =>
      _page.lines.where((line) => _selected.contains(line.id)).toList();

  @override
  Widget build(BuildContext context) {
    final scope = context.watch<MonitorScope>();
    final repository = context.read<MonitorRepository>();
    if (_loadedKey != _key(scope) && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(scope, repository));
    }
    final lines = _page.lines;
    final allPicked = lines.isNotEmpty && lines.every((line) => _selected.contains(line.id));

    // The filters scroll with the lines rather than sitting above them. Pinned,
    // they took more height than a phone has left once the keyboard is up, and
    // the whole view overflowed; this way any screen is tall enough.
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(scope, repository),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _filters(context, lines.length)),
                if (_loading)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else if (_error != null)
                  SliverToBoxAdapter(
                    child: MonitorCard(
                      title: 'Sale lines',
                      child: MonitorEmpty(message: _error!, icon: Icons.cloud_off_rounded),
                    ),
                  )
                else if (lines.isEmpty)
                  const SliverToBoxAdapter(
                    child: MonitorCard(
                      title: 'Sale lines',
                      child: MonitorEmpty(
                        message: 'No sale lines in this range. Widen the dates, or clear the filters.',
                        icon: Icons.receipt_long_outlined,
                      ),
                    ),
                  )
                else ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: _selectAllRow(allPicked, lines),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(12, 0, 12, _selected.isEmpty ? 24 : 108),
                    sliver: SliverList.builder(
                      itemCount: lines.length,
                      itemBuilder: (context, index) {
                        final line = lines[index];
                        return _LineRow(
                          key: ValueKey('sale-line-${line.id}'),
                          line: line,
                          picked: _selected.contains(line.id),
                          usedInChecks: _usage[line.id] ?? 0,
                          onToggle: () {
                            tapHaptic();
                            setState(() {
                              if (!_selected.remove(line.id)) _selected.add(line.id);
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_selected.isNotEmpty) _summaryBar(scope),
      ],
    );
  }

  /// The two things that narrow the lines, and what they left.
  ///
  /// Both sit in one card so they read as one question -- which supply, and
  /// which of its items -- instead of as loose controls stacked on a list.
  Widget _filters(BuildContext context, int listed) => Container(
    margin: const EdgeInsets.fromLTRB(14, 2, 14, 10),
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: cardShadow,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MonitorSearchField(
          key: const ValueKey('supply-code-filter'),
          controller: _supplyController,
          hintText: 'Supply codes, separated by commas',
          helperText: 'A code may hold spaces. Only a comma starts the next one.',
          textCapitalization: TextCapitalization.characters,
          onChanged: _onSupplyCodesChanged,
          onClear: () => setState(() => _supplierCodes = const []),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _FilterButton(
                key: const ValueKey('item-code-filter'),
                icon: Icons.inventory_2_outlined,
                label: _itemCodes.isEmpty
                    ? 'All items'
                    : '${_itemCodes.length} item code${_itemCodes.length == 1 ? '' : 's'}',
                chosen: _itemCodes.isNotEmpty,
                onTap: _page.itemCodes.isEmpty ? null : _pickItemCodes,
              ),
            ),
            const SizedBox(width: 8),
            _FilterButton(
              icon: Icons.bookmark_outline_rounded,
              label: 'Saved',
              chosen: false,
              onTap: _openSaved,
            ),
          ],
        ),
        if (_supplierCodes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final code in _supplierCodes) SupplyCodeChip(code: code),
            ],
          ),
        ],
        if (listed > 0 || _loading)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                Icon(
                  _page.hasMore ? Icons.filter_alt_outlined : Icons.check_circle_outline_rounded,
                  size: 14,
                  color: _page.hasMore ? AppColors.stock : AppColors.inkFaint,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _loading
                        ? 'Looking…'
                        : _page.hasMore
                        ? '$listed of ${_page.total} lines — narrow the dates or the codes for the rest'
                        : '$listed line${listed == 1 ? '' : 's'}'
                              '${_selected.isEmpty ? '' : ' · ${_selected.length} picked'}',
                    style: TextStyle(
                      color: _page.hasMore ? AppColors.stock : AppColors.inkSoft,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _selectAllRow(bool allPicked, List<SaleLine> lines) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Checkbox(
          key: const ValueKey('select-all-lines'),
          value: allPicked,
          tristate: false,
          onChanged: (_) {
            tapHaptic();
            setState(() {
              if (allPicked) {
                _selected.removeAll(lines.map((line) => line.id));
              } else {
                _selected.addAll(lines.map((line) => line.id));
              }
            });
          },
        ),
        Text(
          allPicked ? 'Clear all' : 'Select all listed',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
        const Spacer(),
        if (_selected.isNotEmpty)
          Text(
            '${_selected.length} picked',
            style: const TextStyle(color: AppColors.inkSoft, fontSize: 12),
          ),
      ],
    ),
  );

  Widget _summaryBar(MonitorScope scope) {
    final summary = SupplyCheckSummary.of(_chosen);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 16, offset: Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: FilledButton(
          key: const ValueKey('open-supply-summary'),
          onPressed: () => _openSummary(scope),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.ink,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: Row(
            children: [
              Badge(
                label: Text('${_selected.length}'),
                child: const Icon(Icons.summarize_outlined),
              ),
              const SizedBox(width: 13),
              const Expanded(
                child: Text(
                  'Summary',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                Money.format(summary.merchandise),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickItemCodes() async {
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ItemCodeSheet(options: _page.itemCodes, chosen: _itemCodes),
    );
    if (picked == null || !mounted) return;
    setState(() => _itemCodes = picked);
  }

  Future<void> _openSummary(MonitorScope scope) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SupplyCheckSummaryScreen(
          lines: _chosen,
          fromDate: scope.fromIso,
          toDate: scope.toIso,
          placeLabel: scope.placeLabel,
          locCode: scope.locCode,
          macCode: scope.macCode,
          supplierCodes: _supplierCodes,
          itemCodes: _itemCodes,
        ),
      ),
    );
    if (saved == true && mounted) await _loadUsage(_loadedKey, _page);
  }

  Future<void> _openSaved() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SavedChecksScreen()),
    );
    if (!mounted) return;
    await _loadUsage(_loadedKey, _page);
  }
}

// ── One line ──────────────────────────────────────────────────

class _LineRow extends StatelessWidget {
  const _LineRow({
    super.key,
    required this.line,
    required this.picked,
    required this.usedInChecks,
    required this.onToggle,
  });

  final SaleLine line;
  final bool picked;
  final int usedInChecks;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final measures = <String>[
      '${Money.formatQty(line.netHandling)} ${line.handlingUom}',
      if (line.netBase != null) '${Money.formatQty(line.netBase!)} ${line.baseUom ?? ''}'.trim(),
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      color: picked ? AppColors.brand.withValues(alpha: .07) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: picked ? AppColors.brand : AppColors.line),
      ),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(value: picked, onChanged: (_) => onToggle()),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${line.itemCode}  ${line.description}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                          ),
                        ),
                        if (line.supplierCode != null)
                          SupplyCodeChip(code: line.supplierCode!),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${line.date} · bill ${line.receiptNo} · $measures × ${Money.format(line.unitPrice)}',
                      style: const TextStyle(color: AppColors.inkSoft, fontSize: 11.5),
                    ),
                    if (line.wasReturned)
                      Text(
                        'Part came back · counted at what is left',
                        style: TextStyle(
                          color: AppColors.negative.withValues(alpha: .9),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (usedInChecks > 0)
                      Text(
                        'Already in $usedInChecks saved check${usedInChecks == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: AppColors.inkFaint,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                Money.format(line.netMerchandise),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Picking item codes ────────────────────────────────────────

class _ItemCodeSheet extends StatefulWidget {
  const _ItemCodeSheet({required this.options, required this.chosen});

  final List<SaleLineItemCode> options;
  final List<String> chosen;

  @override
  State<_ItemCodeSheet> createState() => _ItemCodeSheetState();
}

class _ItemCodeSheetState extends State<_ItemCodeSheet> {
  late final Set<String> _chosen = widget.chosen.toSet();
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final query = _search.trim().toLowerCase();
    final shown = widget.options
        .where(
          (option) =>
              query.isEmpty ||
              option.itemCode.toLowerCase().contains(query) ||
              option.description.toLowerCase().contains(query),
        )
        .toList();
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Which items?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('item-code-search'),
            autofocus: false,
            onChanged: (value) => setState(() => _search = value),
            decoration: const InputDecoration(
              hintText: 'Search item code or name',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: shown.length,
              itemBuilder: (context, index) {
                final option = shown[index];
                final picked = _chosen.contains(option.itemCode);
                return CheckboxListTile(
                  key: ValueKey('item-code-${option.itemCode}'),
                  dense: true,
                  value: picked,
                  title: Text(
                    '${option.itemCode}  ${option.description}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  subtitle: Text(
                    '${option.lineCount} line${option.lineCount == 1 ? '' : 's'} · ${Money.format(option.merchandise)}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  onChanged: (_) => setState(() {
                    if (!_chosen.remove(option.itemCode)) _chosen.add(option.itemCode);
                  }),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: () => setState(_chosen.clear),
                child: const Text('All items'),
              ),
              const Spacer(),
              FilledButton(
                key: const ValueKey('item-codes-done'),
                onPressed: () => Navigator.pop(context, _chosen.toList()..sort()),
                child: const Text('Done'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── The summary ───────────────────────────────────────────────

/// What the picked lines come to, and the two dials that change it.
class SupplyCheckSummaryScreen extends StatefulWidget {
  const SupplyCheckSummaryScreen({
    super.key,
    required this.lines,
    required this.fromDate,
    required this.toDate,
    this.placeLabel,
    this.locCode,
    this.macCode,
    this.supplierCodes = const [],
    this.itemCodes = const [],
    this.readOnlyTitle,
    this.initialCommission = 0,
    this.initialGroupByDate = false,
  });

  final List<SaleLine> lines;
  final String fromDate, toDate;
  final String? placeLabel, locCode, macCode;
  final List<String> supplierCodes, itemCodes;

  /// Set when an already saved check is being read back, which cannot be saved again.
  final String? readOnlyTitle;
  final double initialCommission;
  final bool initialGroupByDate;

  @override
  State<SupplyCheckSummaryScreen> createState() => _SupplyCheckSummaryScreenState();
}

class _SupplyCheckSummaryScreenState extends State<SupplyCheckSummaryScreen> {
  late final TextEditingController _commission = TextEditingController(
    text: widget.initialCommission == 0 ? '' : '${widget.initialCommission}',
  );
  late bool _groupByDate = widget.initialGroupByDate;
  bool _saving = false;

  @override
  void dispose() {
    _commission.dispose();
    super.dispose();
  }

  double get _percent {
    final value = double.tryParse(_commission.text.trim()) ?? 0;
    return value.isFinite ? value.clamp(0, 100).toDouble() : 0;
  }

  @override
  Widget build(BuildContext context) {
    final summary = SupplyCheckSummary.of(
      widget.lines,
      commissionPercent: _percent,
      groupByDate: _groupByDate,
    );
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.readOnlyTitle ?? 'Supply summary'),
            Text(
              '${widget.lines.length} line${widget.lines.length == 1 ? '' : 's'} · '
              '${widget.fromDate == widget.toDate ? widget.fromDate : '${widget.fromDate} → ${widget.toDate}'}',
              style: const TextStyle(
                color: AppColors.inkSoft,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 120),
        children: [
          _controls(),
          const SizedBox(height: 12),
          for (final group in summary.groups) _groupCard(group, summary.groups.length > 1),
          const SizedBox(height: 10),
          _totalCard(summary),
          if (summary.packagingAndWage > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Packaging and wage charges on these lines come to '
                '${Money.format(summary.packagingAndWage)}. They are not part of the goods value above.',
                style: const TextStyle(color: AppColors.inkSoft, fontSize: 12, height: 1.4),
              ),
            ),
          if (summary.returnedLineCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${summary.returnedLineCount} of these lines had goods come back. '
                'Each is counted at what is left of it.',
                style: const TextStyle(color: AppColors.inkSoft, fontSize: 12, height: 1.4),
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
                    if (widget.readOnlyTitle == null)
                      Expanded(
                        child: FilledButton.icon(
                          key: const ValueKey('save-supply-check'),
                          onPressed: _saving || widget.lines.isEmpty ? null : _save,
                          icon: const Icon(Icons.bookmark_add_outlined),
                          label: Text(_saving ? 'Saving…' : 'Save'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.brand,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                    if (widget.readOnlyTitle == null) const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        key: const ValueKey('open-statement-export'),
                        onPressed: widget.lines.isEmpty ? null : _export,
                        icon: const Icon(Icons.ios_share_rounded),
                        label: const Text('Send statement'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.ink,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _controls() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: cardShadow,
    ),
    child: Column(
      children: [
        SwitchListTile(
          key: const ValueKey('group-by-date'),
          contentPadding: EdgeInsets.zero,
          value: _groupByDate,
          onChanged: (value) {
            tapHaptic();
            setState(() => _groupByDate = value);
          },
          title: const Text(
            'Break it down by date',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          subtitle: Text(
            _groupByDate
                ? 'Each day shows its own goods, commission and net.'
                : 'One summary over the whole range.',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          key: const ValueKey('commission-percent'),
          controller: _commission,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Sale commission',
            suffixText: '%',
            helperText: 'Taken off the goods value to give the net payable.',
            prefixIcon: Icon(Icons.percent_rounded),
          ),
        ),
      ],
    ),
  );

  Widget _groupCard(SupplyCheckGroup group, bool showLabel) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: cardShadow,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabel)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              group.label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
            ),
          ),
        for (final row in group.rows) _row(row),
        const Divider(height: 18),
        _total('Goods', group.merchandise),
        if (_percent > 0) ...[
          _total('Commission ${_trim(_percent)}%', -group.commission),
          _total('Net payable', group.netPayable, bold: true),
        ],
      ],
    ),
  );

  Widget _row(SupplyCheckRow row) {
    final measures = <String>[
      '${Money.formatQty(row.handlingQty)} ${row.handlingUom}',
      if (row.baseQty != null) '${Money.formatQty(row.baseQty!)} ${row.baseUom ?? ''}'.trim(),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${row.itemCode}  ${row.description}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
                Text(
                  '$measures × ${Money.format(row.unitPrice)} '
                  'per ${row.pricingBasis == 'kilos' ? (row.baseUom ?? 'measure') : row.handlingUom}'
                  '${row.lineCount > 1 ? ' · ${row.lineCount} lines' : ''}',
                  style: const TextStyle(color: AppColors.inkSoft, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            Money.format(row.merchandise),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _total(String label, double value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
              fontSize: bold ? 14 : 12.5,
            ),
          ),
        ),
        Text(
          Money.format(value),
          style: TextStyle(
            fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
            fontSize: bold ? 14 : 12.5,
          ),
        ),
      ],
    ),
  );

  Widget _totalCard(SupplyCheckSummary summary) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.ink,
      borderRadius: BorderRadius.circular(20),
      boxShadow: cardShadow,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ALL TOGETHER',
          style: TextStyle(
            color: Colors.white60,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: .8,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          Money.format(summary.netPayable),
          key: const ValueKey('supply-net-payable'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w900,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 10),
        _darkRow('Goods', summary.merchandise),
        if (_percent > 0) _darkRow('Commission ${_trim(_percent)}%', -summary.commission),
        _darkRow('Net payable', summary.netPayable),
      ],
    ),
  );

  Widget _darkRow(String label, double value) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ),
        Text(
          Money.format(value),
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );

  /// A statement a supplier can be sent: the goods and the money, nothing else.
  Future<void> _export() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SupplyStatementExportScreen(
          lines: widget.lines,
          commissionPercent: _percent,
          groupByDate: _groupByDate,
          fromDate: widget.fromDate,
          toDate: widget.toDate,
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController(
          text: widget.supplierCodes.isNotEmpty
              ? '${widget.supplierCodes.join(', ')} · ${widget.fromDate}'
              : 'Check ${widget.fromDate}',
        );
        return AlertDialog(
          title: const Text('Save this check'),
          content: TextField(
            key: const ValueKey('check-title'),
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Call it'),
            onSubmitted: (value) => Navigator.pop(context, value.trim()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              key: const ValueKey('confirm-save-check'),
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (name == null || name.isEmpty || !mounted) return;
    setState(() => _saving = true);
    await SupplyCheckRepository().save(
      SavedSupplyCheck(
        id: const Uuid().v4(),
        title: name,
        fromDate: widget.fromDate,
        toDate: widget.toDate,
        placeLabel: widget.placeLabel,
        locCode: widget.locCode,
        macCode: widget.macCode,
        supplierCodes: widget.supplierCodes,
        itemCodes: widget.itemCodes,
        commissionPercent: _percent,
        groupByDate: _groupByDate,
        lines: widget.lines,
        createdAt: DateTime.now(),
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    successHaptic();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved on this phone.')),
    );
    Navigator.pop(context, true);
  }

  static String _trim(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';
}

// ── Checks kept on this phone ─────────────────────────────────

class SavedChecksScreen extends StatefulWidget {
  const SavedChecksScreen({super.key});

  @override
  State<SavedChecksScreen> createState() => _SavedChecksScreenState();
}

class _SavedChecksScreenState extends State<SavedChecksScreen> {
  final _repository = SupplyCheckRepository();
  List<SavedSupplyCheck> _checks = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final checks = await _repository.list();
    if (!mounted) return;
    setState(() {
      _checks = checks;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Saved checks'),
          Text(
            'Kept on this phone only',
            style: TextStyle(color: AppColors.inkSoft, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _checks.isEmpty
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(30),
              child: Text(
                'Nothing saved yet. Pick some lines, open the summary, and save it.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkSoft, height: 1.4),
              ),
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
            itemCount: _checks.length,
            itemBuilder: (context, index) {
              final check = _checks[index];
              final summary = check.summary;
              return Card(
                key: ValueKey('saved-check-${check.id}'),
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  title: Text(
                    check.title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${check.rangeLabel} · ${check.lines.length} line${check.lines.length == 1 ? '' : 's'}'
                    '${check.supplierCodes.isEmpty ? '' : ' · ${check.supplierCodes.join(', ')}'}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        Money.format(summary.netPayable),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      if (check.commissionPercent > 0)
                        Text(
                          'after ${_SupplyCheckSummaryScreenState._trim(check.commissionPercent)}%',
                          style: const TextStyle(color: AppColors.inkSoft, fontSize: 10.5),
                        ),
                    ],
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SupplyCheckSummaryScreen(
                        lines: check.lines,
                        fromDate: check.fromDate,
                        toDate: check.toDate,
                        placeLabel: check.placeLabel,
                        supplierCodes: check.supplierCodes,
                        itemCodes: check.itemCodes,
                        readOnlyTitle: check.title,
                        initialCommission: check.commissionPercent,
                        initialGroupByDate: check.groupByDate,
                      ),
                    ),
                  ),
                  onLongPress: () async {
                    final remove = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('Delete ${check.title}?'),
                        content: const Text('The lines themselves are not touched.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Keep'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (remove == true) {
                      await _repository.delete(check.id);
                      await _load();
                    }
                  },
                ),
              );
            },
          ),
  );
}

/// A filter the person opens: it says so when it is holding something.
class _FilterButton extends StatelessWidget {
  const _FilterButton({
    super.key,
    required this.icon,
    required this.label,
    required this.chosen,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool chosen;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: chosen ? AppColors.brand.withValues(alpha: .1) : AppColors.background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap == null
            ? null
            : () {
                tapHaptic();
                onTap!();
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: !enabled
                    ? AppColors.inkFaint
                    : chosen
                    ? AppColors.brandDark
                    : AppColors.inkSoft,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: !enabled
                        ? AppColors.inkFaint
                        : chosen
                        ? AppColors.brandDark
                        : AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
