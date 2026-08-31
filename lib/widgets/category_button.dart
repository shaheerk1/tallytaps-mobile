import 'package:flutter/material.dart';

import '../models/category_spec.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// One big, thumb-sized category button from the bottom dock.
/// Deliberately large and high contrast so older users can hit it first try.
class CategoryButton extends StatelessWidget {
  const CategoryButton({
    super.key,
    required this.spec,
    required this.onTap,
    this.subtitle,
  });

  final CategorySpec spec;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        label: spec.label,
        child: InkWell(
          onTap: () {
            tapHaptic();
            onTap();
          },
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [spec.color, _darken(spec.color)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: spec.color.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(spec.icon, color: Colors.white, size: 38),
              ),
              const SizedBox(height: 8),
              Text(
                spec.label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkFaint,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _darken(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0)).toColor();
  }
}
