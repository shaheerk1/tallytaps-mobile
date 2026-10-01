import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/tally_action.dart';
import '../services/media_service.dart';
import '../state/tally_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/goods_picker.dart';
import '../widgets/note_detail_sheets.dart';

/// The field notebook: write what happened, attach what proves it, and mark
/// only what is worth marking.
///
/// One page, no categories to choose first. Money, goods, who it is about and
/// the writer's own tags are added when they matter and left alone when they do
/// not, so a note is never harder to write than it needs to be.
class NoteScreen extends StatefulWidget {
  const NoteScreen({super.key, this.existing});

  /// An unfinished note being picked up again. Null starts a new one.
  final TallyAction? existing;

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  final TextEditingController _note = TextEditingController();
  final FocusNode _noteFocus = FocusNode();
  final VoiceRecorder _voiceRecorder = VoiceRecorder();

  Timer? _saveTimer;
  Timer? _recordingTicker;
  bool _isRecording = false;
  bool _finishing = false;
  bool _finished = false;

  /// The note being written. It exists in the list from the first word.
  TallyAction? _draft;

  String? _voicePath;
  final List<String> _images = [];

  // What the note carries, all of it optional.
  double? _amount;
  String _moneyMethod = 'cash';
  ActionDirection _moneyDirection = ActionDirection.incoming;
  GoodsSelection? _goods;
  String? _who;
  final List<String> _tags = [];
  bool _needsDoing = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _draft = existing;
      _note.text = existing.note ?? '';
      _amount = existing.amount > 0 ? existing.amount : null;
      _moneyMethod = existing.moneyMethod ?? 'cash';
      _moneyDirection = existing.direction;
      _who = existing.who;
      _tags.addAll(existing.tags);
      _needsDoing = existing.needsDoing;
      _voicePath = existing.voicePath;
      _images.addAll(existing.imagePaths.where((path) => File(path).existsSync()));
      if (existing.item != null) {
        _goods = GoodsSelection(
          name: existing.item!,
          productKey: existing.productKey,
          handlingQty: existing.qty,
          handlingUom: existing.unit,
          baseQty: existing.baseQty,
          baseUom: existing.baseUnit,
        );
      }
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _noteFocus.requestFocus());
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _recordingTicker?.cancel();
    _voiceRecorder.dispose();
    _note.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  @override
  void deactivate() {
    // Walking away keeps the note, exactly as a notebook would.
    _saveTimer?.cancel();
    if (!_finished) unawaited(_save());
    super.deactivate();
  }

  /// The note as it stands, ready to be written down.
  TallyAction _compose(TallyAction base) => base.copyWith(
    note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    amount: _amount ?? 0,
    direction: _moneyDirection,
    moneyMethod: _amount == null ? null : _moneyMethod,
    item: _goods?.name,
    qty: _goods?.handlingQty,
    unit: _goods?.handlingUom,
    productKey: _goods?.productKey,
    baseQty: _goods?.baseQty,
    baseUnit: _goods?.baseUom,
    who: (_who == null || _who!.trim().isEmpty) ? null : _who!.trim(),
    tags: List<String>.from(_tags),
    needsDoing: _needsDoing,
    voicePath: _voicePath,
    imagePaths: List<String>.from(_images),
  );

  bool get _hasSomething =>
      _note.text.trim().isNotEmpty ||
      _amount != null ||
      _goods != null ||
      _voicePath != null ||
      _images.isNotEmpty ||
      _who != null ||
      _tags.isNotEmpty;

  /// Writes the note down where it is. Called as the person types, and again
  /// on the way out.
  Future<void> _save() async {
    if (_finished || !mounted) return;
    final store = context.read<TallyStore>();
    if (!_hasSomething) {
      final draft = _draft;
      if (draft != null) {
        _draft = null;
        await store.deleteNote(draft);
      }
      return;
    }
    var draft = _draft;
    draft ??= await store.startDraft();
    _draft = draft;
    final saved = await store.saveDraft(_compose(draft));
    if (saved != null) _draft = saved;
  }

  void _queueSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () => unawaited(_save()));
  }

  /// Finishing hands the note to the shop. It cannot be changed afterwards,
  /// because there is no way to change one that has already gone.
  Future<void> _finish() async {
    if (_finishing) return;
    if (!_hasSomething) {
      tapHaptic();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write something first, or attach a photo or voice note.')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send this note to the shop?'),
        content: const Text(
          'It goes into the queue and cannot be changed afterwards. '
          'Leave it unfinished if you still want to add to it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep writing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Send it'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _finishing = true);
    final store = context.read<TallyStore>();
    await _save();
    final draft = _draft;
    if (draft == null) {
      setState(() => _finishing = false);
      return;
    }
    await store.finalizeNote(_compose(draft));
    _finished = true;
    if (!mounted) return;
    successHaptic();
    Navigator.of(context).pop();
  }

  Future<void> _deleteNote() async {
    final draft = _draft;
    if (draft == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Throw this note away?'),
        content: const Text('It has not been sent anywhere, so it will be gone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Throw away'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _finished = true;
    await context.read<TallyStore>().deleteNote(draft);
    if (mounted) Navigator.of(context).pop();
  }

  // ── Writing ─────────────────────────────────────────────────

  /// `@name` names who the note is about and `#word` files it. The words stay
  /// in the note, written as they were; the marks are only a shortcut, and can
  /// be taken off again like any other.
  void _onNoteChanged(String value) {
    var changed = false;
    for (final word in value.split(RegExp(r'[\s,.;]+'))) {
      if (word.length < 2) continue;
      if (word.startsWith('@') && _who == null) {
        _who = word.substring(1);
        changed = true;
      } else if (word.startsWith('#')) {
        final tag = word.substring(1).toLowerCase();
        if (!_tags.contains(tag) && _tags.length < 12) {
          _tags.add(tag);
          changed = true;
        }
      }
    }
    if (changed) setState(() {});
    _queueSave();
  }

  Future<void> _addMoney() async {
    final money = await showMoneySheet(
      context,
      amount: _amount,
      method: _moneyMethod,
      direction: _moneyDirection,
    );
    if (money == null || !mounted) return;
    setState(() {
      _amount = money.cleared ? null : money.amount;
      _moneyMethod = money.method;
      _moneyDirection = money.direction;
    });
    _queueSave();
  }

  Future<void> _addGoods() async {
    final goods = await showGoodsPicker(context, current: _goods);
    if (goods == null || !mounted) return;
    setState(() => _goods = goods.cleared ? null : goods);
    _queueSave();
  }

  Future<void> _addWho() async {
    final store = context.read<TallyStore>();
    final name = await showWhoSheet(context, current: _who, remembered: store.rememberedWho);
    if (!mounted) return;
    setState(() => _who = (name == null || name.isEmpty) ? null : name);
    _queueSave();
  }

  Future<void> _addTag() async {
    final store = context.read<TallyStore>();
    final tag = await showTagSheet(context, remembered: store.rememberedTags, chosen: _tags);
    if (tag == null || !mounted) return;
    setState(() {
      if (_tags.contains(tag)) {
        _tags.remove(tag);
      } else if (_tags.length < 12) {
        _tags.add(tag);
      }
    });
    _queueSave();
  }

  // ── Attachments ─────────────────────────────────────────────

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _voiceRecorder.stop();
      _recordingTicker?.cancel();
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        if (path != null) _voicePath = path;
      });
      _queueSave();
      return;
    }
    final started = await _voiceRecorder.start();
    if (!started) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is needed for voice notes.')),
        );
      }
      return;
    }
    setState(() => _isRecording = true);
    _recordingTicker = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _addPhoto({required bool fromCamera}) async {
    final path = fromCamera
        ? await MediaService.capturePhoto()
        : await MediaService.pickGallery();
    if (path == null || !mounted) return;
    setState(() => _images.add(path));
    _queueSave();
  }

  // ── The page ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(
          widget.existing == null ? 'New note' : 'Note',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Throw away',
            onPressed: _deleteNote,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10, left: 2),
            child: FilledButton.icon(
              onPressed: _finishing ? null : _finish,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.send_rounded, size: 17),
              label: Text(
                _finishing ? 'Sending…' : 'Done',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                children: [
                  _noteField(),
                  const SizedBox(height: 12),
                  _detailChips(),
                  const SizedBox(height: 12),
                  _attachments(),
                ],
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _noteField() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: TextField(
        controller: _note,
        focusNode: _noteFocus,
        onChanged: _onNoteChanged,
        minLines: 6,
        maxLines: 14,
        textCapitalization: TextCapitalization.sentences,
        keyboardType: TextInputType.multiline,
        style: const TextStyle(fontSize: 17, height: 1.45, fontWeight: FontWeight.w600),
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: 'What happened?\n\nType @ before a name, # before a word you want to find it by.',
          hintStyle: TextStyle(color: AppColors.inkFaint, height: 1.45, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _detailChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _DetailChip(
          icon: Icons.payments_outlined,
          label: _amount == null
              ? 'Money'
              : '${_moneyDirection == ActionDirection.incoming ? 'In' : 'Out'} '
                    '${Money.format(_amount!)}'
                    '${_moneyMethod == 'card' ? ' · card' : ''}',
          filled: _amount != null,
          tone: AppColors.cash,
          onTap: _addMoney,
        ),
        _DetailChip(
          icon: Icons.inventory_2_outlined,
          label: _goods == null ? 'Goods' : _goods!.summary,
          filled: _goods != null,
          tone: AppColors.stock,
          onTap: _addGoods,
        ),
        _DetailChip(
          icon: Icons.person_outline_rounded,
          label: _who ?? 'Who',
          filled: _who != null,
          tone: AppColors.card,
          onTap: _addWho,
        ),
        for (final tag in _tags)
          _DetailChip(
            icon: Icons.sell_outlined,
            label: '#$tag',
            filled: true,
            tone: AppColors.note,
            onTap: () {
              setState(() => _tags.remove(tag));
              _queueSave();
            },
          ),
        _DetailChip(
          icon: Icons.add_rounded,
          label: 'Tag',
          filled: false,
          tone: AppColors.note,
          onTap: _addTag,
        ),
      ],
    );
  }

  Widget _attachments() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _AttachButton(
              icon: Icons.photo_camera_outlined,
              label: 'Camera',
              onTap: () => _addPhoto(fromCamera: true),
            ),
            const SizedBox(width: 8),
            _AttachButton(
              icon: Icons.image_outlined,
              label: 'Gallery',
              onTap: () => _addPhoto(fromCamera: false),
            ),
            const SizedBox(width: 8),
            _AttachButton(
              icon: _isRecording ? Icons.stop_rounded : Icons.mic_none_rounded,
              label: _isRecording ? 'Stop' : (_voicePath == null ? 'Voice' : 'Re-record'),
              active: _isRecording,
              onTap: _toggleRecording,
            ),
          ],
        ),
        if (_voicePath != null && !_isRecording)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                const Icon(Icons.graphic_eq_rounded, size: 18, color: AppColors.note),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Voice note attached',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() => _voicePath = null);
                    _queueSave();
                  },
                  child: const Text('Remove'),
                ),
              ],
            ),
          ),
        if (_images.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final path in _images)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(path),
                          width: 84,
                          height: 84,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 84,
                            height: 84,
                            color: AppColors.line,
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 2,
                        top: 2,
                        child: InkWell(
                          onTap: () {
                            setState(() => _images.remove(path));
                            _queueSave();
                          },
                          child: const CircleAvatar(
                            radius: 11,
                            backgroundColor: Colors.black54,
                            child: Icon(Icons.close_rounded, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _footer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _needsDoing,
              onChanged: (value) {
                tapHaptic();
                setState(() => _needsDoing = value);
                _queueSave();
              },
              title: const Text(
                'Somebody has to do something',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              subtitle: const Text(
                'Stays at the top until the shop ticks it off',
                style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.cloud_off_rounded, size: 15, color: AppColors.inkFaint),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _hasSomething
                        ? 'Kept on this phone. Press Done when it is ready for the shop.'
                        : 'Start writing; it saves itself.',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({
    required this.icon,
    required this.label,
    required this.filled,
    required this.tone,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool filled;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () {
        tapHaptic();
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: filled ? tone.withValues(alpha: 0.12) : AppColors.surface,
          border: Border.all(color: filled ? tone : AppColors.line, width: filled ? 1.3 : 1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: filled ? tone : AppColors.inkSoft),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: filled ? tone : AppColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachButton extends StatelessWidget {
  const _AttachButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          tapHaptic();
          onTap();
        },
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: active ? AppColors.negative.withValues(alpha: 0.1) : AppColors.surface,
            border: Border.all(color: active ? AppColors.negative : AppColors.line),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: active ? AppColors.negative : AppColors.inkSoft),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: active ? AppColors.negative : AppColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
