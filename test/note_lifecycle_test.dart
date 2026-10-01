import 'package:flutter_test/flutter_test.dart';
import 'package:tally/data/action_repository.dart';
import 'package:tally/models/tally_action.dart';
import 'package:tally/state/tally_store.dart';

/// The phone's own storage, kept in memory so the lifecycle can be followed
/// without a database.
class _MemoryRepo extends ActionRepository {
  final List<TallyAction> rows = [];
  int _nextId = 1;

  @override
  Future<int> insert(TallyAction action) async {
    action.id = _nextId++;
    rows.add(action);
    return action.id!;
  }

  @override
  Future<int> update(TallyAction action) async {
    final index = rows.indexWhere((row) => row.id == action.id);
    if (index < 0) return 0;
    rows[index] = action;
    return 1;
  }

  @override
  Future<int> delete(int id) async {
    rows.removeWhere((row) => row.id == id);
    return 1;
  }

  @override
  Future<List<TallyAction>> getAll() async => rows;
}

void main() {
  test('a note is kept from the first word, and stays the writer\'s own', () async {
    final repo = _MemoryRepo();
    final store = TallyStore(repo);

    final draft = await store.startDraft();
    expect(draft.isDraft, isTrue);
    expect(store.drafts.length, 1);
    // Nothing unfinished is ever offered to the shop.
    expect(store.unsynced, isEmpty);

    await store.saveDraft(draft.copyWith(note: 'Lorry broke down at Dambulla'));
    expect(store.actions.single.note, 'Lorry broke down at Dambulla');
    expect(store.actions.single.isDraft, isTrue);
    expect(store.unsynced, isEmpty);
  });

  test('an empty note is dropped rather than left cluttering the list', () async {
    final store = TallyStore(_MemoryRepo());
    final draft = await store.startDraft();

    await store.saveDraft(draft);

    expect(store.actions, isEmpty);
    expect(store.drafts, isEmpty);
  });

  test('finishing a note queues it, and files it by what it carries', () async {
    final store = TallyStore(_MemoryRepo());

    final cashDraft = await store.startDraft();
    await store.finalizeNote(
      cashDraft.copyWith(note: 'Paid the lorry', amount: 4000, moneyMethod: 'cash'),
    );

    final goodsDraft = await store.startDraft();
    await store.finalizeNote(goodsDraft.copyWith(note: 'Took rice', item: 'Rice', qty: 3.0));

    final plainDraft = await store.startDraft();
    await store.finalizeNote(plainDraft.copyWith(note: 'Shutter is jammed'));

    final kinds = store.finalNotes.map((note) => note.type).toSet();
    expect(kinds, {ActionType.cash, ActionType.stock, ActionType.note});
    expect(store.drafts, isEmpty);
    // All three are finished, so all three are waiting to go.
    expect(store.unsynced.length, 3);
  });

  test('many notes can be unfinished at once', () async {
    final store = TallyStore(_MemoryRepo());

    for (final text in ['Check the scale', 'Call Kamal', 'Order bags']) {
      final draft = await store.startDraft();
      await store.saveDraft(draft.copyWith(note: text));
    }

    expect(store.drafts.length, 3);
    expect(store.actions.length, 3);
  });

  test('a note asking to be done waits until the shop sees to it', () async {
    final store = TallyStore(_MemoryRepo());
    final draft = await store.startDraft();
    final saved = await store.finalizeNote(
      draft.copyWith(note: 'Bring the empty crates back', needsDoing: true),
    );

    expect(store.waitingNotes.length, 1);
    expect(saved!.isWaiting, isTrue);

    final seen = saved.seenAtShop(DateTime(2026, 10, 1, 9), 'Counter 1');
    expect(seen.isWaiting, isFalse);
    expect(seen.isDone, isTrue);
    expect(seen.resolvedBy, 'Counter 1');
  });

  test('a thrown-away note leaves the notebook', () async {
    final store = TallyStore(_MemoryRepo());
    final draft = await store.startDraft();
    await store.saveDraft(draft.copyWith(note: 'Wrong one'));

    await store.deleteNote(store.actions.single);

    expect(store.actions, isEmpty);
  });
}
