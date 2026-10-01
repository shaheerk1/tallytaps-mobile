import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'monitor_controller.dart';

/// Dismissing the sheet must leave the filter alone, so "everything" travels
/// as an explicit sentinel rather than as null.
const _wholeBusiness = '__all__';

/// Whole business, one shop, or one counter inside a shop.
///
/// Shops are how the business is really divided, so they lead. Counters are
/// offered underneath the shop they belong to, for the owner who wants to see
/// what one till did.
Future<void> showPlacePicker(BuildContext context, MonitorScope scope) async {
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
