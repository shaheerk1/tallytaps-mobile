import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../monitor/monitor_controller.dart';
import '../monitor/monitor_models.dart';
import '../monitor/monitor_operations.dart';
import '../monitor/monitor_place_picker.dart';
import '../monitor/monitor_supply.dart';
import '../monitor/monitor_supply_models.dart';
import '../monitor/monitor_widgets.dart';
import '../state/tally_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// What is owed, both ways, on one page.
///
/// Money owed is not a thing that happened on a day, so nothing here follows a
/// date range: a bill from last month is owed exactly as much as one from this
/// morning. It can still be narrowed to one shop or one counter, because that
/// is how the money is actually chased.
class MoneyScreen extends StatefulWidget {
  const MoneyScreen({super.key});

  @override
  State<MoneyScreen> createState() => _MoneyScreenState();
}

class _MoneyScreenState extends State<MoneyScreen> {
  final MonitorScope _scope = MonitorScope();
  MonitorRepository? _repository;
  bool _askedForFleet = false;
  int _side = 0;

  double? _owedToUs;
  double? _weOwe;

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  Future<void> _loadFleet(MonitorRepository repository) async {
    try {
      final fleet = await repository.fleet();
      if (mounted) _scope.setFleet(fleet);
    } catch (_) {
      // Without the fleet there is simply no shop filter to offer.
    }
  }

  /// A total arrives while a list is building, so it is kept for the next
  /// frame rather than set in the middle of this one.
  void _remember(VoidCallback apply) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(apply);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasMonitor = context.select<TallyStore, bool>((store) => store.monitorAccess);
    if (!hasMonitor) return const _NeedsAccess();

    final store = context.read<TallyStore>();
    final repository = _repository ??= MonitorRepository(store: store);
    if (!_askedForFleet) {
      _askedForFleet = true;
      _loadFleet(repository);
    }

    return ChangeNotifierProvider<MonitorScope>.value(
      value: _scope,
      child: Provider<MonitorRepository>.value(
        value: repository,
        child: Builder(
          builder: (context) {
            final scope = context.watch<MonitorScope>();
            return Column(
              children: [
                _PlaceBar(scope: scope),
                _Totals(
                  owedToUs: _owedToUs,
                  weOwe: _weOwe,
                  side: _side,
                  onPick: (side) => setState(() => _side = side),
                ),
                Expanded(
                  child: _side == 0
                      ? _OwedToUs(onTotal: (value) => _remember(() => _owedToUs = value))
                      : _WeOwe(onTotal: (value) => _remember(() => _weOwe = value)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Which shop or counter the figures are for. One line, out of the way.
class _PlaceBar extends StatelessWidget {
  const _PlaceBar({required this.scope});

  final MonitorScope scope;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Not tied to dates · everything still unpaid',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.inkFaint,
              ),
            ),
          ),
          if (scope.fleet.locations.isNotEmpty)
            ActionChip(
              visualDensity: VisualDensity.compact,
              avatar: Icon(
                scope.macCode != null
                    ? Icons.point_of_sale_rounded
                    : scope.locCode != null
                    ? Icons.storefront_rounded
                    : Icons.apartment_rounded,
                size: 16,
              ),
              label: Text(
                scope.placeLabel,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              onPressed: () {
                tapHaptic();
                showPlacePicker(context, scope);
              },
            ),
        ],
      ),
    );
  }
}

/// The two sides of the money: each is the total, and the way into its list.
class _Totals extends StatelessWidget {
  const _Totals({
    required this.owedToUs,
    required this.weOwe,
    required this.side,
    required this.onPick,
  });

  final double? owedToUs;
  final double? weOwe;
  final int side;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(
        children: [
          Expanded(
            child: _TotalCard(
              label: 'Owed to us',
              amount: owedToUs,
              icon: Icons.call_received_rounded,
              tone: AppColors.positive,
              selected: side == 0,
              onTap: () {
                tapHaptic();
                onPick(0);
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _TotalCard(
              label: 'We owe',
              amount: weOwe,
              icon: Icons.call_made_rounded,
              tone: AppColors.negative,
              selected: side == 1,
              onTap: () {
                tapHaptic();
                onPick(1);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.label,
    required this.amount,
    required this.icon,
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final double? amount;
  final IconData icon;
  final Color tone;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(13, 11, 11, 11),
        decoration: BoxDecoration(
          color: selected ? AppColors.surface : AppColors.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? tone.withValues(alpha: 0.45) : AppColors.line,
            width: selected ? 1.4 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: tone.withValues(alpha: 0.14),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : const [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 15, color: selected ? tone : AppColors.inkFaint),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: selected ? AppColors.ink : AppColors.inkSoft,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                amount == null ? '—' : Money.format(amount!),
                maxLines: 1,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: selected ? tone : AppColors.inkSoft,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Customers carrying an unpaid balance, and the bills behind each of them.
class _OwedToUs extends StatelessWidget {
  const _OwedToUs({required this.onTotal});

  final ValueChanged<double> onTotal;

  @override
  Widget build(BuildContext context) {
    final scope = context.watch<MonitorScope>();
    final repository = context.read<MonitorRepository>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
      children: [
        MonitorAsync<List<MonitorReceivable>>(
          reloadKey: 'owed-to-us|${scope.placeKey}',
          height: 260,
          load: () => repository.receivables(scope),
          builder: (context, rows) {
            onTotal(rows.fold<double>(0, (sum, row) => sum + row.balance));
            if (rows.isEmpty) {
              return const MonitorCard(
                title: 'Owed by customers',
                child: MonitorEmpty(
                  message: 'Every bill is settled. Nothing is owed.',
                  icon: Icons.verified_outlined,
                ),
              );
            }
            return MonitorCard(
              title: 'Owed by customers',
              subtitle: '${rows.length} customer${rows.length == 1 ? '' : 's'} · '
                  'largest first',
              child: Column(
                children: [
                  for (final row in rows) ...[
                    MonitorRow(
                      title: row.title,
                      subtitle: [
                        row.customerCode,
                        '${row.invoiceCount} unpaid bill${row.invoiceCount == 1 ? '' : 's'}',
                        'oldest ${row.oldest}',
                      ].join(' · '),
                      trailing: Money.format(row.balance),
                      tone: AppColors.stock,
                      onTap: () => pushMonitorRoute(
                        context,
                        MonitorCustomerBillsScreen(receivable: row),
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
    );
  }
}

/// Suppliers waiting to be paid, and the account sheet behind each of them.
class _WeOwe extends StatelessWidget {
  const _WeOwe({required this.onTotal});

  final ValueChanged<double> onTotal;

  @override
  Widget build(BuildContext context) {
    final scope = context.watch<MonitorScope>();
    final repository = context.read<MonitorRepository>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
      children: [
        MonitorAsync<List<MonitorSupplierAccount>>(
          reloadKey: 'we-owe|${scope.placeKey}',
          height: 260,
          load: () => repository.supplierAccounts(scope),
          builder: (context, rows) {
            final owing = rows.where((row) => !row.isSettled).toList();
            final payees = owing.where((row) => row.balance > 0).toList();
            onTotal(payees.fold<double>(0, (sum, row) => sum + row.balance));
            if (owing.isEmpty) {
              return const MonitorCard(
                title: 'Owed to suppliers',
                child: MonitorEmpty(
                  message: 'Nothing is owed to a supplier right now.',
                  icon: Icons.handshake_outlined,
                ),
              );
            }
            return MonitorCard(
              title: 'Owed to suppliers',
              subtitle: '${payees.length} supplier${payees.length == 1 ? '' : 's'} to pay'
                  '${owing.length > payees.length ? ' · ${owing.length - payees.length} owe us' : ''}',
              child: Column(
                children: [
                  for (final account in owing) ...[
                    MonitorRow(
                      title: account.supplierName,
                      subtitle: [
                        if (account.supplierCode != null) account.supplierCode!,
                        '${account.statements} statement${account.statements == 1 ? '' : 's'}',
                        if (account.lastPayment != null) 'last paid ${account.lastPayment}',
                      ].join(' · '),
                      trailing: Money.format(account.balance.abs()),
                      trailingHint: account.theyOweUs ? 'they owe us' : 'to pay',
                      tone: account.theyOweUs ? AppColors.positive : AppColors.stock,
                      onTap: () => pushMonitorRoute(
                        context,
                        MonitorSupplierAccountScreen(
                          supplierId: account.supplierId,
                          title: account.supplierName,
                        ),
                      ),
                    ),
                    if (account != owing.last) monitorDivider,
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

class _NeedsAccess extends StatelessWidget {
  const _NeedsAccess();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline_rounded, size: 52, color: AppColors.inkFaint),
            const SizedBox(height: 12),
            const Text(
              'Not shared with this phone yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'What customers owe and what the shop owes its suppliers comes '
              'from the host. Ask for monitor access, and it appears here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
