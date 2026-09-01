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
