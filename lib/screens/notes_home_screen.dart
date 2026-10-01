import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/category_spec.dart';
import '../models/tally_action.dart';
import '../state/tally_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'detail_sheet.dart';
import 'mobile_billing_screen.dart';
import 'note_screen.dart';

/// The notebook, and the first thing the app shows.
///
/// Every note is here the moment it is written, finished or not. Unfinished
/// ones can be opened and added to; finished ones are the record and cannot
/// change. The button in the corner starts a new one; holding it starts a bill.
class NotesHomeScreen extends StatefulWidget {
  const NotesHomeScreen({super.key});

  @override
  State<NotesHomeScreen> createState() => _NotesHomeScreenState();
}

class _NotesHomeScreenState extends State<NotesHomeScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  bool _onlyToDo = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openNote([TallyAction? existing]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NoteScreen(existing: existing)),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openFinished(TallyAction note) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DetailSheet(action: note),
    );
    if (mounted) setState(() {});
  }

  void _openBill() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MobileBillingScreen()),
    );
  }

  List<TallyAction> _visible(List<TallyAction> all) {
    final term = _query.trim().toLowerCase();
    return all.where((note) {
      if (_onlyToDo && !note.isWaiting) return false;
      if (term.isEmpty) return true;
      return (note.note?.toLowerCase().contains(term) ?? false) ||
          (note.who?.toLowerCase().contains(term) ?? false) ||
          (note.item?.toLowerCase().contains(term) ?? false) ||
          note.tags.any((tag) => tag.contains(term)) ||
          note.title.toLowerCase().contains(term);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TallyStore>();
    final notes = _visible(store.actions);
    final waiting = store.waitingNotes.length;
    final drafts = store.drafts.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: TextField(
              controller: _search,
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search your notes, a name, a tag',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 2, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (waiting > 0 || drafts > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
              child: Row(
                children: [
                  if (waiting > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text('To do ($waiting)'),
                        selected: _onlyToDo,
                        onSelected: (value) {
                          tapHaptic();
                          setState(() => _onlyToDo = value);
                        },
                      ),
                    ),
                  if (drafts > 0)
                    Text(
                      '$drafts unfinished',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.inkFaint,
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: notes.isEmpty
                ? _EmptyNotes(searching: _query.isNotEmpty || _onlyToDo)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 96),
                    itemCount: notes.length,
                    itemBuilder: (context, index) {
                      final note = notes[index];
                      final previous = index == 0 ? null : notes[index - 1];
                      final showDay = previous == null ||
                          !_sameDay(previous.createdAt, note.createdAt);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showDay)
                            Padding(
                              padding: EdgeInsets.only(top: index == 0 ? 4 : 14, bottom: 6),
                              child: Text(
                                _dayLabel(note.createdAt),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.inkFaint,
                                ),
                              ),
                            ),
                          _NoteCard(
                            note: note,
                            onTap: () =>
                                note.isDraft ? _openNote(note) : _openFinished(note),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
      // Writing is the main thing, so it is the big button. Billing sits just
      // above it, small but plainly there, and a long press still reaches it.
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'new-bill',
            onPressed: _openBill,
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.ink,
            elevation: 2,
            tooltip: 'New bill',
            child: const Icon(Icons.receipt_long_rounded, size: 20),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onLongPress: () {
              tapHaptic();
              _openBill();
            },
            child: FloatingActionButton.extended(
              heroTag: 'new-note',
              onPressed: () => _openNote(),
              backgroundColor: AppColors.brand,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Note', style: TextStyle(fontWeight: FontWeight.w800)),
              tooltip: 'New note · hold for a bill',
            ),
          ),
        ],
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _dayLabel(DateTime when) {
    final now = DateTime.now();
    if (_sameDay(now, when)) return 'Today';
    if (_sameDay(now.subtract(const Duration(days: 1)), when)) return 'Yesterday';
    return DateFormat('EEEE, d MMMM').format(when);
  }
}

/// One note in the list: what it says, what it carries, and where it stands.
class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.onTap});

  final TallyAction note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final spec = CategorySpec.of(note.type);
    final time = DateFormat('h:mm a').format(note.createdAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        elevation: note.isDraft ? 0 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            tapHaptic();
            onTap();
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: note.isDraft ? AppColors.line : Colors.transparent,
                style: note.isDraft ? BorderStyle.solid : BorderStyle.none,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        note.headline,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15.5,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    if (note.hasMoney) ...[
                      const SizedBox(width: 10),
                      Text(
                        '${note.direction == ActionDirection.incoming ? '+' : '−'} '
                        '${Money.format(note.amount)}',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: note.direction == ActionDirection.incoming
                              ? AppColors.positive
                              : AppColors.negative,
                        ),
                      ),
                    ],
                  ],
                ),
                if (note.body.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      note.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      time,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.inkFaint,
                      ),
                    ),
                    if (note.isDraft)
                      const _Mark(text: 'Unfinished', color: AppColors.inkFaint),
                    if (note.isWaiting) const _Mark(text: 'To do', color: AppColors.stock),
                    if (note.isDone)
                      const _Mark(text: 'Seen at the shop', color: AppColors.positive),
                    if (note.isFinal && !note.synced && !note.isDone)
                      const _Mark(text: 'Waiting to sync', color: AppColors.card),
                    if (note.hasGoods)
                      _Mark(text: note.item ?? 'goods', color: spec.color),
                    if (note.who != null) _Mark(text: note.who!, color: AppColors.card),
                    for (final tag in note.tags)
                      _Mark(text: '#$tag', color: AppColors.note),
                    if (note.imagePaths.isNotEmpty)
                      _Mark(
                        text: '${note.imagePaths.length} photo'
                            '${note.imagePaths.length == 1 ? '' : 's'}',
                        color: AppColors.inkFaint,
                      ),
                    if (note.voicePath != null)
                      const _Mark(text: 'voice', color: AppColors.inkFaint),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching ? Icons.search_off_rounded : Icons.edit_note_rounded,
              size: 54,
              color: AppColors.inkFaint,
            ),
            const SizedBox(height: 12),
            Text(
              searching ? 'Nothing matches that.' : 'Your notebook is empty.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              searching
                  ? 'Try another word, or clear the search.'
                  : 'Tap the button to write the first one. '
                        'It saves itself as you type, so nothing is lost.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
