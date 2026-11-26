import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/theme/app_spacing.dart';
import 'package:friends_game_app/core/utils/validators.dart';
import 'package:friends_game_app/core/widgets/app_button.dart';
import 'package:friends_game_app/core/widgets/app_text_field.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/auth/presentation/widgets/sms_verification_fields.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _requested = false;
  bool _submitted = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _submitted = true);
    await ref.read(authControllerProvider.notifier).register(
          fullName: _name.text,
          phoneNumber: _phone.text,
          password: _password.text,
          otp: _code.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final error = _submitted ? auth.error : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
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
                      AppTextField(
                          controller: _name,
                          label: 'Full name',
                          prefixIcon: Icons.person_outline_rounded,
                          validator: (value) =>
                              Validators.required(value, label: 'Full name')),
                      const SizedBox(height: 16),
                      SmsVerificationFields(
                        phone: _phone,
                        code: _code,
                        reset: false,
                        disabled: auth.loading,
                        onRequested: (value) => setState(() {
                          _requested = value;
                          _submitted = false;
                        }),
                      ),
                      const SizedBox(height: 8),
                      AppTextField(
                          controller: _password,
                          label: 'Password',
                          obscureText: true,
                          prefixIcon: Icons.lock_outline_rounded,
                          validator: Validators.password),
                      const SizedBox(height: 16),
                      AppTextField(
                          controller: _confirm,
                          label: 'Confirm password',
                          obscureText: true,
                          validator: (value) => value != _password.text
                              ? 'Passwords do not match.'
                              : Validators.password(value)),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(error,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      ],
                      const SizedBox(height: 24),
                      AppButton(
                          label: 'Create account',
                          loading: auth.loading,
                          onPressed: _requested ? _register : null),
                      const SizedBox(height: 12),
                      TextButton(
                          onPressed: () => context.go('/login'),
                          child:
                              const Text('Already have an account? Sign in')),
                    ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
