import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/sync_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'monitor_controller.dart';

/// Pushes a monitor sub-page while preserving the monitor-owned dependencies.
/// A route added to the root Navigator is a sibling of [MonitorScreen], so it
/// cannot otherwise see providers created inside that screen.
Future<T?> pushMonitorRoute<T>(BuildContext context, Widget child) {
  final repository = context.read<MonitorRepository>();
  final scope = context.read<MonitorScope>();
  return Navigator.of(context).push<T>(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider<MonitorScope>.value(
        value: scope,
        child: Provider<MonitorRepository>.value(
          value: repository,
          child: child,
        ),
      ),
    ),
  );
}

/// Shared building blocks for the Business Monitor.
///
/// The monitor is read-only and information dense, so it uses a calmer, flatter
/// vocabulary than the recording screens: plain cards, one accent per meaning,
/// and numbers large enough to read at arm's length.

const double kMonitorRadius = 18;

/// Loads once, reloads whenever [reloadKey] changes, and renders the three
/// states every monitor panel needs.
class MonitorAsync<T> extends StatefulWidget {
  const MonitorAsync({
    super.key,
    required this.reloadKey,
    required this.load,
    required this.builder,
    this.height = 160,
  });

  final Object reloadKey;
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T value) builder;
  final double height;

  @override
  State<MonitorAsync<T>> createState() => _MonitorAsyncState<T>();
}

class _MonitorAsyncState<T> extends State<MonitorAsync<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  @override
  void didUpdateWidget(covariant MonitorAsync<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadKey != widget.reloadKey) {
      _future = widget.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: widget.height,
            child: const Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          // A withdrawn grant is handled by the shell, which closes the section.
          if (snapshot.error is MonitorAccessRevoked) {
            return const SizedBox.shrink();
          }
          return _MonitorError(
            message: '${snapshot.error}',
            onRetry: () => setState(() => _future = widget.load()),
          );
        }
        return widget.builder(context, snapshot.data as T);
      },
    );
  }
}

class _MonitorError extends StatelessWidget {
  const _MonitorError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(kMonitorRadius),
        border: Border.all(color: const Color(0xFFF3D2D2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Could not load this',
            style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.negative),
          ),
          const SizedBox(height: 4),
          Text(message, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
          const SizedBox(height: 10),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

/// A titled card. Everything in the monitor lives inside one of these.
class MonitorCard extends StatelessWidget {
  const MonitorCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.action,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? action;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(kMonitorRadius),
        boxShadow: cardShadow,
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title!,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.inkFaint,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                ?action,
              ],
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}

/// One headline number. [tone] carries the meaning, not decoration.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.tone = AppColors.ink,
    this.onTap,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final String? hint;
  final Color tone;
  final VoidCallback? onTap;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: emphasis ? tone.withValues(alpha: 0.08) : AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: emphasis ? tone.withValues(alpha: 0.25) : AppColors.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: AppColors.inkFaint,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: tone,
                letterSpacing: -0.4,
              ),
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 3),
            Text(
              hint!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.inkSoft,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return body;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        tapHaptic();
        onTap!();
      },
      child: body,
    );
  }
}

/// Two-column metric grid that keeps tiles the same height.
class MetricGrid extends StatelessWidget {
  const MetricGrid({super.key, required this.tiles, this.columns = 2});

  final List<Widget> tiles;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final width =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}

/// A label/amount line, used for tender splits and totals.
class AmountRow extends StatelessWidget {
  const AmountRow({
    super.key,
    required this.label,
    required this.amount,
    this.hint,
    this.tone,
    this.bold = false,
  });

  final String label;
  final String amount;
  final String? hint;
  final Color? tone;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                if (hint != null)
                  Text(
                    hint!,
                    style: const TextStyle(fontSize: 11, color: AppColors.inkFaint),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            amount,
            style: TextStyle(
              fontSize: bold ? 16 : 14,
              fontWeight: FontWeight.w800,
              color: tone ?? AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// A short status word. Colour comes from meaning, never from the word itself.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: tone,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Colour for a lifecycle word, so the same status always reads the same way.
Color statusTone(String status) => switch (status) {
  'paid' || 'cleared' || 'closed' || 'finalized' || 'active' => AppColors.cash,
  'partial' || 'open' || 'received' || 'deposited' || 'blind_closed' ||
  'issued' || 'prepared' => AppColors.stock,
  'dishonoured' || 'returned' || 'returned_unpaid' || 'stopped' ||
  'cancelled' || 'void' => AppColors.negative,
  _ => AppColors.inkFaint,
};

String prettyStatus(String status) =>
    status.replaceAll('_', ' ').replaceAll('-', ' ');

/// "40 bags · 2,000 kg" — a dual-unit measure written the way the market says
/// it, with the second unit dropped when an item only has one.
String measureText({
  required double handlingQty,
  required String handlingUom,
  double? baseQty,
  String? baseUom,
}) {
  final handling = '${Money.formatQty(handlingQty)} $handlingUom';
  if (baseQty == null || baseUom == null || baseUom.isEmpty) return handling;
  return '$handling · ${Money.formatQty(baseQty)} $baseUom';
}

/// A horizontal comparison bar. Deliberately plain: the number is the point,
/// the bar only gives it a shape to scan.
class ComparisonBar extends StatelessWidget {
  const ComparisonBar({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    required this.amount,
    this.hint,
    this.tone = AppColors.brand,
  });

  final String label;
  final double value;
  final double max;
  final String amount;
  final String? hint;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final fraction = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                amount,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 7,
              backgroundColor: AppColors.line,
              valueColor: AlwaysStoppedAnimation(tone),
            ),
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                hint!,
                style: const TextStyle(fontSize: 11, color: AppColors.inkFaint),
              ),
            ),
        ],
      ),
    );
  }
}

/// Says plainly that there is nothing to show, and why.
class MonitorEmpty extends StatelessWidget {
  const MonitorEmpty({super.key, required this.message, this.icon = Icons.inbox_rounded});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Column(
        children: [
          Icon(icon, size: 30, color: AppColors.inkFaint),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.inkSoft,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A tappable list row with a leading glyph, used across every list screen.
class MonitorRow extends StatelessWidget {
  const MonitorRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.trailingHint,
    this.leading,
    this.tone,
    this.onTap,
    this.trailingAction,
  });

  final String title;
  final String subtitle;
  final String? trailing;
  final String? trailingHint;
  final Widget? leading;
  final Color? tone;
  final VoidCallback? onTap;
  final Widget? trailingAction;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap == null
          ? null
          : () {
              tapHaptic();
              onTap!();
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 11)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.inkFaint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    trailing!,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: tone ?? AppColors.ink,
                    ),
                  ),
                  if (trailingHint != null)
                    Text(
                      trailingHint!,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.inkFaint,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ],
            if (trailingAction != null) ...[
              const SizedBox(width: 8),
              trailingAction!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Thin separator used between rows inside a card.
const monitorDivider = Divider(height: 18, color: AppColors.line);
