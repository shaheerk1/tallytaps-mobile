import 'package:flutter_test/flutter_test.dart';
import 'package:tally/monitor/monitor_supply_models.dart';

void main() {
  test('a delivery note reads with its supplier and both measures', () {
    final detail = MonitorGoodsReceiptDetail.fromMap({
      'nodeId': 'node-1',
      'grn': {
        'grnId': '11', 'grnNumber': 'GRN-11', 'status': 'finalized',
        'businessDate': '2099-11-01', 'supplierName': 'Perera Stores',
        'ownershipModel': 'owned', 'vehicleNo': 'LP-1234', 'lineCount': 1,
      },
      'lines': [
        {
          'lineNo': 1, 'productName': 'Rice', 'handlingQty': 4, 'handlingUom': 'bag',
          'baseQty': 100, 'baseUom': 'kg', 'unitCost': 90, 'lineValue': 9000,
        },
      ],
    });

    expect(detail.grn.supplierLabel, 'Perera Stores');
    expect(detail.grn.isDraft, isFalse);
    expect(detail.grn.isOwned, isTrue);
    expect(detail.lines.single.baseQty, 100);
    expect(detail.total, 9000);
  });

  test('a lot says what is left and how old it is', () {
    final lot = MonitorActiveLot.fromMap({
      'lotId': '21', 'productName': 'Rice', 'businessDate': '2099-11-01', 'ageDays': 3,
      'remainingHandling': 3, 'receivedHandling': 4, 'handlingUom': 'bag',
      'remainingBase': 72, 'receivedBase': 100, 'baseUom': 'kg',
      'ownershipModel': 'consignment', 'lotTag': 'RCE1', 'supplierName': 'Perera Stores',
    });

    expect(lot.isEmpty, isFalse);
    expect(lot.isOwned, isFalse);
    expect(lot.ageText, '3 days old');
    expect(lot.remainingText, contains('3 bag'));
    expect(lot.remainingText, contains('72 kg'));
  });

  test('an emptied lot is marked as such', () {
    final lot = MonitorActiveLot.fromMap({
      'lotId': '22', 'productName': 'Rice', 'remainingHandling': 0, 'receivedHandling': 2,
      'handlingUom': 'bag', 'ageDays': 0, 'ownershipModel': 'owned',
    });
    expect(lot.isEmpty, isTrue);
    expect(lot.ageText, 'today');
  });

  test('a statement carries its type, period and money', () {
    final detail = MonitorStatementDetail.fromMap({
      'nodeId': 'node-1',
      'statement': {
        'statementId': '31', 'statementNumber': 'PAT-31', 'status': 'finalized',
        'statementType': 'consignment', 'supplierName': 'Perera Stores',
        'fromDate': '2099-11-01', 'toDate': '2099-11-02',
        'merchandiseSubtotal': 10000, 'commissionRate': 10, 'commissionAmount': 1000,
        'adjustmentTotal': -500, 'netPayable': 8500, 'bagChargeTotal': 80,
      },
      'lines': [
        {
          'kind': 'sale', 'description': 'Rice', 'unitPrice': 100, 'quantity': 4,
          'kilos': 100, 'amount': 10000, 'receiptNo': 7,
        },
      ],
      'adjustments': [
        {'type': 'deduction', 'label': 'Lorry wage', 'amount': -500},
      ],
    });

    expect(detail.statement.typeLabel, 'Consignment');
    expect(detail.statement.periodText, '2099-11-01 to 2099-11-02');
    expect(detail.statement.netPayable, 8500);
    expect(detail.bagChargeTotal, 80);
    expect(detail.lines.single.kindLabel, 'Sale');
    expect(detail.adjustments.single.isCredit, isFalse);
  });

  test('a supplier account sheet ends on its balance', () {
    final sheet = MonitorAccountSheet.fromMap({
      'supplier': {'supplierId': '5', 'name': 'Perera Stores', 'code': 'PER'},
      'totalOwed': 8500, 'totalPaid': 3000, 'balance': 5500,
      'lines': [
        {
          'kind': 'statement', 'date': '2099-11-01', 'reference': 'PAT-31',
          'description': 'Sales statement', 'owed': 8500, 'paid': 0, 'balance': 8500,
        },
        {
          'kind': 'payment', 'date': '2099-11-02', 'reference': 'SAE-41',
          'description': 'Payment', 'owed': 0, 'paid': 3000, 'balance': 5500,
          'reversed': false,
        },
      ],
    });

    expect(sheet.supplierName, 'Perera Stores');
    expect(sheet.lines.last.balance, 5500);
    expect(sheet.balance, 5500);
  });

  test('a supplier owed nothing reads as settled', () {
    final account = MonitorSupplierAccount.fromMap({
      'supplierId': '9', 'supplierName': 'Silva Farm', 'balance': 0, 'paid': 1000,
      'statements': 2,
    });
    expect(account.isSettled, isTrue);
    expect(account.theyOweUs, isFalse);
  });
}
