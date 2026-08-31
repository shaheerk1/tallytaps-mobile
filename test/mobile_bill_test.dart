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
}
