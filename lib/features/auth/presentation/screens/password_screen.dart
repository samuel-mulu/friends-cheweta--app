import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/errors/app_failure.dart';
import 'package:friends_game_app/core/theme/app_spacing.dart';
import 'package:friends_game_app/core/utils/validators.dart';
import 'package:friends_game_app/core/widgets/app_button.dart';
import 'package:friends_game_app/core/widgets/app_text_field.dart';
import 'package:friends_game_app/features/auth/data/auth_repository.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/auth/presentation/widgets/sms_verification_fields.dart';

class PasswordScreen extends ConsumerStatefulWidget {
  const PasswordScreen.reset({super.key, this.initialPhone}) : reset = true;
  const PasswordScreen.change({super.key})
      : reset = false,
        initialPhone = null;

  final bool reset;
  final String? initialPhone;

  @override
  ConsumerState<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends ConsumerState<PasswordScreen> {
  final _form = GlobalKey<FormState>();
  late final _phone = TextEditingController(text: widget.initialPhone);
  final _code = TextEditingController();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _requested = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.reset) {
        await ref
            .read(authRepositoryProvider)
            .resetPassword(_phone.text, _code.text, _password.text);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Password reset. Sign in with your new password.')));
        context.go('/login');
      } else {
        await ref
            .read(authControllerProvider.notifier)
            .changePassword(_current.text, _password.text);
      }
    } on AppFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.reset ? 'Reset password' : 'Change password';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.screen),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _form,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.reset)
                        SmsVerificationFields(
                          phone: _phone,
                          code: _code,
                          reset: true,
                          disabled: _busy,
                          onRequested: (value) => setState(() {
                            _requested = value;
                            _error = null;
                          }),
                        )
                      else
                        AppTextField(
                            controller: _current,
                            label: 'Current password',
                            obscureText: true,
                            validator: Validators.password),
                      if (!widget.reset || _requested) ...[
                        const SizedBox(height: 16),
                        AppTextField(
                            controller: _password,
                            label: 'New password',
                            obscureText: true,
                            validator: Validators.password),
                        const SizedBox(height: 16),
                        AppTextField(
                            controller: _confirm,
                            label: 'Confirm new password',
                            obscureText: true,
                            validator: (value) => value != _password.text
                                ? 'Passwords do not match.'
                                : Validators.password(value)),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                        ],
                        const SizedBox(height: 24),
                        AppButton(
                            label: title, loading: _busy, onPressed: _save),
                      ],
                    ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
