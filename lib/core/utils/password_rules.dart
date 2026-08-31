/// One password rule — used both by the live checklist and by
/// [PasswordRules.validate]. Mirrors the backend's own check.
class PasswordRule {
  const PasswordRule({
    required this.label,
    required this.errorMessage,
    required this.isSatisfied,
  });

  /// Short label for the checklist, e.g. "At least 8 characters".
  final String label;

  /// Full sentence for the form validator.
  final String errorMessage;

  final bool Function(String value) isSatisfied;
}

/// The rules a password must satisfy to register or reset a password.
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

  /// A form-field validator: the first unmet rule's message, or null.
  static String? validate(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required.';
    for (final rule in all) {
      if (!rule.isSatisfied(v)) return rule.errorMessage;
    }
    return null;
  }
}
