import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_exception.dart';
import 'session_controller.dart';
import 'verify_email_controller.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  String get _email => ref.read(sessionControllerProvider).user?.email ?? '';

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    ref
        .read(verifyCodeControllerProvider.notifier)
        .submit(email: _email, code: _codeController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final verifyState = ref.watch(verifyCodeControllerProvider);
    final resendState = ref.watch(resendCodeControllerProvider);
    final verifyError = verifyState.hasError ? verifyState.error : null;
    final apiError = verifyError is ApiException ? verifyError : null;

    ref.listen(verifyCodeControllerProvider, (previous, next) {
      final justVerified = previous?.isLoading == true && next.hasValue;
      if (justVerified) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Email verified!')));
        context.pop();
      }
    });

    ref.listen(resendCodeControllerProvider, (previous, next) {
      final justSent = previous?.isLoading == true && next.hasValue;
      if (justSent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A new code has been sent.')),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Verify your email')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Enter the 6-digit code we sent to $_email',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _codeController,
                  decoration: const InputDecoration(
                    labelText: 'Verification code',
                  ),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, letterSpacing: 8),
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onFieldSubmitted: (_) => _submit(),
                  validator: (value) {
                    final v = value?.trim() ?? '';
                    if (v.length != 6) return 'Enter the 6-digit code.';
                    return null;
                  },
                ),
                if (apiError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      apiError.message,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: verifyState.isLoading ? null : _submit,
                  child: verifyState.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Verify'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: resendState.isLoading
                      ? null
                      : () => ref
                            .read(resendCodeControllerProvider.notifier)
                            .resend(email: _email),
                  child: const Text("Didn't get a code? Resend"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
