import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/mobile_bill.dart';
import '../state/tally_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class MobileBillingScreen extends StatefulWidget {
  const MobileBillingScreen({super.key});

  @override
  State<MobileBillingScreen> createState() => _MobileBillingScreenState();
}

class _MobileBillingScreenState extends State<MobileBillingScreen> {
  final _searchController = TextEditingController();
  final cart = <String, MobileBillLine>{};
  List<PosCatalogNode> nodes = [];
  List<CatalogItem> items = [];
  String? nodeId;
  String? error;
  String? selectedCategory;
  bool loading = true;
  String search = '';

  @override
  void initState() {
    super.initState();
    _loadNodes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNodes() async {
    setState(() => loading = true);
    try {
      final loaded = await context.read<TallyStore>().loadPosNodes();
      if (!mounted) return;
      nodes = loaded;
      if (nodes.isNotEmpty) {
        nodeId = nodes.first.id;
        await _loadCatalog();
      }
    } catch (exception) {
      error = exception.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadCatalog() async {
    final id = nodeId;
    if (id == null) return;
    setState(() {
      loading = true;
      error = null;
      selectedCategory = null;
      cart.clear();
    });
    try {
      final loaded = await context.read<TallyStore>().loadCatalog(id);
      if (!mounted || id != nodeId) return;
      items = loaded;
    } catch (exception) {
      error = exception.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<String> get categories {
    final values = items
        .map((item) => item.category?.trim())
        .whereType<String>()
        .where((category) => category.isNotEmpty)
        .toSet()
        .toList();
    values.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  List<CatalogItem> get visible {
    final query = search.trim().toLowerCase();
    return items.where((item) {
      if (selectedCategory != null && item.category != selectedCategory) {
        return false;
      }
      if (query.isEmpty) return true;
      return [
        item.name,
        item.sku,
        item.barcode,
        item.category,
      ].whereType<String>().any((value) => value.toLowerCase().contains(query));
    }).toList();
  }

  double get total => cart.values.fold(0, (sum, line) => sum + line.lineTotal);

  double get merchandiseTotal =>
      cart.values.fold(0, (sum, line) => sum + line.merchandiseTotal);

  Future<void> _add(CatalogItem item) async {
    tapHaptic();
    final existing = cart[item.sourceProductKey];
    if (item.requiresMeasuredQuantity) {
      await _editItem(
        item,
        existing ??
            MobileBillLine(
              item: item,
              quantity: item.allowZeroQuantity ? 0 : item.quantityStep,
            ),
        isNew: existing == null,
      );
      return;
    }
    setState(() {
      if (existing == null) {
        cart[item.sourceProductKey] = MobileBillLine(
          item: item,
          quantity: item.quantityStep,
        );
      } else {
        existing.quantity += item.quantityStep;
      }
    });
  }

  Future<void> _editItem(
    CatalogItem item,
    MobileBillLine line, {
    bool isNew = false,
  }) async {
    final result = await showModalBottomSheet<_LineEditResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LineEditorSheet(item: item, line: line),
    );
    if (!mounted || result == null) return;
    setState(() {
      line.quantity = result.quantity;
      line.kilos = result.measuredQuantity;
      line.unitPriceOverride = result.unitPrice;
      line.priceOverrideReason = result.priceOverrideReason;
      cart[item.sourceProductKey] = line;
    });
    if (isNew) successHaptic();
  }

  void _decrease(MobileBillLine line) {
    tapHaptic();
    if (line.item.requiresMeasuredQuantity) {
      _editItem(line.item, line);
      return;
    }
    setState(() {
      final next = line.quantity - line.item.quantityStep;
      if (next <= 0) {
        cart.remove(line.item.sourceProductKey);
      } else {
        line.quantity = next;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<TallyStore>().isConnected;
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Create a bill'),
            Text(
              'Fast field sale',
              style: TextStyle(
                color: AppColors.inkSoft,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      body: loading && nodes.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : nodes.isEmpty
          ? _empty(
              connected ? Icons.inventory_2_outlined : Icons.cloud_off_rounded,
              connected ? 'No POS item list yet' : 'Connect to a host first',
              connected
                  ? 'Enable POS Cloud Backup on a desktop POS and run its first sync.'
                  : 'After one catalog download, quick billing also works while this phone is offline.',
            )
          : _body(),
    );
  }

  Widget _body() => Column(
    children: [
      _catalogHeader(),
      if (error != null)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.negative.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            error!,
            style: const TextStyle(
              color: AppColors.negative,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      Expanded(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : visible.isEmpty
            ? _empty(
                Icons.search_off_rounded,
                'No matching item',
                'Try another name, code, or category.',
              )
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  12,
                  2,
                  12,
                  cart.isEmpty ? 24 : 124,
                ),
                itemCount: visible.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, index) => _productCard(visible[index]),
              ),
      ),
      if (cart.isNotEmpty) _cartBar(),
    ],
  );

  Widget _catalogHeader() {
    final selectedNode = nodes.firstWhere((node) => node.id == nodeId);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: cardShadow,
      ),
      child: Column(
        children: [
          if (nodes.length > 1)
            DropdownButtonFormField<String>(
              initialValue: nodeId,
              decoration: const InputDecoration(
                labelText: 'Item list from',
                prefixIcon: Icon(Icons.storefront_rounded),
              ),
              items: nodes
                  .map(
                    (node) => DropdownMenuItem(
                      value: node.id,
                      child: Text(
                        '${node.nickname} · ${node.itemCount} items',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                nodeId = value;
                _loadCatalog();
              },
            )
          else
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    color: AppColors.brand,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedNode.nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${selectedNode.itemCount} synced items · available offline',
                        style: const TextStyle(
                          color: AppColors.inkSoft,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 11),
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => search = value),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search item, code or barcode',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: search.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() => search = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          if (categories.isNotEmpty) ...[
            const SizedBox(height: 9),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _categoryChip(null, 'All'),
                  for (final category in categories)
                    _categoryChip(category, category),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _categoryChip(String? value, String label) => Padding(
    padding: const EdgeInsets.only(right: 7),
    child: FilterChip(
      label: Text(label),
      selected: selectedCategory == value,
      onSelected: (_) => setState(() => selectedCategory = value),
      showCheckmark: false,
      side: BorderSide.none,
      selectedColor: AppColors.brand.withValues(alpha: .14),
      backgroundColor: AppColors.background,
      labelStyle: TextStyle(
        color: selectedCategory == value ? AppColors.brandDark : AppColors.ink,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _productCard(CatalogItem item) {
    final line = cart[item.sourceProductKey];
    final selected = line != null;
    return Material(
      key: ValueKey('billing-item-${item.sourceProductKey}'),
      color: Colors.white,
      borderRadius: BorderRadius.circular(19),
      elevation: selected ? 1 : 0,
      child: InkWell(
        onTap: () => _add(item),
        borderRadius: BorderRadius.circular(19),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 12, 10, 11),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.positive.withValues(alpha: .12)
                          : AppColors.stockSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      selected ? Icons.check_rounded : Icons.add_rounded,
                      color: selected ? AppColors.positive : AppColors.stock,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _itemDescription(item),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.inkSoft,
                            fontSize: 12,
                            height: 1.25,
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
                        Money.format(item.unitPrice),
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'per ${item.priceUom}',
                        style: const TextStyle(
                          color: AppColors.inkFaint,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (selected) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 9),
                  child: Divider(height: 1),
                ),
                Row(
                  children: [
                    IconButton.filledTonal(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _decrease(line),
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => _editItem(item, line),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            children: [
                              Text(
                                _lineMeasures(line),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.brandDark,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                '${Money.format(line.lineTotal)} · tap to edit',
                                style: const TextStyle(
                                  color: AppColors.inkSoft,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton.filled(
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.brand,
                      ),
                      onPressed: item.requiresMeasuredQuantity
                          ? () => _editItem(item, line)
                          : () => _add(item),
                      icon: Icon(
                        item.requiresMeasuredQuantity
                            ? Icons.edit_rounded
                            : Icons.add_rounded,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _itemDescription(CatalogItem item) {
    final parts = <String>[
      if (item.sku?.trim().isNotEmpty == true) item.sku!.trim(),
      if (item.dualUomEnabled) '${item.handlingUom} + ${item.baseUom}',
      if (!item.dualUomEnabled) item.handlingUom,
      if (item.bagCharge > 0)
        '${Money.format(item.bagCharge)} packaging/${item.handlingUom}',
      if (item.wageCharge > 0)
        '${Money.format(item.wageCharge)} wage/${item.wageBasis == 'kilos' ? item.baseUom : item.handlingUom}',
    ];
    return parts.join(' · ');
  }

  String _lineMeasures(MobileBillLine line) {
    final count = '${Money.formatQty(line.quantity)} ${line.item.handlingUom}';
    if (!line.item.requiresMeasuredQuantity) return count;
    return '$count · ${Money.formatQty(line.kilos ?? 0)} ${line.item.baseUom}';
  }

  Widget _cartBar() => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      boxShadow: [
        BoxShadow(
          color: Color(0x22000000),
          blurRadius: 18,
          offset: Offset(0, -5),
        ),
      ],
    ),
    child: SafeArea(
      top: false,
      child: FilledButton(
        key: const ValueKey('billing-review'),
        onPressed: _review,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ink,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Row(
          children: [
            Badge(
              label: Text('${cart.length}'),
              child: const Icon(Icons.receipt_long_rounded),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Review bill',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    merchandiseTotal == total
                        ? '${cart.length} item${cart.length == 1 ? '' : 's'}'
                        : 'Includes ${Money.format(total - merchandiseTotal)} charges',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
            Text(
              Money.format(total),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _review() async {
    if (cart.values.any((line) => !line.isValid)) {
      setState(() => error = 'Complete the quantities required by each item.');
      return;
    }
    final selected = nodes.firstWhere((node) => node.id == nodeId);
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _BillReviewScreen(
          lines: cart.values.toList(),
          nodes: nodes,
          catalog: selected,
        ),
      ),
    );
    if (saved == true && mounted) Navigator.pop(context, true);
  }

  Widget _empty(IconData icon, String title, String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 58, color: AppColors.inkFaint),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 7),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.inkSoft, height: 1.4),
          ),
        ],
      ),
    ),
  );
}

class _BillReviewScreen extends StatefulWidget {
  const _BillReviewScreen({
    required this.lines,
    required this.nodes,
    required this.catalog,
  });

  final List<MobileBillLine> lines;
  final List<PosCatalogNode> nodes;
  final PosCatalogNode catalog;

  @override
  State<_BillReviewScreen> createState() => _BillReviewScreenState();
}

class _BillReviewScreenState extends State<_BillReviewScreen> {
  final customer = TextEditingController();
  final mobile = TextEditingController();
  final note = TextEditingController();
  bool all = false;
  bool submitting = false;
  String payment = 'cash';
  String? destination;
  String? error;

  @override
  void initState() {
    super.initState();
    destination = widget.catalog.id;
  }

  @override
  void dispose() {
    customer.dispose();
    mobile.dispose();
    note.dispose();
    super.dispose();
  }

  double get merchandise =>
      widget.lines.fold(0, (sum, line) => sum + line.merchandiseTotal);
  double get packaging =>
      widget.lines.fold(0, (sum, line) => sum + line.bagChargeTotal);
  double get wages =>
      widget.lines.fold(0, (sum, line) => sum + line.wageChargeTotal);
  double get total => widget.lines.fold(0, (sum, line) => sum + line.lineTotal);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Finish bill'),
          Text(
            'Check once, then save',
            style: TextStyle(
              color: AppColors.inkSoft,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 128),
      children: [
        _totalCard(),
        const SizedBox(height: 12),
        _sectionTitle('ITEMS', '${widget.lines.length}'),
        const SizedBox(height: 7),
        for (final line in widget.lines) _line(line),
        const SizedBox(height: 8),
        _paymentCard(),
        const SizedBox(height: 10),
        _customerCard(),
        const SizedBox(height: 10),
        _destinationCard(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              error!,
              style: const TextStyle(
                color: AppColors.negative,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    ),
    bottomNavigationBar: Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 16)],
      ),
      child: SafeArea(
        top: false,
        child: FilledButton(
          key: const ValueKey('bill-save'),
          onPressed: submitting ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brand,
            padding: const EdgeInsets.symmetric(vertical: 17),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: submitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  'Save bill · ${Money.format(total)}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
        ),
      ),
    ),
  );

  Widget _totalCard() => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: AppColors.ink,
      borderRadius: BorderRadius.circular(24),
      boxShadow: cardShadow,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'BILL TOTAL',
          style: TextStyle(
            color: Colors.white60,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: .8,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          Money.format(total),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 31,
            fontWeight: FontWeight.w900,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 11),
        _totalRow('Items', merchandise),
        if (packaging > 0) _totalRow('Packaging charges', packaging),
        if (wages > 0) _totalRow('Wage charges', wages),
      ],
    ),
  );

  Widget _totalRow(String label, double value) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        Text(
          Money.format(value),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _sectionTitle(String title, String count) => Row(
    children: [
      Text(
        title,
        style: const TextStyle(
          color: AppColors.inkFaint,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: .7,
        ),
      ),
      const SizedBox(width: 7),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.brand.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          count,
          style: const TextStyle(
            color: AppColors.brand,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ],
  );

  Widget _line(MobileBillLine line) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    child: InkWell(
      key: ValueKey('review-line-${line.item.sourceProductKey}'),
      onTap: () => _editLine(line),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.item.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _reviewMeasure(line),
                    style: const TextStyle(
                      color: AppColors.inkSoft,
                      fontSize: 12,
                    ),
                  ),
                  if (line.bagChargeTotal + line.wageChargeTotal > 0)
                    Text(
                      _chargeSummary(line),
                      style: const TextStyle(
                        color: AppColors.stock,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
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
                  Money.format(line.lineTotal),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                const Row(
                  children: [
                    Text(
                      'Edit',
                      style: TextStyle(
                        color: AppColors.brand,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: AppColors.brand),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  String _reviewMeasure(MobileBillLine line) {
    final measures = <String>[
      '${Money.formatQty(line.quantity)} ${line.item.handlingUom}',
      if (line.item.requiresMeasuredQuantity)
        '${Money.formatQty(line.kilos ?? 0)} ${line.item.baseUom}',
    ];
    return '${measures.join(' · ')} × ${Money.format(line.unitPrice)} per ${line.item.priceUom}';
  }

  String _chargeSummary(MobileBillLine line) {
    final charges = <String>[
      if (line.bagChargeTotal > 0)
        'Packaging ${Money.format(line.bagChargeTotal)}',
      if (line.wageChargeTotal > 0)
        'Wage ${Money.format(line.wageChargeTotal)}',
    ];
    return charges.join(' · ');
  }

  Future<void> _editLine(MobileBillLine line) async {
    final result = await showModalBottomSheet<_LineEditResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LineEditorSheet(item: line.item, line: line),
    );
    if (!mounted || result == null) return;
    setState(() {
      line.quantity = result.quantity;
      line.kilos = result.measuredQuantity;
      line.unitPriceOverride = result.unitPrice;
      line.priceOverrideReason = result.priceOverrideReason;
    });
  }

  Widget _paymentCard() => _whiteCard(
    title: 'How was it paid?',
    icon: Icons.payments_outlined,
    child: SegmentedButton<String>(
      segments: const [
        ButtonSegment(
          value: 'cash',
          label: Text('Cash'),
          icon: Icon(Icons.payments_rounded),
        ),
        ButtonSegment(
          value: 'card',
          label: Text('Card'),
          icon: Icon(Icons.credit_card_rounded),
        ),
        ButtonSegment(
          value: 'unpaid',
          label: Text('Later'),
          icon: Icon(Icons.schedule_rounded),
        ),
      ],
      selected: {payment},
      showSelectedIcon: false,
      onSelectionChanged: (values) => setState(() => payment = values.first),
    ),
  );

  Widget _customerCard() => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(19),
    ),
    child: ExpansionTile(
      shape: const Border(),
      collapsedShape: const Border(),
      leading: const Icon(Icons.person_outline_rounded, color: AppColors.brand),
      title: const Text(
        'Customer or note',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: const Text('Optional'),
      childrenPadding: const EdgeInsets.fromLTRB(13, 0, 13, 14),
      children: [
        TextField(
          controller: customer,
          decoration: const InputDecoration(labelText: 'Customer name'),
        ),
        const SizedBox(height: 9),
        TextField(
          controller: mobile,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Mobile number'),
        ),
        const SizedBox(height: 9),
        TextField(
          controller: note,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Bill note'),
        ),
      ],
    ),
  );

  Widget _destinationCard() => _whiteCard(
    title: 'Send to POS',
    icon: Icons.storefront_rounded,
    child: Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'All connected POS systems',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            all
                ? 'Every connected POS can view this bill'
                : 'Only the selected POS receives this bill',
          ),
          value: all,
          onChanged: (value) => setState(() => all = value),
        ),
        if (!all)
          DropdownButtonFormField<String>(
            initialValue: destination,
            decoration: const InputDecoration(labelText: 'POS destination'),
            items: widget.nodes
                .map(
                  (node) => DropdownMenuItem(
                    value: node.id,
                    child: Text(node.nickname),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => destination = value),
          ),
      ],
    ),
  );

  Widget _whiteCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(19),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.brand, size: 21),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );

  Future<void> _submit() async {
    if (!all && destination == null) {
      setState(() => error = 'Choose a POS destination.');
      return;
    }
    if (widget.lines.any((line) => !line.isValid)) {
      setState(() => error = 'Complete the required item quantities.');
      return;
    }
    setState(() {
      submitting = true;
      error = null;
    });
    final bill = MobileBill(
      clientBillId: const Uuid().v4(),
      catalogPosNodeId: widget.catalog.id,
      deliveryScope: all ? 'all' : 'selected',
      targetPosNodeIds: all ? [] : [destination!],
      lines: widget.lines,
      paymentMethod: payment,
      customerName: customer.text.trim().isEmpty ? null : customer.text.trim(),
      customerMobile: mobile.text.trim().isEmpty ? null : mobile.text.trim(),
      note: note.text.trim().isEmpty ? null : note.text.trim(),
      createdAt: DateTime.now(),
    );
    final sent = await context.read<TallyStore>().submitMobileBill(bill);
    if (!mounted) return;
    setState(() => submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sent
              ? 'Bill sent to the POS inbox.'
              : 'Bill saved safely. It will retry when connected.',
        ),
      ),
    );
    Navigator.pop(context, true);
  }
}

class _LineEditorSheet extends StatefulWidget {
  const _LineEditorSheet({required this.item, required this.line});

  final CatalogItem item;
  final MobileBillLine line;

  @override
  State<_LineEditorSheet> createState() => _LineEditorSheetState();
}

class _LineEditorSheetState extends State<_LineEditorSheet> {
  late final TextEditingController quantity;
  late final TextEditingController measured;
  late final TextEditingController price;
  late final TextEditingController reason;
  String? validationMessage;

  @override
  void initState() {
    super.initState();
    quantity = TextEditingController(text: _editable(widget.line.quantity));
    measured = TextEditingController(
      text: widget.line.kilos == null ? '' : _editable(widget.line.kilos!),
    );
    price = TextEditingController(text: _editable(widget.line.unitPrice));
    reason = TextEditingController(text: widget.line.priceOverrideReason ?? '');
  }

  @override
  void dispose() {
    quantity.dispose();
    measured.dispose();
    price.dispose();
    reason.dispose();
    super.dispose();
  }

  double? get quantityValue => double.tryParse(quantity.text.trim());
  double? get measuredValue => double.tryParse(measured.text.trim());
  double? get priceValue => double.tryParse(price.text.trim());
  bool get hasOverride =>
      priceValue != null && (priceValue! - widget.item.unitPrice).abs() >= .005;

  MobileBillLine? get preview {
    final count = quantityValue;
    final rate = priceValue;
    if (count == null || rate == null) return null;
    return MobileBillLine(
      item: widget.item,
      quantity: count,
      kilos: measuredValue,
      unitPriceOverride: rate,
      priceOverrideReason: reason.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final current = preview;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              widget.item.name,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 3),
            const Text(
              'Enter the actual sale quantities',
              style: TextStyle(color: AppColors.inkSoft),
            ),
            const SizedBox(height: 15),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _numberField(
                    key: const ValueKey('line-handling-quantity'),
                    controller: quantity,
                    label: 'Unit Count',
                    suffix: widget.item.handlingUom,
                    autofocus: !widget.item.requiresMeasuredQuantity,
                  ),
                ),
                if (widget.item.requiresMeasuredQuantity) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: _numberField(
                      key: const ValueKey('line-measured-quantity'),
                      controller: measured,
                      label: 'Measured Qty',
                      suffix: widget.item.baseUom ?? 'measured',
                      autofocus: true,
                    ),
                  ),
                ],
              ],
            ),
            if (widget.item.allowZeroQuantity)
              const Padding(
                padding: EdgeInsets.only(top: 5),
                child: Text(
                  'Unit Count may be 0 for this item.',
                  style: TextStyle(color: AppColors.inkSoft, fontSize: 11),
                ),
              ),
            const SizedBox(height: 11),
            if (widget.item.priceOverrideAllowed)
              _numberField(
                key: const ValueKey('line-selling-price'),
                controller: price,
                label: 'Selling price per ${widget.item.priceUom}',
                prefix: Money.symbol,
                helper: _priceHelper(widget.item),
              )
            else
              _policyRow(
                Icons.sell_outlined,
                'Price',
                '${Money.format(widget.item.unitPrice)} per ${widget.item.priceUom}',
              ),
            if (hasOverride && widget.item.priceOverrideReasonRequired) ...[
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('line-price-reason'),
                controller: reason,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Reason for price change',
                  hintText: 'Required by this item',
                  prefixIcon: Icon(Icons.edit_note_rounded),
                ),
              ),
            ],
            if (widget.item.bagCharge > 0 || widget.item.wageCharge > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.stockSoft,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  children: [
                    if (widget.item.bagCharge > 0)
                      _chargeRow(
                        'Packaging',
                        '${Money.format(widget.item.bagCharge)} × Unit Count',
                        current?.bagChargeTotal ?? 0,
                      ),
                    if (widget.item.wageCharge > 0)
                      _chargeRow(
                        'Wage',
                        '${Money.format(widget.item.wageCharge)} × ${widget.item.wageBasis == 'kilos' ? 'Measured Qty' : 'Unit Count'}',
                        current?.wageChargeTotal ?? 0,
                      ),
                  ],
                ),
              ),
            ],
            if (validationMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  validationMessage!,
                  style: const TextStyle(
                    color: AppColors.negative,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(height: 14),
            FilledButton(
              key: const ValueKey('line-editor-save'),
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              child: Text(
                'Use item · ${Money.format(current?.lineTotal ?? 0)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberField({
    required Key key,
    required TextEditingController controller,
    required String label,
    String? suffix,
    String? prefix,
    String? helper,
    bool autofocus = false,
  }) => TextField(
    key: key,
    controller: controller,
    autofocus: autofocus,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onChanged: (_) => setState(() {
      validationMessage = null;
    }),
    decoration: InputDecoration(
      labelText: label,
      suffixText: suffix,
      prefixText: prefix == null ? null : '$prefix ',
      helperText: helper,
      helperMaxLines: 2,
    ),
  );

  Widget _policyRow(IconData icon, String label, String value) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
    ),
    child: Row(
      children: [
        Icon(icon, color: AppColors.brand),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: AppColors.inkSoft, fontSize: 11),
              ),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _chargeRow(String label, String rule, double total) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                rule,
                style: const TextStyle(color: AppColors.inkSoft, fontSize: 11),
              ),
            ],
          ),
        ),
        Text(
          Money.format(total),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );

  String _priceHelper(CatalogItem item) {
    final minimum = item.minimumSellPrice;
    final maximum = item.maximumSellPrice;
    if (minimum == null && maximum == null) {
      return 'This item allows a price change.';
    }
    if (maximum == null) return 'Minimum ${Money.format(minimum ?? 0)}';
    return '${Money.format(minimum ?? 0)} to ${Money.format(maximum)}';
  }

  void _save() {
    final count = quantityValue;
    final measuredAmount = measuredValue;
    final rate = priceValue;
    if (count == null || count < 0) {
      setState(() => validationMessage = 'Enter a valid Unit Count.');
      return;
    }
    if (!widget.item.allowZeroQuantity && count <= 0) {
      setState(() => validationMessage = 'Unit Count must be more than 0.');
      return;
    }
    if (widget.item.requiresMeasuredQuantity &&
        (measuredAmount == null || measuredAmount <= 0)) {
      setState(() => validationMessage = 'Enter the actual Measured Qty.');
      return;
    }
    if (rate == null || rate < 0) {
      setState(() => validationMessage = 'Enter a valid selling price.');
      return;
    }
    if (widget.item.minimumSellPrice != null &&
        rate < widget.item.minimumSellPrice!) {
      setState(
        () => validationMessage =
            'The selling price is below the allowed minimum.',
      );
      return;
    }
    if (widget.item.maximumSellPrice != null &&
        rate > widget.item.maximumSellPrice!) {
      setState(
        () => validationMessage =
            'The selling price is above the allowed maximum.',
      );
      return;
    }
    if (hasOverride &&
        widget.item.priceOverrideReasonRequired &&
        reason.text.trim().isEmpty) {
      setState(
        () => validationMessage = 'Enter a reason for changing the price.',
      );
      return;
    }
    Navigator.pop(
      context,
      _LineEditResult(
        quantity: count,
        measuredQuantity: widget.item.requiresMeasuredQuantity
            ? measuredAmount
            : null,
        unitPrice: hasOverride ? rate : null,
        priceOverrideReason: hasOverride ? reason.text.trim() : null,
      ),
    );
  }

  static String _editable(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';
}

class _LineEditResult {
  const _LineEditResult({
    required this.quantity,
    required this.measuredQuantity,
    required this.unitPrice,
    required this.priceOverrideReason,
  });

  final double quantity;
  final double? measuredQuantity;
  final double? unitPrice;
  final String? priceOverrideReason;
}
