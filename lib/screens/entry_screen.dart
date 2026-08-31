import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/category_spec.dart';
import '../models/tally_action.dart';
import '../services/media_service.dart';
import '../state/tally_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/item_picker.dart';
import '../widgets/number_pad.dart';

/// Full-screen quick-entry flow. Opened by tapping a big category button,
/// this screen is the "always at the bottom, one hand, big everything" part
/// of the app: direction toggle, live amount, number pad and a huge Record
/// button, all within thumb reach.
class EntryScreen extends StatefulWidget {
  const EntryScreen({super.key, required this.type});

  final ActionType type;

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  late final CategorySpec _spec = CategorySpec.of(widget.type);
  late final bool _hasAmount = widget.type != ActionType.note;

  ActionDirection _direction = ActionDirection.incoming;

  String _input = '';
  final TextEditingController _noteController = TextEditingController();

  // Stock-only state
  String? _selectedItem;
  String _qtyInput = '';
  String _priceInput = '';
  _StockInputMode _stockMode = _StockInputMode.qty;
  String _unit = 'Kg';

  final VoiceRecorder _voiceRecorder = VoiceRecorder();
  String? _voicePath;
  bool _isRecording = false;
  Timer? _recordingTicker;

  final List<String> _images = [];
  bool _saving = false;

  double get _amount => Money.parseInput(_input);
  double get _stockQty => Money.parseInput(_qtyInput);
  double get _stockPrice => Money.parseInput(_priceInput);

  @override
  void dispose() {
    _recordingTicker?.cancel();
    _voiceRecorder.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _appendDigit(String current, String key) {
    if (key == '.') {
      if (current.contains('.')) return current;
      if (current.length >= 13) return current;
      return current.isEmpty ? '0.' : '$current.';
    }
    final dotIndex = current.indexOf('.');
    if (dotIndex != -1 && current.length - dotIndex - 1 >= 2) return current;
    if (current.length >= 13) return current;
    return current + key;
  }

  void _onDigit(String key) {
    setState(() {
      if (widget.type == ActionType.stock) {
        if (_stockMode == _StockInputMode.qty) {
          _qtyInput = _appendDigit(_qtyInput, key);
        } else {
          _priceInput = _appendDigit(_priceInput, key);
        }
      } else {
        _input = _appendDigit(_input, key);
      }
    });
  }

  void _onBackspace() {
    setState(() {
      if (widget.type == ActionType.stock) {
        if (_stockMode == _StockInputMode.qty) {
          if (_qtyInput.isEmpty) return;
          _qtyInput = _qtyInput.substring(0, _qtyInput.length - 1);
        } else {
          if (_priceInput.isEmpty) return;
          _priceInput = _priceInput.substring(0, _priceInput.length - 1);
        }
      } else {
        if (_input.isEmpty) return;
        _input = _input.substring(0, _input.length - 1);
      }
    });
  }

  void _clearActiveInput() {
    setState(() {
      if (widget.type == ActionType.stock) {
        if (_stockMode == _StockInputMode.qty) {
          _qtyInput = '';
        } else {
          _priceInput = '';
        }
      } else {
        _input = '';
      }
    });
  }

  Future<void> _pickItem() async {
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ItemPickerSheet(),
    );
    if (name != null && mounted) {
      setState(() => _selectedItem = name);
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _voiceRecorder.stop();
      _recordingTicker?.cancel();
      if (mounted) {
        setState(() {
          _isRecording = false;
          if (path != null) _voicePath = path;
        });
      }
      return;
    }
    final ok = await _voiceRecorder.start();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission is needed for voice notes.'),
          ),
        );
      }
      return;
    }
    setState(() => _isRecording = true);
    _recordingTicker = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _addCameraPhoto() async {
    final path = await MediaService.capturePhoto();
    if (path != null && mounted) setState(() => _images.add(path));
  }

  Future<void> _addGalleryImage() async {
    final path = await MediaService.pickGallery();
    if (path != null && mounted) setState(() => _images.add(path));
  }

  void _removeImage(String path) =>
      setState(() => _images.removeWhere((p) => p == path));

  Future<void> _record() async {
    if (_saving) return;
    if (widget.type == ActionType.stock) {
      if (_selectedItem == null || _selectedItem!.trim().isEmpty) {
        tapHaptic();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Select an item first.')));
        return;
      }
      if (_stockQty <= 0) {
        tapHaptic();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter the kilo / qty first.')),
        );
        return;
      }
    } else if (_hasAmount) {
      if (_amount <= 0) {
        tapHaptic();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Enter an amount first.')));
        return;
      }
    } else if (_noteController.text.trim().isEmpty &&
        _voicePath == null &&
        _images.isEmpty) {
      tapHaptic();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Type or attach something first.')),
      );
      return;
    }
    setState(() => _saving = true);
    final store = context.read<TallyStore>();
    if (widget.type == ActionType.stock) {
      await store.record(
        type: widget.type,
        direction: _direction,
        amount: _stockPrice,
        item: _selectedItem!.trim(),
        qty: _stockQty,
        unit: _unit,
        note: _noteController.text,
        voicePath: _voicePath,
        imagePaths: _images,
      );
    } else {
      await store.record(
        type: widget.type,
        direction: _direction,
        amount: _amount,
        note: _noteController.text,
        voicePath: _voicePath,
        imagePaths: _images,
      );
    }
    if (!mounted) return;
    successHaptic();
    // Straight back home so the next action can be recorded right away.
    // Home shows the success confirmation in its hero area.
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final valueColor = _direction == ActionDirection.incoming
        ? AppColors.positive
        : AppColors.negative;

    final Widget body = switch (widget.type) {
      ActionType.stock => _buildStockLayout(valueColor),
      ActionType.note => _buildNoteLayout(),
      _ => _buildMoneyLayout(valueColor),
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: body),
    );
  }

  Widget _buildMoneyLayout(Color valueColor) {
    return Column(
      children: [
        _Header(spec: _spec, onBack: () => Navigator.of(context).maybePop()),
        _DirectionToggle(
          spec: _spec,
          value: _direction,
          onChanged: (d) => setState(() => _direction = d),
        ),
        Flexible(
          fit: FlexFit.loose,
          child: _AmountDisplay(
            text: Money.formatInput(_input),
            color: _amount > 0 ? valueColor : AppColors.inkSoft,
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              _noteField(hint: 'Add a short note (optional)'),
              const SizedBox(height: 12),
              _attachments(),
            ],
          ),
        ),
        _padArea(),
        _recordButton(),
      ],
    );
  }

  Widget _buildStockLayout(Color valueColor) {
    final hasValue = _stockMode == _StockInputMode.qty
        ? _stockQty > 0
        : _stockPrice > 0;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                _Header(
                  spec: _spec,
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                _DirectionToggle(
                  spec: _spec,
                  value: _direction,
                  onChanged: (d) => setState(() => _direction = d),
                ),
                _ItemSelector(selected: _selectedItem, onTap: _pickItem),
                _StockModeToggle(
                  mode: _stockMode,
                  unit: _unit,
                  onModeChanged: (m) => setState(() => _stockMode = m),
                  onUnitChanged: (u) => setState(() => _unit = u),
                ),
                const SizedBox(height: 4),
                _AmountDisplay(
                  text: _stockDisplayText,
                  color: hasValue ? valueColor : AppColors.inkSoft,
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _noteField(hint: 'Add a short note (optional)'),
                ),
                const SizedBox(height: 12),
                _attachments(),
              ],
            ),
          ),
        ),
        _padArea(),
        _recordButton(),
      ],
    );
  }

  String get _stockDisplayText => _stockMode == _StockInputMode.qty
      ? Money.formatNumberInput(_qtyInput)
      : Money.formatInput(_priceInput);

  Widget _buildNoteLayout() {
    return Column(
      children: [
        _Header(spec: _spec, onBack: () => Navigator.of(context).maybePop()),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 10, 24, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'What happened?',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              TextField(
                controller: _noteController,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
                decoration: InputDecoration(
                  hintText:
                      'Type what happened…\n'
                      'e.g. "Paid the delivery guy for 3 boxes"',
                  hintStyle: const TextStyle(
                    color: AppColors.inkFaint,
                    height: 1.4,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.all(18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _attachments(),
            ],
          ),
        ),
        _recordButton(),
      ],
    );
  }

  Widget _noteField({required String hint}) {
    return TextField(
      controller: _noteController,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.inkFaint),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  /// The number pad is hidden while the keyboard is open so the screen never
  /// overflows on small devices. It comes back the moment the keyboard closes.
  Widget _padArea() {
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    if (keyboardOpen) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
      child: NumberPad(
        onDigit: _onDigit,
        onBackspace: _onBackspace,
        onLongBackspace: _clearActiveInput,
        height: 56,
      ),
    );
  }

  Widget _attachments() {
    return _Attachments(
      isRecording: _isRecording,
      recordingElapsed: _voiceRecorder.elapsed,
      voicePath: _voicePath,
      images: _images,
      onToggleRecording: _toggleRecording,
      onCamera: _addCameraPhoto,
      onGallery: _addGalleryImage,
      onRemoveVoice: () => setState(() => _voicePath = null),
      onRemoveImage: _removeImage,
      onPlayVoice: () {
        if (_voicePath != null) {
          VoicePlayer.play(_voicePath!);
        }
      },
    );
  }

  Widget _recordButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: _RecordButton(loading: _saving, onTap: _record),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------
class _Header extends StatelessWidget {
  const _Header({required this.spec, required this.onBack});

  final CategorySpec spec;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 20, 8),
      child: Row(
        children: [
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            elevation: 1,
            child: InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(16),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 20,
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: spec.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(spec.icon, color: spec.color, size: 22),
                const SizedBox(width: 8),
                Text(
                  spec.label,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: spec.color,
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
// Direction toggle (Received / Paid  ·  Incoming / Outgoing)
// ---------------------------------------------------------------------------
class _DirectionToggle extends StatelessWidget {
  const _DirectionToggle({
    required this.spec,
    required this.value,
    required this.onChanged,
  });

  final CategorySpec spec;
  final ActionDirection value;
  final ValueChanged<ActionDirection> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: cardShadow,
        ),
        child: Row(
          children: [
            _Segment(
              label: spec.type.inLabel,
              icon: Icons.south_west_rounded,
              selected: value == ActionDirection.incoming,
              color: AppColors.positive,
              onTap: () => onChanged(ActionDirection.incoming),
            ),
            _Segment(
              label: spec.type.outLabel,
              icon: Icons.north_east_rounded,
              selected: value == ActionDirection.outgoing,
              color: AppColors.negative,
              onTap: () => onChanged(ActionDirection.outgoing),
            ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          tapHaptic();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 54,
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(colors: [color, color.withValues(alpha: 0.82)])
                : null,
            color: selected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? Colors.white : AppColors.inkSoft,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : AppColors.inkSoft,
                    ),
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

enum _StockInputMode { qty, price }

// ---------------------------------------------------------------------------
// Stock: searchable item selector
// ---------------------------------------------------------------------------
class _ItemSelector extends StatelessWidget {
  const _ItemSelector({required this.selected, required this.onTap});

  final String? selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasItem = selected != null && selected!.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.stockSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.search_rounded,
                    color: AppColors.stock,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    hasItem ? selected! : 'Select item…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: hasItem ? AppColors.ink : AppColors.inkFaint,
                    ),
                  ),
                ),
                const Icon(
                  Icons.expand_more_rounded,
                  color: AppColors.inkFaint,
                  size: 26,
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
// Stock: Kilo/Qty | Price mode + Kg/Pcs unit
// ---------------------------------------------------------------------------
class _StockModeToggle extends StatelessWidget {
  const _StockModeToggle({
    required this.mode,
    required this.unit,
    required this.onModeChanged,
    required this.onUnitChanged,
  });

  final _StockInputMode mode;
  final String unit;
  final ValueChanged<_StockInputMode> onModeChanged;
  final ValueChanged<String> onUnitChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: cardShadow,
            ),
            child: Row(
              children: [
                _ModeSegment(
                  label: 'Kilo / Qty',
                  icon: Icons.straighten_rounded,
                  selected: mode == _StockInputMode.qty,
                  onTap: () => onModeChanged(_StockInputMode.qty),
                ),
                _ModeSegment(
                  label: 'Price',
                  icon: Icons.payments_rounded,
                  selected: mode == _StockInputMode.price,
                  onTap: () => onModeChanged(_StockInputMode.price),
                ),
              ],
            ),
          ),
          if (mode == _StockInputMode.qty) ...[
            const SizedBox(height: 8),
            _UnitChips(unit: unit, onChanged: onUnitChanged),
          ],
        ],
      ),
    );
  }
}

class _ModeSegment extends StatelessWidget {
  const _ModeSegment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          tapHaptic();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 48,
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    colors: [
                      AppColors.stock,
                      AppColors.stock.withValues(alpha: 0.82),
                    ],
                  )
                : null,
            color: selected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? Colors.white : AppColors.inkSoft,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : AppColors.inkSoft,
                    ),
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

class _UnitChips extends StatelessWidget {
  const _UnitChips({required this.unit, required this.onChanged});

  final String unit;
  final ValueChanged<String> onChanged;

  static const _options = ['Kg', 'Pcs'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        for (final option in _options) ...[
          GestureDetector(
            onTap: () {
              tapHaptic();
              onChanged(option);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: unit == option ? AppColors.stock : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: unit == option ? AppColors.stock : AppColors.line,
                ),
              ),
              child: Text(
                option,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: unit == option ? Colors.white : AppColors.inkSoft,
                ),
              ),
            ),
          ),
          if (option != _options.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Amount display
// ---------------------------------------------------------------------------
class _AmountDisplay extends StatelessWidget {
  const _AmountDisplay({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 46,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1.05,
              letterSpacing: -0.5,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Attachments: voice note, camera, gallery + added chips
// ---------------------------------------------------------------------------
class _Attachments extends StatelessWidget {
  const _Attachments({
    required this.isRecording,
    required this.recordingElapsed,
    required this.voicePath,
    required this.images,
    required this.onToggleRecording,
    required this.onCamera,
    required this.onGallery,
    required this.onRemoveVoice,
    required this.onRemoveImage,
    required this.onPlayVoice,
  });

  final bool isRecording;
  final Duration recordingElapsed;
  final String? voicePath;
  final List<String> images;
  final VoidCallback onToggleRecording;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onRemoveVoice;
  final ValueChanged<String> onRemoveImage;
  final VoidCallback onPlayVoice;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isRecording) _recordingBar(recordingElapsed, onToggleRecording),
        if (voicePath != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _voiceChip(onPlayVoice, onRemoveVoice),
          ),
        if (images.isNotEmpty)
          SizedBox(
            height: 74,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemBuilder: (context, i) =>
                  _imageThumb(images[i], () => onRemoveImage(images[i])),
            ),
          ),
        if (!isRecording)
          Row(
            children: [
              _attachButton(
                icon: Icons.mic_rounded,
                color: AppColors.negative,
                label: 'Voice',
                onTap: onToggleRecording,
              ),
              const SizedBox(width: 10),
              _attachButton(
                icon: Icons.camera_alt_rounded,
                color: AppColors.brand,
                label: 'Photo',
                onTap: onCamera,
              ),
              const SizedBox(width: 10),
              _attachButton(
                icon: Icons.photo_library_rounded,
                color: AppColors.card,
                label: 'Gallery',
                onTap: onGallery,
              ),
            ],
          ),
      ],
    );
  }

  Widget _recordingBar(Duration elapsed, VoidCallback onStop) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.negative.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const _PulsingDot(),
          const SizedBox(width: 12),
          Text(
            _fmtElapsed(elapsed),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.negative,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Recording voice note… tap to stop',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.negative,
              ),
            ),
          ),
          IconButton(
            onPressed: onStop,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.negative,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.stop_rounded),
          ),
        ],
      ),
    );
  }

  Widget _voiceChip(VoidCallback onPlay, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: cardShadow,
      ),
      child: Row(
        children: [
          const Icon(Icons.graphic_eq_rounded, color: AppColors.negative),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Voice note',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          _chipAction(Icons.play_circle_fill_rounded, AppColors.brand, onPlay),
          _chipAction(Icons.close_rounded, AppColors.inkFaint, onRemove),
        ],
      ),
    );
  }

  Widget _imageThumb(String path, VoidCallback onRemove) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
            image: DecorationImage(
              image: FileImage(File(path)),
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          top: -8,
          right: -8,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: AppColors.ink,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _chipAction(IconData icon, Color color, VoidCallback onTap) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: color, size: 26),
    );
  }

  Widget _attachButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          tapHaptic();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: cardShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtElapsed(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 1.0).animate(_c),
      child: Container(
        width: 14,
        height: 14,
        decoration: const BoxDecoration(
          color: AppColors.negative,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Record button
// ---------------------------------------------------------------------------
class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brand,
      borderRadius: BorderRadius.circular(22),
      elevation: 4,
      shadowColor: AppColors.brand.withValues(alpha: 0.4),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          height: 62,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              colors: [AppColors.brand, AppColors.brandDark],
            ),
          ),
          child: loading
              ? const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Record',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.3,
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
// Stock: searchable item selector
// ---------------------------------------------------------------------------
