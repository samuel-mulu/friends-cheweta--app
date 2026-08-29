import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/theme/app_spacing.dart';
import 'package:friends_game_app/core/utils/validators.dart';
import 'package:friends_game_app/core/widgets/app_button.dart';
import 'package:friends_game_app/core/widgets/app_text_field.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() { _name.dispose(); _phone.dispose(); _password.dispose(); _confirm.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.screen),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(children: [
                  AppTextField(controller: _name, label: 'Full name', prefixIcon: Icons.person_outline_rounded, validator: (v) => Validators.required(v, label: 'Full name')),
                  const SizedBox(height: 16),
                  AppTextField(controller: _phone, label: 'Phone number', keyboardType: TextInputType.phone, prefixIcon: Icons.phone_rounded, validator: Validators.phone),
                  const SizedBox(height: 16),
                  AppTextField(controller: _password, label: 'Password', obscureText: true, prefixIcon: Icons.lock_outline_rounded, validator: Validators.password),
                  const SizedBox(height: 16),
                  AppTextField(controller: _confirm, label: 'Confirm password', obscureText: true, prefixIcon: Icons.lock_reset_rounded, validator: (v) {
                    final error = Validators.password(v);
                    if (error != null) return error;
                    if (v != _password.text) return 'Passwords do not match.';
                    return null;
                  }),
                  if (auth.error != null) ...[
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerLeft, child: Text(auth.error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                  ],
                  const SizedBox(height: 24),
                  AppButton(label: 'Create account', loading: auth.loading, onPressed: () async {
                    if (!_formKey.currentState!.validate()) return;
                    await ref.read(authControllerProvider.notifier).register(fullName: _name.text, phoneNumber: _phone.text, password: _password.text);
                  }),
                  const SizedBox(height: 12),
                  TextButton(onPressed: () => context.go('/login'), child: const Text('Already have an account? Sign in')),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
