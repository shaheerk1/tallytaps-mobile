import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/app_theme.dart';
import 'supply_check_models.dart';

/// The warm paper a statement is written on, as the desktop prints it.
class _Paper {
  static const page = Color(0xFFFFFDF8);
  static const band = Color(0xFFFFF8EA);
  static const rule = Color(0xFFE6DCC6);
  static const ink = Color(0xFF2A2419);
  static const inkSoft = Color(0xFF7A6E57);
  static const net = Color(0xFFF2EBD8);
}

/// One statement, ready to be handed to a supplier.
///
/// It carries the goods and the money and nothing else: no supplier, no supply
/// code, no customer, no bill number. A supplier is owed for what went out at
/// what price, and the rest is the shop's own business.
class SupplyStatementSheet extends StatelessWidget {
  const SupplyStatementSheet({
    super.key,
    required this.heading,
    required this.group,
    required this.commissionPercent,
    this.footnote,
  });

  /// The day this covers, or the whole range.
  final String heading;
  final SupplyCheckGroup group;
  final double commissionPercent;
  final String? footnote;

  /// The width the sheet is drawn at before it is scaled to a screen or a file.
  static const sheetWidth = 860.0;

  /// A measure totals only when every line is counted the same way.
  static String _total(Iterable<double?> values, Iterable<String?> uoms) {
    final amounts = values.whereType<double>().toList();
    if (amounts.isEmpty) return '—';
    final sum = amounts.fold<double>(0, (total, value) => total + value);
    final kinds = uoms.whereType<String>().toSet();
    final text = Money.formatQty(sum);
    return kinds.length == 1 ? '$text ${kinds.first}' : text;
  }

  @override
  Widget build(BuildContext context) {
    final rows = group.rows;
    final unitTotal = _total(rows.map((row) => row.handlingQty), rows.map((row) => row.handlingUom));
    final measuredTotal = _total(rows.map((row) => row.baseQty), rows.map((row) => row.baseUom));

    return Container(
      width: sheetWidth,
      color: _Paper.page,
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(),
          const SizedBox(height: 14),
          _tableHead(),
          for (var index = 0; index < rows.length; index += 1)
            _line(rows[index], index.isOdd),
          Container(height: 2, color: _Paper.rule),
          const SizedBox(height: 14),
          _totals(unitTotal, measuredTotal),
          if (footnote != null) ...[
            const SizedBox(height: 16),
            Text(
              footnote!,
              style: const TextStyle(color: _Paper.inkSoft, fontSize: 13, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  /// Just the day it covers. The sheet says what it is by looking like itself,
  /// and a title over it only took room on a supplier's screen.
  Widget _header() => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      heading,
      style: const TextStyle(color: _Paper.ink, fontSize: 19, fontWeight: FontWeight.w900),
    ),
  );

  Widget _tableHead() => Container(
    color: _Paper.band,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    child: Row(
      children: const [
        Expanded(flex: 30, child: _Head('ITEM')),
        Expanded(flex: 15, child: _Head('UNIT COUNT', end: true)),
        Expanded(flex: 18, child: _Head('MEASURED QTY', end: true)),
        Expanded(flex: 16, child: _Head('RATE', end: true)),
        Expanded(flex: 21, child: _Head('LINE TOTAL', end: true)),
      ],
    ),
  );

  Widget _line(SupplyCheckRow row, bool shaded) => Container(
    decoration: BoxDecoration(
      color: shaded ? _Paper.band.withValues(alpha: .45) : _Paper.page,
      border: const Border(bottom: BorderSide(color: _Paper.rule)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 30,
          child: Text(
            row.description.trim().isEmpty ? row.itemCode : row.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _Paper.ink, fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(flex: 15, child: _Cell('${Money.formatQty(row.handlingQty)} ${row.handlingUom}')),
        Expanded(
          flex: 18,
          child: _Cell(
            row.baseQty == null
                ? '—'
                : '${Money.formatQty(row.baseQty!)} ${row.baseUom ?? ''}'.trim(),
          ),
        ),
        Expanded(flex: 16, child: _Cell(Money.format(row.unitPrice))),
        Expanded(flex: 21, child: _Cell(Money.format(row.merchandise), bold: true)),
      ],
    ),
  );

  Widget _totals(String unitTotal, String measuredTotal) => Column(
    children: [
      _TotalRow(label: 'Total unit count', value: unitTotal),
      _TotalRow(label: 'Total measured qty', value: measuredTotal),
      const SizedBox(height: 8),
      _TotalRow(label: 'Merchandise subtotal', value: Money.format(group.merchandise), strong: true),
      if (commissionPercent > 0)
        _TotalRow(
          label: 'Commission ${_percent(commissionPercent)}%',
          value: '- ${Money.format(group.commission)}',
        ),
      const SizedBox(height: 6),
      Container(
        color: _Paper.net,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'NET PAYABLE',
                style: TextStyle(
                  color: _Paper.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .6,
                ),
              ),
            ),
            Text(
              Money.format(group.netPayable),
              style: const TextStyle(
                color: _Paper.ink,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  static String _percent(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';
}

class _Head extends StatelessWidget {
  const _Head(this.text, {this.end = false});

  final String text;
  final bool end;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: end ? TextAlign.right : TextAlign.left,
    style: const TextStyle(
      color: _Paper.inkSoft,
      fontSize: 11.5,
      fontWeight: FontWeight.w900,
      letterSpacing: .7,
    ),
  );
}

class _Cell extends StatelessWidget {
  const _Cell(this.text, {this.bold = false});

  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.right,
    maxLines: 1,
    style: TextStyle(
      color: _Paper.ink,
      fontSize: 15,
      fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    ),
  );
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.strong = false});

  final String label, value;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: strong ? _Paper.ink : _Paper.inkSoft,
              fontSize: strong ? 15 : 14,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 18),
        SizedBox(
          width: 170,
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 1,
            style: TextStyle(
              color: _Paper.ink,
              fontSize: strong ? 16 : 14.5,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    ),
  );
}

/// Turns a drawn sheet into a picture a supplier can be sent.
///
/// The sheet is laid out at its own width whatever the phone is, and only then
/// scaled to fit the screen, so what is captured is the full sheet at full size
/// rather than the part that happened to be visible.
Future<Uint8List?> captureSheet(GlobalKey boundaryKey, {double pixelRatio = 2.5}) async {
  final object = boundaryKey.currentContext?.findRenderObject();
  if (object is! RenderRepaintBoundary) return null;
  final image = await object.toImage(pixelRatio: pixelRatio);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data?.buffer.asUint8List();
}

/// Puts the picture on disk where the phone can pick it up.
///
/// It has to be a real file: what shares it copies the picture out of the path
/// it is given, so bytes held only in memory arrive as a file that is not there.
Future<XFile> writeSheet(Uint8List png, String name, Directory directory) async {
  final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '-');
  final file = File('${directory.path}/$safe.png');
  await file.writeAsBytes(png, flush: true);
  return XFile(file.path, mimeType: 'image/png', name: '$safe.png');
}

/// Writes a captured sheet beside the app's own files and hands it to whatever
/// the phone shares with.
Future<void> shareSheet(Uint8List png, String name, {String? message}) async {
  final file = await writeSheet(png, name, await getTemporaryDirectory());
  await SharePlus.instance.share(ShareParams(files: [file], text: message));
}
