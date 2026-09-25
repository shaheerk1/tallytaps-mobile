import 'package:flutter_test/flutter_test.dart';
import 'package:tally/data/entry_draft_repository.dart';
import 'package:tally/models/tally_action.dart';

void main() {
  test('a half-entered record survives being written down and read back', () {
    final draft = EntryDraft(
      type: ActionType.stock,
      direction: ActionDirection.outgoing,
      note: 'Half done',
      item: 'Rice',
      qtyInput: '12.5',
      priceInput: '300',
      stockPriceMode: true,
      unit: 'Kg',
      voicePath: '/tmp/voice.m4a',
      imagePaths: const ['/tmp/one.jpg', '/tmp/two.jpg'],
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );

    final restored = EntryDraft.fromMap(draft.toMap());

    expect(restored.type, ActionType.stock);
    expect(restored.direction, ActionDirection.outgoing);
    expect(restored.note, 'Half done');
    expect(restored.item, 'Rice');
    expect(restored.qtyInput, '12.5');
    expect(restored.priceInput, '300');
    expect(restored.stockPriceMode, isTrue);
    expect(restored.unit, 'Kg');
    expect(restored.voicePath, '/tmp/voice.m4a');
    expect(restored.imagePaths, ['/tmp/one.jpg', '/tmp/two.jpg']);
    expect(restored.isEmpty, isFalse);
  });

  test('an untouched screen leaves nothing behind', () {
    final draft = EntryDraft(
      type: ActionType.cash,
      direction: ActionDirection.incoming,
      updatedAt: DateTime.now(),
    );
    expect(draft.isEmpty, isTrue);
    expect(EntryDraft.fromMap(draft.toMap()).isEmpty, isTrue);
  });

  test('a note on its own is worth keeping', () {
    final draft = EntryDraft(
      type: ActionType.note,
      direction: ActionDirection.incoming,
      note: 'Call the supplier',
      updatedAt: DateTime.now(),
    );
    expect(draft.isEmpty, isFalse);
  });

  test('unreadable photo paths do not break a draft', () {
    final broken = EntryDraft.fromMap({
      'type': 'card',
      'direction': 'incoming',
      'input': '250',
      'image_paths': 'not json',
      'updated_at': 0,
    });
    expect(broken.type, ActionType.card);
    expect(broken.input, '250');
    expect(broken.imagePaths, isEmpty);
  });
}
