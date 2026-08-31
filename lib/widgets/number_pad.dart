import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Full on-screen number pad with big keys, built for one-thumb entry.
class NumberPad extends StatelessWidget {
  const NumberPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    required this.onLongBackspace,
    this.height = 62,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onLongBackspace;
  final double height;

  static const List<String> _rows = [
    '7', '8', '9',
    '4', '5', '6',
    '1', '2', '3',
    '.', '0', '⌫',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < 4; r++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                for (var c = 0; c < 3; c++)
                  Expanded(child: _padKey(r, c)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _padKey(int row, int col) {
    final label = _rows[row * 3 + col];
    final isBackspace = label == '⌫';
    return _Key(
      height: height,
      label: label,
      onTap: () {
        tapHaptic();
        if (isBackspace) {
          onBackspace();
        } else {
          onDigit(label);
        }
      },
      onLongPress: isBackspace ? onLongBackspace : null,
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.height,
    required this.label,
    required this.onTap,
    this.onLongPress,
  });

  final double height;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final isBackspace = label == '⌫';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: AppColors.key,
        borderRadius: BorderRadius.circular(20),
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.line, width: 1),
            ),
            child: isBackspace
                ? const Icon(
                    Icons.backspace_outlined,
                    color: AppColors.negative,
                    size: 26,
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.keyText,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
