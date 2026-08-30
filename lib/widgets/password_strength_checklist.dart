import 'package:flutter/material.dart';

import '../core/utils/password_rules.dart';

/// Live, as-you-type visual feedback for each password strength rule
/// (see [PasswordRules]) — a check icon in the theme's success-ish color
/// once a rule is met, an outline circle while it isn't. Deliberately
/// neutral rather than error-red for an unmet rule: nothing is *wrong*
/// yet, the user just isn't done typing.
class PasswordStrengthChecklist extends StatelessWidget {
  const PasswordStrengthChecklist({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final rule in PasswordRules.all)
            _RuleRow(
              label: rule.label,
              met: rule.isSatisfied(password),
              colors: colors,
            ),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.label,
    required this.met,
    required this.colors,
  });

  final String label;
  final bool met;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle : Icons.circle_outlined,
            size: 14,
            color: met ? colors.tertiary : colors.outline,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: met ? colors.tertiary : colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
