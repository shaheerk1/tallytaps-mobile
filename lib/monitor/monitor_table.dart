import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// One column of a table: how wide it sits, and which way it reads.
class TableColumnSpec {
  const TableColumnSpec(this.label, {this.width = 110, this.numeric = false});

  final String label;
  final double width;
  final bool numeric;
}

/// One row: its cells, and how it should carry itself.
class TableRowSpec {
  const TableRowSpec(
    this.cells, {
    this.tone,
    this.struckThrough = false,
    this.emphasis = false,
  });

  final List<String> cells;
  final Color? tone;

  /// A reversed or cancelled record: still shown, but plainly not counted.
  final bool struckThrough;

  /// A totals row, or one worth the eye stopping at.
  final bool emphasis;
}

/// A desktop-style table on a phone: it scrolls both ways, and pinching zooms
/// it in and out, because these sheets are made to be read closely.
///
/// The head stays on screen while the rows scroll under it. Nothing is hidden
/// behind a tap: everything on the sheet is on the sheet.
class MonitorDataTable extends StatefulWidget {
  const MonitorDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.footer,
    this.height = 420,
  });

  final List<TableColumnSpec> columns;
  final List<TableRowSpec> rows;

  /// A totals line, kept in view under the rows.
  final TableRowSpec? footer;
  final double height;

  @override
  State<MonitorDataTable> createState() => _MonitorDataTableState();
}

class _MonitorDataTableState extends State<MonitorDataTable> {
  final TransformationController _zoom = TransformationController();
  final ScrollController _vertical = ScrollController();
  double _scale = 1;

  @override
  void dispose() {
    _zoom.dispose();
    _vertical.dispose();
    super.dispose();
  }

  void _setScale(double scale) {
    final next = scale.clamp(0.6, 2.2).toDouble();
    if ((next - _scale).abs() < 0.01) return;
    setState(() => _scale = next);
    _zoom.value = Matrix4.identity()..scaleByDouble(next, next, 1, 1);
  }

  double get _tableWidth =>
      widget.columns.fold<double>(0, (sum, column) => sum + column.width);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Pinch to zoom · drag to move around',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkFaint,
                ),
              ),
            ),
            _ZoomButton(
              icon: Icons.remove_rounded,
              tooltip: 'Smaller',
              onTap: () => _setScale(_scale - 0.2),
            ),
            const SizedBox(width: 6),
            _ZoomButton(
              icon: Icons.add_rounded,
              tooltip: 'Bigger',
              onTap: () => _setScale(_scale + 0.2),
            ),
            const SizedBox(width: 6),
            _ZoomButton(
              icon: Icons.fit_screen_outlined,
              tooltip: 'Fit again',
              onTap: () => _setScale(1),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: widget.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: InteractiveViewer(
              transformationController: _zoom,
              minScale: 0.6,
              maxScale: 2.2,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(40),
              onInteractionEnd: (_) {
                final scale = _zoom.value.getMaxScaleOnAxis();
                if ((scale - _scale).abs() > 0.01) setState(() => _scale = scale);
              },
              child: SizedBox(
                width: _tableWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _HeadRow(columns: widget.columns),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: widget.height * 2),
                      child: ListView.builder(
                        controller: _vertical,
                        shrinkWrap: true,
                        primary: false,
                        itemCount: widget.rows.length,
                        itemBuilder: (context, index) => _BodyRow(
                          columns: widget.columns,
                          row: widget.rows[index],
                          striped: index.isOdd,
                        ),
                      ),
                    ),
                    if (widget.footer != null)
                      _BodyRow(
                        columns: widget.columns,
                        row: widget.footer!,
                        striped: false,
                        isFooter: true,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () {
          tapHaptic();
          onTap();
        },
        child: Container(
          width: 34,
          height: 30,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(9),
            color: AppColors.surface,
          ),
          child: Icon(icon, size: 17, color: AppColors.inkSoft),
        ),
      ),
    );
  }
}

class _HeadRow extends StatelessWidget {
  const _HeadRow({required this.columns});

  final List<TableColumnSpec> columns;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.line, width: 1.4)),
      ),
      child: Row(
        children: [
          for (final column in columns)
            SizedBox(
              width: column.width,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                child: Text(
                  column.label.toUpperCase(),
                  textAlign: column.numeric ? TextAlign.right : TextAlign.left,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                    color: AppColors.inkFaint,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BodyRow extends StatelessWidget {
  const _BodyRow({
    required this.columns,
    required this.row,
    required this.striped,
    this.isFooter = false,
  });

  final List<TableColumnSpec> columns;
  final TableRowSpec row;
  final bool striped;
  final bool isFooter;

  @override
  Widget build(BuildContext context) {
    final color = row.tone ?? AppColors.ink;
    return Container(
      decoration: BoxDecoration(
        color: isFooter
            ? AppColors.background
            : striped
            ? AppColors.background.withValues(alpha: 0.55)
            : AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.line.withValues(alpha: 0.8)),
          top: isFooter
              ? const BorderSide(color: AppColors.line, width: 1.4)
              : BorderSide.none,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < columns.length; index += 1)
            SizedBox(
              width: columns[index].width,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                child: Text(
                  index < row.cells.length ? row.cells[index] : '',
                  textAlign: columns[index].numeric
                      ? TextAlign.right
                      : TextAlign.left,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: isFooter || row.emphasis
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: row.struckThrough ? AppColors.inkFaint : color,
                    decoration: row.struckThrough
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                    fontFeatures: columns[index].numeric
                        ? const [FontFeature.tabularFigures()]
                        : null,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
