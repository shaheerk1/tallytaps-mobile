import 'package:flutter/material.dart';

import '../models/tally_action.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Money named on a note: how much, which way it went, and whether it was cash
/// or card. Nothing here is required; a note about money is still just a note.
class MoneySelection {
  const MoneySelection({
    required this.amount,
    required this.method,
    required this.direction,
    this.cleared = false,
  });

  final double amount;
  final String method;
  final ActionDirection direction;
  final bool cleared;
}

Future<MoneySelection?> showMoneySheet(
  BuildContext context, {
  double? amount,
  required String method,
  required ActionDirection direction,
}) => showModalBottomSheet<MoneySelection>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _MoneySheet(amount: amount, method: method, direction: direction),
);

class _MoneySheet extends StatefulWidget {
  const _MoneySheet({this.amount, required this.method, required this.direction});

  final double? amount;
  final String method;
  final ActionDirection direction;

  @override
  State<_MoneySheet> createState() => _MoneySheetState();
}

class _MoneySheetState extends State<_MoneySheet> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.amount == null ? '' : widget.amount!.toStringAsFixed(2),
  );
  late String _method = widget.method;
  late ActionDirection _direction = widget.direction;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'How much money?',
      onClear: widget.amount == null
          ? null
          : () => Navigator.of(context).pop(
              MoneySelection(
                amount: 0,
                method: _method,
                direction: _direction,
                cleared: true,
              ),
            ),
      onSave: () {
        final value = Money.parseInput(_amount.text);
        if (value <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enter how much it was.')),
          );
          return;
        }
        Navigator.of(context).pop(
          MoneySelection(amount: value, method: _method, direction: _direction),
        );
      },
      children: [
        TextField(
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          decoration: InputDecoration(
            prefixText: '${Money.symbol}  ',
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 14),
        SegmentedButton<ActionDirection>(
          segments: const [
            ButtonSegment(
              value: ActionDirection.incoming,
              label: Text('Came in'),
              icon: Icon(Icons.south_west_rounded, size: 18),
            ),
            ButtonSegment(
              value: ActionDirection.outgoing,
              label: Text('Went out'),
              icon: Icon(Icons.north_east_rounded, size: 18),
            ),
          ],
          selected: {_direction},
          showSelectedIcon: false,
          onSelectionChanged: (value) {
            tapHaptic();
            setState(() => _direction = value.first);
          },
        ),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'cash', label: Text('Cash')),
            ButtonSegment(value: 'card', label: Text('Card or transfer')),
          ],
          selected: {_method},
          showSelectedIcon: false,
          onSelectionChanged: (value) {
            tapHaptic();
            setState(() => _method = value.first);
          },
        ),
      ],
    );
  }
}

/// Who the note is about. Typed freely and remembered, because the people a
/// field note is about are not always in the shop's books.
Future<String?> showWhoSheet(
  BuildContext context, {
  String? current,
  required List<String> remembered,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _WhoSheet(current: current, remembered: remembered),
);

class _WhoSheet extends StatefulWidget {
  const _WhoSheet({this.current, required this.remembered});

  final String? current;
  final List<String> remembered;

  @override
  State<_WhoSheet> createState() => _WhoSheetState();
}

class _WhoSheetState extends State<_WhoSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.current ?? '');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final term = _name.text.trim().toLowerCase();
    final suggestions = widget.remembered
        .where((name) => term.isEmpty || name.toLowerCase().contains(term))
        .take(12)
        .toList();
    return _SheetShell(
      title: 'Who is this about?',
      onClear: widget.current == null ? null : () => Navigator.of(context).pop(''),
      onSave: () => Navigator.of(context).pop(_name.text.trim()),
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'A supplier, a customer, a driver',
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'Used before',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.inkFaint),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in suggestions)
                ActionChip(
                  label: Text(name),
                  onPressed: () {
                    tapHaptic();
                    Navigator.of(context).pop(name);
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A word to find the note by later. Past words come first, because a notebook
/// is only searchable if the same thing is called the same name.
Future<String?> showTagSheet(
  BuildContext context, {
  required List<String> remembered,
  required List<String> chosen,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _TagSheet(remembered: remembered, chosen: chosen),
);

class _TagSheet extends StatefulWidget {
  const _TagSheet({required this.remembered, required this.chosen});

  final List<String> remembered;
  final List<String> chosen;

  @override
  State<_TagSheet> createState() => _TagSheetState();
}

class _TagSheetState extends State<_TagSheet> {
  final TextEditingController _tag = TextEditingController();

  @override
  void dispose() {
    _tag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final term = _tag.text.trim().toLowerCase();
    final suggestions = widget.remembered
        .where((tag) => term.isEmpty || tag.contains(term))
        .take(18)
        .toList();
    return _SheetShell(
      title: 'Tag this note',
      onSave: () {
        final tag = _tag.text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');
        if (tag.isEmpty) {
          Navigator.of(context).pop();
          return;
        }
        Navigator.of(context).pop(tag);
      },
      children: [
        TextField(
          controller: _tag,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          onSubmitted: (value) {
            final tag = value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');
            if (tag.isNotEmpty) Navigator.of(context).pop(tag);
          },
          decoration: InputDecoration(
            hintText: 'credit, lorry, repair',
            prefixText: '#',
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'Used before',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.inkFaint),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in suggestions)
                FilterChip(
                  label: Text('#$tag'),
                  selected: widget.chosen.contains(tag),
                  onSelected: (_) {
                    tapHaptic();
                    Navigator.of(context).pop(tag);
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The plain sheet these three share: a title, a body, and one way out.
class _SheetShell extends StatelessWidget {
  const _SheetShell({
    required this.title,
    required this.children,
    required this.onSave,
    this.onClear,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback onSave;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (onClear != null)
                    TextButton(onPressed: onClear, child: const Text('Take off')),
                ],
              ),
              const SizedBox(height: 10),
              ...children,
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: onSave,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
