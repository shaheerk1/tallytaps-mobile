import 'package:flutter_test/flutter_test.dart';
import 'package:tally/models/mobile_bill.dart';

void main() {
  test('mobile bill snapshots weight and configured charges', () {
    const item = CatalogItem(
      nodeId: 'node-1',
      sourceProductKey: '8',
      name: 'Rice',
      unitPrice: 100,
      attributes: {
        'pricing_basis': 'kilos',
        'bag_charge': 4,
        'wage_charge': 2,
        'wage_basis': 'kilos',
      },
    );
    final line = MobileBillLine(item: item, quantity: 1, kilos: 2.5);
    expect(line.merchandiseTotal, 250);
    expect(line.bagChargeTotal, 4);
    expect(line.wageChargeTotal, 5);
    expect(line.lineTotal, 259);
    expect(line.toApi()['productSnapshot'], isA<Map<String, dynamic>>());
  });

  test('catalog accepts MySQL decimal attributes encoded as strings', () {
    final item = CatalogItem.fromApi('node-1', {
      'sourceProductKey': '8',
      'name': 'Rice',
      'unitPrice': '100.50',
      'attributes': {
        'pricing_basis': 'kilos',
        'handling_uom': 'box',
        'base_uom': 'kg',
        'dual_uom_enabled': '1',
        'requires_kilos': '1',
        'quantity_step': '0.25',
        'bag_charge': '4.00',
        'wage_charge': '2.50',
        'minimum_sell_price': '90.00',
        'maximum_sell_price': '150.00',
        'price_override_allowed': '1',
        'wage_basis': 'kilos',
      },
    });

    expect(item.unitPrice, 100.5);
    expect(item.handlingUom, 'box');
    expect(item.baseUom, 'kg');
    expect(item.dualUomEnabled, isTrue);
    expect(item.requiresMeasuredQuantity, isTrue);
    expect(item.quantityStep, 0.25);
    expect(item.bagCharge, 4);
    expect(item.wageCharge, 2.5);
    expect(item.minimumSellPrice, 90);
    expect(item.maximumSellPrice, 150);
    expect(item.priceOverrideAllowed, isTrue);

    final line = MobileBillLine(item: item, quantity: 2, kilos: 3);
    expect(line.merchandiseTotal, 301.5);
    expect(line.bagChargeTotal, 8);
    expect(line.wageChargeTotal, 7.5);
    expect(line.lineTotal, 317);
    expect(line.isValid, isTrue);
    expect(line.toApi(), containsPair('handlingQuantity', 2));
    expect(line.toApi(), containsPair('measuredQuantity', 3));
    expect(line.toApi(), containsPair('handlingUom', 'box'));
    expect(line.toApi(), containsPair('baseUom', 'kg'));
    expect(line.toApi(), containsPair('packagingChargeRate', 4));
  });

  test('dual UoM line enforces measured quantity and price-change reason', () {
    const item = CatalogItem(
      nodeId: 'node-1',
      sourceProductKey: '9',
      name: 'Variable box',
      unitPrice: 10,
      attributes: {
        'handling_uom': 'box',
        'base_uom': 'kg',
        'dual_uom_enabled': 1,
        'allow_zero_quantity': 1,
        'pricing_basis': 'kilos',
        'price_override_allowed': 1,
        'price_override_reason_required': 1,
      },
    );

    final line = MobileBillLine(item: item, quantity: 0, unitPriceOverride: 12);
    expect(line.isValid, isFalse);

    line.kilos = 2.5;
    expect(line.isValid, isFalse);

    line.priceOverrideReason = 'Field-agreed rate';
    expect(line.isValid, isTrue);
    expect(line.lineTotal, 30);
    expect(line.toApi(), containsPair('priceOverrideApplied', true));
    expect(
      line.toApi(),
      containsPair('priceOverrideReason', 'Field-agreed rate'),
    );
  });

  test('catalog database hydration tolerates numeric strings', () {
    final item = CatalogItem.fromDb({
      'node_id': 'node-1',
      'source_product_key': '8',
      'name': 'Rice',
      'sku': null,
      'barcode': null,
      'category': null,
      'unit': 'kg',
      'unit_price': '42.25',
      'attributes': '{"bag_charge":"3.50"}',
    });

    expect(item.unitPrice, 42.25);
    expect(item.bagCharge, 3.5);
  });
}
