import 'package:flutter/material.dart';

import '../models/tally_action.dart';
import '../theme/app_colors.dart';

/// Visual identity for each action category: colour, icon and friendly copy.
class CategorySpec {
  const CategorySpec({
    required this.type,
    required this.label,
    required this.icon,
    required this.color,
    required this.prompt,
    required this.badge,
  });

  final ActionType type;
  final String label;

  /// Big icon shown on the button.
  final IconData icon;

  final Color color;

  /// Question shown on the entry screen, e.g. "How much cash did you get?"
  final String prompt;

  /// Short badge under the button label, e.g. "in / out".
  final String badge;

  static const List<CategorySpec> all = [
    CategorySpec(
      type: ActionType.cash,
      label: 'Cash',
      icon: Icons.payments_rounded,
      color: AppColors.cash,
      prompt: 'How much cash?',
      badge: 'in / out',
    ),
    CategorySpec(
      type: ActionType.card,
      label: 'Card',
      icon: Icons.credit_card_rounded,
      color: AppColors.card,
      prompt: 'How much on card?',
      badge: 'in / out',
    ),
    CategorySpec(
      type: ActionType.stock,
      label: 'Stock',
      icon: Icons.inventory_2_rounded,
      color: AppColors.stock,
      prompt: 'What stock moved?',
      badge: 'in / out',
    ),
    CategorySpec(
      type: ActionType.note,
      label: 'Note',
      icon: Icons.edit_note_rounded,
      color: AppColors.note,
      prompt: 'What happened?',
      badge: 'no amount',
    ),
  ];

  static CategorySpec of(ActionType type) =>
      all.firstWhere((s) => s.type == type);
}
