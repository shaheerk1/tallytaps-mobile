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
  List<PosCatalogNode> nodes = [];
  List<CatalogItem> items = [];
  final cart = <String, MobileBillLine>{};
  String? nodeId, error;
  bool loading = true;
  String search = '';
  @override
  void initState() {
    super.initState();
    _loadNodes();
  }

  Future<void> _loadNodes() async {
    setState(() => loading = true);
    try {
      nodes = await context.read<TallyStore>().loadPosNodes();
      if (nodes.isNotEmpty) {
        nodeId = nodes.first.id;
        await _loadCatalog();
      }
    } catch (e) {
      error = e.toString();
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
      cart.clear();
    });
    try {
      items = await context.read<TallyStore>().loadCatalog(id);
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<CatalogItem> get visible {
    final q = search.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items
        .where(
          (i) => [
            i.name,
            i.sku,
            i.barcode,
            i.category,
          ].whereType<String>().any((v) => v.toLowerCase().contains(q)),
        )
        .toList();
  }

  double get total => cart.values.fold(0, (sum, line) => sum + line.lineTotal);
  Future<void> _add(CatalogItem item) async {
    tapHaptic();
    final existing = cart[item.sourceProductKey];
    if (existing != null) {
      setState(() => existing.quantity += item.quantityStep);
      return;
    }
    double? kilos;
    if (item.pricingBasis == 'kilos') {
      final value = await _numberDialog('Enter weight', item.unit ?? 'Kg', 1);
      if (value == null) return;
      kilos = value;
    }
    setState(
      () => cart[item.sourceProductKey] = MobileBillLine(
        item: item,
        quantity: item.pricingBasis == 'kilos' ? 1 : item.quantityStep,
        kilos: kilos,
      ),
    );
  }

  Future<double?> _numberDialog(
    String title,
    String suffix,
    double initial,
  ) async {
    final c = TextEditingController(text: '$initial');
    return showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: suffix),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(c.text);
              if (v != null && v > 0) Navigator.pop(context, v);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<TallyStore>().isConnected;
    return Scaffold(
      appBar: AppBar(title: const Text('Quick bill')),
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
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Column(
          children: [
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
            ),
            const SizedBox(height: 10),
            TextField(
              onChanged: (value) => setState(() => search = value),
              decoration: const InputDecoration(
                hintText: 'Search item, code or barcode',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ],
        ),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.all(12),
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
                'Try another name or code.',
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 110),
                itemCount: visible.length,
                separatorBuilder: (_, _) => const SizedBox(height: 7),
                itemBuilder: (context, index) {
                  final item = visible[index];
                  final count = cart[item.sourceProductKey]?.quantity;
                  return Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(17),
                    child: ListTile(
                      onTap: () => _add(item),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                      ),
                      leading: CircleAvatar(
                        backgroundColor: AppColors.brand.withValues(alpha: .1),
                        child: const Icon(
                          Icons.add_rounded,
                          color: AppColors.brand,
                        ),
                      ),
                      title: Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        [
                          item.category,
                          item.unit,
                          item.pricingBasis == 'kilos' ? 'by weight' : null,
                        ].whereType<String>().join(' · '),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            Money.format(item.unitPrice),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: AppColors.ink,
                            ),
                          ),
                          if (count != null)
                            Text(
                              '${count.toStringAsFixed(count % 1 == 0 ? 0 : 2)} added',
                              style: const TextStyle(
                                color: AppColors.positive,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      if (cart.isNotEmpty) _cartBar(),
    ],
  );
  Widget _cartBar() => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: const BoxDecoration(
      color: Colors.white,
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
        onPressed: _review,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brand,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
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
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'Review bill',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
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
    final selected = nodes.firstWhere((n) => n.id == nodeId);
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
  final customer = TextEditingController(),
      mobile = TextEditingController(),
      note = TextEditingController();
  bool all = false, submitting = false;
  String payment = 'cash';
  String? destination, error;
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

  double get total => widget.lines.fold(0, (s, l) => s + l.lineTotal);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Review bill')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        for (final line in widget.lines) _line(line),
        const SizedBox(height: 12),
        TextField(
          controller: customer,
          decoration: const InputDecoration(
            labelText: 'Customer name (optional)',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: mobile,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Mobile number (optional)',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: note,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Note (optional)',
            prefixIcon: Icon(Icons.notes_rounded),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'SEND TO',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: AppColors.inkFaint,
            fontSize: 12,
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'All connected POS systems',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: const Text('Turn off to send only to one POS inbox'),
          value: all,
          onChanged: (v) => setState(() => all = v),
        ),
        if (!all)
          DropdownButtonFormField<String>(
            initialValue: destination,
            decoration: const InputDecoration(labelText: 'POS destination'),
            items: widget.nodes
                .map(
                  (n) => DropdownMenuItem(value: n.id, child: Text(n.nickname)),
                )
                .toList(),
            onChanged: (v) => setState(() => destination = v),
          ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: payment,
          decoration: const InputDecoration(
            labelText: 'Payment',
            prefixIcon: Icon(Icons.payments_outlined),
          ),
          items: const [
            DropdownMenuItem(value: 'cash', child: Text('Paid by cash')),
            DropdownMenuItem(value: 'card', child: Text('Paid by card')),
            DropdownMenuItem(
              value: 'unpaid',
              child: Text('Unpaid / collect later'),
            ),
          ],
          onChanged: (v) => setState(() => payment = v ?? 'cash'),
        ),
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
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 16)],
      ),
      child: SafeArea(
        top: false,
        child: FilledButton(
          onPressed: submitting ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brand,
            padding: const EdgeInsets.symmetric(vertical: 17),
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
  Widget _line(MobileBillLine line) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.item.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                GestureDetector(
                  onTap: line.item.priceOverrideAllowed
                      ? () => _editPrice(line)
                      : null,
                  child: Text(
                    '${line.item.pricingBasis == 'kilos' ? '${line.kilos} ${line.item.unit ?? 'kg'}' : '${line.quantity} ${line.item.unit ?? ''}'} × ${Money.format(line.unitPrice)}${line.item.priceOverrideAllowed ? ' · tap price to change' : ''}',
                    style: TextStyle(
                      color: line.item.priceOverrideAllowed
                          ? AppColors.brand
                          : AppColors.inkSoft,
                      fontWeight: line.item.priceOverrideAllowed
                          ? FontWeight.w700
                          : FontWeight.normal,
                    ),
                  ),
                ),
                if (line.bagChargeTotal + line.wageChargeTotal > 0)
                  Text(
                    'Charges ${Money.format(line.bagChargeTotal + line.wageChargeTotal)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.inkFaint,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(() {
              if (line.item.pricingBasis == 'kilos') {
                line.kilos = ((line.kilos ?? 1) - line.item.quantityStep).clamp(
                  line.item.quantityStep,
                  999999,
                );
              } else {
                line.quantity = (line.quantity - line.item.quantityStep).clamp(
                  line.item.quantityStep,
                  999999,
                );
              }
            }),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text(
            Money.format(line.lineTotal),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          IconButton(
            onPressed: () => setState(() {
              if (line.item.pricingBasis == 'kilos') {
                line.kilos = (line.kilos ?? 0) + line.item.quantityStep;
              } else {
                line.quantity += line.item.quantityStep;
              }
            }),
            icon: const Icon(Icons.add_circle, color: AppColors.brand),
          ),
        ],
      ),
    ),
  );
  Future<void> _editPrice(MobileBillLine line) async {
    final controller = TextEditingController(text: '${line.unitPrice}');
    final price = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change selling price'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            helperText:
                'Allowed ${line.item.minimumSellPrice ?? 0} – ${line.item.maximumSellPrice ?? 'no maximum'}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text);
              final minimum = line.item.minimumSellPrice ?? 0;
              final maximum = line.item.maximumSellPrice;
              if (value != null &&
                  value >= minimum &&
                  (maximum == null || value <= maximum)) {
                Navigator.pop(context, value);
              }
            },
            child: const Text('Use price'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (price != null && mounted) {
      setState(() => line.unitPriceOverride = price);
    }
  }

  Future<void> _submit() async {
    if (!all && destination == null) return;
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
