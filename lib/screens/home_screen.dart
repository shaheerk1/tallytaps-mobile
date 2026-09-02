import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/category_spec.dart';
import '../models/tally_action.dart';
import '../state/tally_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../monitor/monitor_screen.dart';
import '../widgets/category_button.dart';
import 'entry_screen.dart';
import 'history_screen.dart';
import 'mobile_billing_screen.dart';

/// Landing screen. The whole first view is dedicated to starting a new action:
/// a friendly prompt on top and the four big category buttons docked at the
/// bottom so they sit right under the thumb. Past entries live one tap away.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TallyStore>();

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              unsyncedCount: store.unsynced.length + store.pendingBillCount,
            ),
            _TodaySummary(
              incoming: store.todayIncoming(),
              outgoing: store.todayOutgoing(),
              count: store.today.length,
            ),
            // Shown only while the host grants this device monitor access.
            // The server re-checks on every request, so a withdrawn grant
            // removes this entry point as soon as the app next asks.
            if (store.monitorAccess)
              _MonitorEntry(
                onOpen: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MonitorScreen()),
                ),
              ),
            Expanded(
              child: store.lastRecorded != null
                  ? _SuccessBanner(
                      key: ValueKey(store.lastRecordedNonce),
                      action: store.lastRecorded!,
                      onDone: store.clearLastRecorded,
                    )
                  : const _HeroPrompt(),
            ),
            _Dock(
              onBill: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MobileBillingScreen()),
              ),
              onCategory: (type) => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => EntryScreen(type: type)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Entry point to the Business Monitor.
///
/// Deliberately a single quiet strip rather than a dock button: recording an
/// action stays the fastest thing on this screen, and only some devices ever
/// see this at all.
class _MonitorEntry extends StatelessWidget {
  const _MonitorEntry({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Material(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            tapHaptic();
            onOpen();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.insights_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Business Monitor',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 1),
                      Text(
                        'Sales, cash, stock and bills from every POS',
                        style: TextStyle(
                          color: Color(0xFFB9C3CE),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFB9C3CE),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header: brand, date, history + sync status
// ---------------------------------------------------------------------------
class _Header extends StatelessWidget {
  const _Header({required this.unsyncedCount});

  final int unsyncedCount;

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('EEEE, d MMM').format(DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(0, 139, 255, 77),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Image.asset(
                          'assets/icons/small_icon.png',
                          width: 30,
                          height: 30,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        'TallyTaps',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  today,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          if (unsyncedCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Tooltip(
                message: '$unsyncedCount entry ready to sync to your POS',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.stock.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.cloud_upload_rounded,
                        color: AppColors.stock,
                        size: 16,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$unsyncedCount',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.stock,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            elevation: 1,
            child: InkWell(
              onTap: () {
                tapHaptic();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(13),
                child: Row(
                  children: [
                    const Icon(
                      Icons.history_rounded,
                      color: AppColors.ink,
                      size: 22,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'History',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Today summary card
// ---------------------------------------------------------------------------
class _TodaySummary extends StatelessWidget {
  const _TodaySummary({
    required this.incoming,
    required this.outgoing,
    required this.count,
  });

  final double incoming;
  final double outgoing;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: cardShadow,
      ),
      child: Row(
        children: [
          _stat(
            icon: Icons.south_west_rounded,
            color: AppColors.positive,
            label: 'Received',
            value: Money.format(incoming),
          ),
          Container(
            width: 1,
            height: 40,
            margin: const EdgeInsets.symmetric(horizontal: 14),
            color: AppColors.line,
          ),
          _stat(
            icon: Icons.north_east_rounded,
            color: AppColors.negative,
            label: 'Paid',
            value: Money.format(outgoing),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const Text(
                'entries',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkFaint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkFaint,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Friendly "what did you do?" hero
// ---------------------------------------------------------------------------
class _HeroPrompt extends StatelessWidget {
  const _HeroPrompt();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: AppColors.brand,
                  size: 52,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Hassle Free Record Keeping.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap a button below to record it in seconds.\n'
                'It reaches your POS automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                  color: AppColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Success banner: animated confirmation shown after an action is recorded
// ---------------------------------------------------------------------------
class _SuccessBanner extends StatefulWidget {
  const _SuccessBanner({super.key, required this.action, required this.onDone});

  final TallyAction action;
  final VoidCallback onDone;

  @override
  State<_SuccessBanner> createState() => _SuccessBannerState();
}

class _SuccessBannerState extends State<_SuccessBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _c,
    curve: const Interval(0, 0.3, curve: Curves.easeOut),
    reverseCurve: const Interval(0.6, 1, curve: Curves.easeIn),
  );
  late final Animation<double> _scale = Tween(begin: 0.7, end: 1.0).animate(
    CurvedAnimation(
      parent: _c,
      curve: Curves.elasticOut,
      reverseCurve: Curves.easeInBack,
    ),
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _timer = Timer(const Duration(seconds: 4), _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    await _c.reverse();
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: FadeTransition(
          opacity: _opacity,
          child: ScaleTransition(scale: _scale, child: _bannerCard(context)),
        ),
      ),
    );
  }

  Widget _bannerCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      decoration: BoxDecoration(
        color: AppColors.positive.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.positive.withValues(alpha: 0.35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.positive,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.positive.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 44,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _line,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap a button below to record the next one',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.inkSoft,
            ),
          ),
        ],
      ),
    );
  }

  String get _line {
    final a = widget.action;
    switch (a.type) {
      case ActionType.note:
        return 'Note recorded!';
      case ActionType.stock:
        final dir = a.direction == ActionDirection.incoming
            ? 'Stock in'
            : 'Stock out';
        final item = (a.item == null || a.item!.trim().isEmpty)
            ? null
            : a.item!.trim();
        final parts = [?item, if (a.qtyLabel.isNotEmpty) a.qtyLabel];
        return '$dir${parts.isEmpty ? '' : ' · ${parts.join(' · ')}'}!';
      default:
        final dir = a.direction == ActionDirection.incoming
            ? 'received'
            : 'paid';
        return '${a.type.label} $dir · ${Money.format(a.amount)}';
    }
  }
}

// ---------------------------------------------------------------------------
// The bottom dock of big category buttons
// ---------------------------------------------------------------------------
class _Dock extends StatelessWidget {
  const _Dock({required this.onCategory, required this.onBill});

  final ValueChanged<ActionType> onCategory;
  final VoidCallback onBill;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: FilledButton.icon(
                onPressed: onBill,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.ink,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  minimumSize: const Size.fromHeight(54),
                ),
                icon: const Icon(Icons.receipt_long_rounded),
                label: const Text(
                  'Create a quick bill',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 10, bottom: 6),
              child: Row(
                children: [
                  const Text(
                    'Quick record',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkFaint,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Divider(
                      color: AppColors.line.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final spec in CategorySpec.all)
                  CategoryButton(
                    spec: spec,
                    subtitle: spec.badge,
                    onTap: () => onCategory(spec.type),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
