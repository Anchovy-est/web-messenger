/// A single password-strength rule this app enforces — used both for the
/// live, as-you-type checklist shown under a password field
/// ([PasswordRules.all] + a widget that renders each rule's current
/// pass/fail state) and for the on-submit [PasswordRules.validate].
/// Mirrors the backend's own check (backend/src/schemas/auth.schema.js)
/// rule-for-rule, so nothing a client-side check accepts can still be
/// rejected server-side for a rule the user was never shown.
class PasswordRule {
  const PasswordRule({
    required this.label,
    required this.errorMessage,
    required this.isSatisfied,
  });

  /// Short label for the live checklist, e.g. "At least 8 characters".
  final String label;

  /// Full sentence for the on-submit form validator, e.g. "Password must
  /// be at least 8 characters."
  final String errorMessage;

  final bool Function(String value) isSatisfied;
}

/// The five rules a password must satisfy to register or reset a
/// password — see the class doc comment on [PasswordRule].
class PasswordRules {
  PasswordRules._();

  static final List<PasswordRule> all = [
    PasswordRule(
      label: 'At least 8 characters',
      errorMessage: 'Password must be at least 8 characters.',
      isSatisfied: (v) => v.length >= 8,
    ),
    PasswordRule(
      label: 'One lowercase letter',
      errorMessage: 'Password must contain at least one lowercase letter.',
      isSatisfied: (v) => RegExp(r'[a-z]').hasMatch(v),
    ),
    PasswordRule(
      label: 'One uppercase letter',
      errorMessage: 'Password must contain at least one uppercase letter.',
      isSatisfied: (v) => RegExp(r'[A-Z]').hasMatch(v),
    ),
    PasswordRule(
      label: 'One number',
      errorMessage: 'Password must contain at least one number.',
      isSatisfied: (v) => RegExp(r'[0-9]').hasMatch(v),
    ),
    PasswordRule(
      label: 'One special character',
      errorMessage: 'Password must contain at least one special character.',
      isSatisfied: (v) => RegExp(r'[^A-Za-z0-9]').hasMatch(v),
    ),
  ];

  /// A `TextFormField` validator: the first unmet rule's message, or
  /// null once every rule is satisfied. Pair with
  /// `PasswordStrengthChecklist` (see `lib/widgets/password_strength_checklist.dart`)
  /// for live feedback while typing, rather than only at submit time.
  static String? validate(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required.';
    for (final rule in all) {
      if (!rule.isSatisfied(v)) return rule.errorMessage;
    }
    return null;
  }
}
