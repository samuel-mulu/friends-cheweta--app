import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/theme/app_spacing.dart';
import 'package:friends_game_app/core/utils/validators.dart';
import 'package:friends_game_app/core/widgets/app_button.dart';
import 'package:friends_game_app/core/widgets/app_text_field.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() { _phone.dispose(); _password.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.screen),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Friends Game Hub', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text('Sign in to continue.', style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 32),
                  AppTextField(controller: _phone, label: 'Phone number', keyboardType: TextInputType.phone, prefixIcon: Icons.phone_rounded, validator: Validators.phone),
                  const SizedBox(height: 16),
                  AppTextField(controller: _password, label: 'Password', obscureText: true, prefixIcon: Icons.lock_outline_rounded, validator: Validators.password),
                  if (auth.error != null) ...[
                    const SizedBox(height: 12),
                    Text(auth.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  AppButton(
                    label: 'Sign in',
                    loading: auth.loading,
                    onPressed: () async {
                      if (!_formKey.currentState!.validate()) return;
                      await ref.read(authControllerProvider.notifier).login(phoneNumber: _phone.text, password: _password.text);
                    },
                  ),
                  const SizedBox(height: 12),
                  Center(child: TextButton(onPressed: () => context.go('/register'), child: const Text('Create an account'))),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
