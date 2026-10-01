import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../monitor/monitor_screen.dart';
import '../state/tally_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'history_screen.dart';
import 'money_screen.dart';
import 'notes_home_screen.dart';
import 'sync_setup_screen.dart';

/// The whole app, in three places: the notebook, the shop as it runs, and what
/// is owed either way.
///
/// The notebook comes first because it is the one thing a person in the field
/// does, and it must be one tap from anywhere.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TallyStore>();
    final pending = store.unsynced.length + store.pendingBillCount;
    final hasMonitor = store.monitorAccess;
    final tabs = <_ShellTab>[
      const _ShellTab(label: 'Notes', icon: Icons.edit_note_rounded, tone: AppColors.note),
      if (hasMonitor)
        const _ShellTab(label: 'Business', icon: Icons.insights_rounded, tone: AppColors.cash),
      if (hasMonitor)
        const _ShellTab(label: 'Owed', icon: Icons.swap_horiz_rounded, tone: AppColors.card),
    ];
    final index = _tab.clamp(0, tabs.length - 1);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(pending: pending),
            if (tabs.length > 1)
              Container(
                margin: const EdgeInsets.fromLTRB(14, 2, 14, 4),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.line.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    for (var position = 0; position < tabs.length; position += 1)
                      Expanded(
                        child: _TabButton(
                          tab: tabs[position],
                          selected: position == index,
                          onTap: () {
                            tapHaptic();
                            setState(() => _tab = position);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: IndexedStack(
                index: index,
                children: [
                  const NotesHomeScreen(),
                  if (hasMonitor) const MonitorScreen(embedded: true),
                  if (hasMonitor) const MoneyScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellTab {
  const _ShellTab({required this.label, required this.icon, required this.tone});

  final String label;
  final IconData icon;

  /// Its own colour, which only shows when you are standing in it.
  final Color tone;
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.tab, required this.selected, required this.onTap});

  final _ShellTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x1A101828),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ]
              : const [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              tab.icon,
              size: 18,
              color: selected ? tab.tone : AppColors.inkFaint,
            ),
            const SizedBox(width: 6),
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: selected ? AppColors.ink : AppColors.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The app's own line: its name, and whether anything is still waiting to go.
class _Header extends StatelessWidget {
  const _Header({required this.pending});

  final int pending;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 10, 4),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'TallyTaps',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
                letterSpacing: -0.3,
              ),
            ),
          ),
          // Everything already sent, bills included, is one tap away.
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: pending > 0
                    ? AppColors.card.withValues(alpha: 0.12)
                    : AppColors.line.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                pending > 0 ? '$pending waiting to sync' : 'Sent',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: pending > 0 ? AppColors.card : AppColors.inkSoft,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Connection',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SyncSetupScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    );
  }
}
