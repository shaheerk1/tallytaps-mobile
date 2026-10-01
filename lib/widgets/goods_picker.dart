import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/mobile_bill.dart';
import '../state/tally_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Goods named on a note: the shop's own item, and how much of it.
///
/// An item the POS keeps in two measures asks for both, because three bags and
/// sixty kilos are two different facts about the same delivery.
class GoodsSelection {
  const GoodsSelection({
    required this.name,
    this.productKey,
    this.handlingQty,
    this.handlingUom,
    this.baseQty,
    this.baseUom,
    this.cleared = false,
  });

  final String name;
  final String? productKey;
  final double? handlingQty;
  final String? handlingUom;
  final double? baseQty;
  final String? baseUom;

  /// The person took the goods back off the note.
  final bool cleared;

  String get summary {
    final parts = <String>[
      if (handlingQty != null && handlingQty! > 0)
        '${Money.formatQty(handlingQty!)} ${handlingUom ?? 'units'}',
      if (baseQty != null && baseQty! > 0) '${Money.formatQty(baseQty!)} ${baseUom ?? 'measured'}',
    ];
    return parts.isEmpty ? name : '$name · ${parts.join(' · ')}';
  }
}

/// Picks an item from the connected POS, then asks for its quantities.
Future<GoodsSelection?> showGoodsPicker(
  BuildContext context, {
  GoodsSelection? current,
}) => showModalBottomSheet<GoodsSelection>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _GoodsSheet(current: current),
);

class _GoodsSheet extends StatefulWidget {
  const _GoodsSheet({this.current});

  final GoodsSelection? current;

  @override
  State<_GoodsSheet> createState() => _GoodsSheetState();
}

class _GoodsSheetState extends State<_GoodsSheet> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _handling = TextEditingController();
  final TextEditingController _base = TextEditingController();

  List<CatalogItem> _items = const [];
  CatalogItem? _chosen;
  String? _freeName;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _handling.text = widget.current?.handlingQty == null
        ? ''
        : Money.formatQty(widget.current!.handlingQty!);
    _base.text = widget.current?.baseQty == null
        ? ''
        : Money.formatQty(widget.current!.baseQty!);
    _freeName = widget.current?.name;
    unawaitedLoad();
  }

  void unawaitedLoad() {
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _handling.dispose();
    _base.dispose();
    super.dispose();
  }

  /// The item list comes from the POS catalog this phone already downloads for
  /// quick billing, so a note names the same item the shop does.
  Future<void> _load() async {
    try {
      final store = context.read<TallyStore>();
      final items = await store.loadCatalogItems();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        final key = widget.current?.productKey;
        if (key != null) {
          for (final item in items) {
            if (item.sourceProductKey == key) _chosen = item;
          }
        }
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = exception.toString();
      });
    }
  }

  List<CatalogItem> get _matches {
    final term = _search.text.trim().toLowerCase();
    if (term.isEmpty) return _items.take(40).toList();
    return _items
        .where((item) =>
            item.name.toLowerCase().contains(term) ||
            (item.sku ?? '').toLowerCase().contains(term))
        .take(40)
        .toList();
  }

  bool get _isDual => _chosen?.dualUomEnabled ?? false;
  String get _handlingUom => _chosen?.handlingUom ?? 'units';
  String get _baseUom => _chosen?.baseUom ?? 'kg';

  void _save() {
    final name = _chosen?.name ?? _freeName ?? _search.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose an item, or type what it was.')),
      );
      return;
    }
    Navigator.of(context).pop(
      GoodsSelection(
        name: name,
        productKey: _chosen?.sourceProductKey,
        handlingQty: Money.parseInput(_handling.text),
        handlingUom: _handlingUom,
        baseQty: _isDual ? Money.parseInput(_base.text) : null,
        baseUom: _isDual ? _baseUom : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, controller) => Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'What goods?',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (widget.current != null)
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(
                          const GoodsSelection(name: '', cleared: true),
                        ),
                        child: const Text('Take off'),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search the shop\'s items',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: AppColors.surface,
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
              if (_chosen != null) _quantityFields(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
                    : _listBody(controller),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brand,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Put it on the note',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quantityFields() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _chosen!.name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _handling,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: _handlingUom,
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              if (_isDual) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _base,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: _baseUom,
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (_isDual)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'This item is kept in two measures, so both are worth writing.',
                style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
              ),
            ),
        ],
      ),
    );
  }

  Widget _listBody(ScrollController controller) {
    if (_error != null || _items.isEmpty) {
      return ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
        children: [
          Text(
            _error == null
                ? 'No shop items are on this phone yet. Download a catalog from quick billing, or just type what the goods were.'
                : 'The shop\'s items could not be read. You can still type what the goods were.',
            style: const TextStyle(color: AppColors.inkSoft, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (value) => _freeName = value.trim(),
            decoration: InputDecoration(
              labelText: 'Goods',
              hintText: 'Rice, empty crates, anything',
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      );
    }
    final matches = _matches;
    return ListView.separated(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      itemCount: matches.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.line),
      itemBuilder: (context, index) {
        final item = matches[index];
        final chosen = item.sourceProductKey == _chosen?.sourceProductKey;
        return ListTile(
          title: Text(
            item.name,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          subtitle: Text(
            [
              if (item.sku != null && item.sku!.isNotEmpty) item.sku!,
              item.dualUomEnabled
                  ? '${item.handlingUom} and ${item.baseUom ?? 'measured'}'
                  : item.handlingUom,
            ].join(' · '),
            style: const TextStyle(fontSize: 12),
          ),
          trailing: chosen
              ? const Icon(Icons.check_circle_rounded, color: AppColors.brand)
              : null,
          onTap: () {
            tapHaptic();
            setState(() {
              _chosen = item;
              _freeName = item.name;
            });
          },
        );
      },
    );
  }
}
