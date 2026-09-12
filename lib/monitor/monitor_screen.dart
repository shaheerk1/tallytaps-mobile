import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/tally_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'monitor_bills.dart';
import 'monitor_controller.dart';
import 'monitor_operations.dart';
import 'monitor_overview.dart';

/// The Business Monitor shell.
///
/// Owns the period and terminal filters that every tab reads, and closes the
/// whole section the moment the host withdraws this device's access.
class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  final MonitorScope _scope = MonitorScope();
  late final MonitorRepository _repository;
  int _tab = 0;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _repository = MonitorRepository(store: context.read<TallyStore>());
    _loadFleet();
  }

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  Future<void> _loadFleet() async {
    try {
      final fleet = await _repository.fleet();
      if (mounted) _scope.setFleet(fleet);
    } catch (_) {
      // The tabs surface their own errors; an empty fleet only removes the
      // per-POS filter, which is optional.
    }
  }

  /// The store flips this off as soon as any monitor call is refused.
  void _closeIfRevoked(bool hasAccess) {
    if (hasAccess || _closing || !mounted) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Business monitor access was withdrawn by the host.'),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasAccess = context.select<TallyStore, bool>((store) => store.monitorAccess);
    _closeIfRevoked(hasAccess);

    return ChangeNotifierProvider<MonitorScope>.value(
      value: _scope,
      child: Provider<MonitorRepository>.value(
        value: _repository,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text(
              'Business Monitor',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(56),
              child: _FilterBar(),
            ),
          ),
          body: IndexedStack(
            index: _tab,
            children: const [
              MonitorOverviewTab(),
              MonitorSalesTab(),
              MonitorBillsTab(),
              MonitorCashTab(),
              MonitorStockTab(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (index) {
              tapHaptic();
              setState(() => _tab = index);
            },
            height: 66,
            backgroundColor: AppColors.surface,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights_rounded),
                label: 'Summary',
              ),
              NavigationDestination(
                icon: Icon(Icons.trending_up_outlined),
                selectedIcon: Icon(Icons.trending_up_rounded),
                label: 'Sales',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long_rounded),
                label: 'Bills',
              ),
              NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet_rounded),
                label: 'Cash',
              ),
              NavigationDestination(
                icon: Icon(Icons.inventory_2_outlined),
                selectedIcon: Icon(Icons.inventory_2_rounded),
                label: 'Stock',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Period and POS filters. Every tab reads the same scope, so this sits once at
/// the top rather than being repeated per screen.
class _FilterBar extends StatelessWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context) {
    final scope = context.watch<MonitorScope>();
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        children: [
          for (final preset in RangePreset.values)
            if (preset != RangePreset.custom)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(preset.label),
                  selected: scope.preset == preset,
                  onSelected: (_) {
                    tapHaptic();
                    scope.applyPreset(preset);
                  },
                ),
              ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              avatar: const Icon(Icons.event_rounded, size: 17),
              label: Text(
                scope.preset == RangePreset.custom ? scope.rangeLabel : 'Pick dates',
              ),
              onPressed: () => _pickRange(context, scope),
            ),
          ),
          if (scope.fleet.locations.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: Icon(
                  scope.macCode != null
                      ? Icons.point_of_sale_rounded
                      : scope.locCode != null
                      ? Icons.storefront_rounded
                      : Icons.apartment_rounded,
                  size: 17,
                ),
                label: Text(scope.placeLabel),
                onPressed: () => _pickPlace(context, scope),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickRange(BuildContext context, MonitorScope scope) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: DateTimeRange(start: scope.from, end: scope.to),
    );
    if (picked != null) scope.applyCustom(picked.start, picked.end);
  }

  /// Dismissing the sheet must leave the filter alone, so "everything" travels
  /// as an explicit sentinel rather than as null.
  static const _wholeBusiness = '__all__';

  /// Whole business, one shop, or one counter inside a shop.
  ///
  /// Shops are how the business is really divided, so they lead. Counters are
  /// offered underneath the shop they belong to, for the owner who wants to see
  /// what one till did.
  Future<void> _pickPlace(BuildContext context, MonitorScope scope) async {
    final locations = scope.fleet.locations;
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Show figures from',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Every figure, list and total follows this choice.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.apartment_rounded),
                title: Text(locations.length > 1 ? 'All shops together' : 'Whole business'),
                subtitle: locations.length > 1
                    ? Text('${locations.length} shops as one picture')
                    : null,
                selected: scope.locCode == null,
                onTap: () => Navigator.of(sheetContext).pop(_wholeBusiness),
              ),
              for (final location in locations) ...[
                ListTile(
                  leading: const Icon(Icons.storefront_rounded),
                  title: Text(location.name),
                  subtitle: Text(location.subtitle),
                  selected: scope.locCode == location.locCode && scope.macCode == null,
                  onTap: () => Navigator.of(sheetContext).pop(location.locCode),
                ),
                for (final counter in location.counters)
                  Padding(
                    padding: const EdgeInsets.only(left: 28),
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.point_of_sale_rounded, size: 20),
                      title: Text(counter.name),
                      subtitle: Text('${location.name} · this counter only'),
                      selected: scope.locCode == location.locCode &&
                          scope.macCode == counter.macCode,
                      onTap: () => Navigator.of(sheetContext)
                          .pop('${location.locCode}/${counter.macCode}'),
                    ),
                  ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (selected == null) return;
    if (selected == _wholeBusiness) {
      scope.selectPlace();
      return;
    }
    final parts = selected.split('/');
    scope.selectPlace(
      locCode: parts.first,
      macCode: parts.length > 1 ? parts[1] : null,
    );
  }
}
