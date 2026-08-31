import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/tally_store.dart';
import '../theme/app_colors.dart';

/// Full-screen-height bottom sheet for picking a stock item fast.
/// Shows a big search field, a tap-friendly list and an "add new" row
/// when the typed text is not yet in the list.
class ItemPickerSheet extends StatefulWidget {
  const ItemPickerSheet({super.key});

  @override
  State<ItemPickerSheet> createState() => _ItemPickerSheetState();
}

class _ItemPickerSheetState extends State<ItemPickerSheet> {
  final _searchController = TextEditingController();
  List<String> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await context.read<TallyStore>().loadItems();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  String get _query => _searchController.text.trim().toLowerCase();

  List<String> get _filtered =>
      _items.where((i) => i.toLowerCase().contains(_query)).toList();

  bool get _exactMatch => _items.any((i) => i.toLowerCase() == _query);

  Future<void> _addNew() async {
    final name = _searchController.text.trim();
    if (name.isEmpty) return;
    final saved = await context.read<TallyStore>().addItem(name);
    if (!mounted) return;
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final stockColor = AppColors.stock;
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 12),
            _grabHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(
                children: [
                  const Text(
                    'Select item',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_items.length} saved',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 18, color: AppColors.ink),
                decoration: InputDecoration(
                  hintText: 'Search items…',
                  hintStyle: const TextStyle(
                    color: AppColors.inkSoft,
                    fontSize: 16,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: AppColors.inkSoft,
                  ),
                  filled: true,
                  fillColor: AppColors.background,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: stockColor, width: 2),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                      children: [
                        if (_query.isNotEmpty && !_exactMatch)
                          _itemTile(
                            key: const Key('item-add-new'),
                            icon: Icons.add_circle_outline,
                            text: _searchController.text.trim(),
                            subtitle: 'Add new item',
                            onTap: _addNew,
                          ),
                        for (final item in _filtered)
                          _itemTile(
                            icon: Icons.inventory_2_outlined,
                            text: item,
                            subtitle: 'Tap to select',
                            onTap: () => Navigator.of(context).pop(item),
                          ),
                        if (_filtered.isEmpty && _query.isEmpty)
                          _hint('Your saved stock items will appear here.'),
                        if (_filtered.isEmpty &&
                            _query.isNotEmpty &&
                            _exactMatch)
                          _hint('Already in the list above. Tap it to select.'),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grabHandle() {
    return Container(
      width: 44,
      height: 5,
      decoration: BoxDecoration(
        color: AppColors.inkSoft,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  Widget _itemTile({
    Key? key,
    required IconData icon,
    required String text,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.stockSoft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: AppColors.stock, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.inkSoft),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hint(String message) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.inkSoft,
        ),
      ),
    );
  }
}
