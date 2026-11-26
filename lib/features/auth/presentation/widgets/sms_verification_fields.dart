import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/errors/app_failure.dart';
import 'package:friends_game_app/core/utils/validators.dart';
import 'package:friends_game_app/core/widgets/app_text_field.dart';
import 'package:friends_game_app/features/auth/data/auth_repository.dart';

class SmsVerificationFields extends ConsumerStatefulWidget {
  const SmsVerificationFields({
    super.key,
    required this.phone,
    required this.code,
    required this.reset,
    required this.onRequested,
    this.disabled = false,
  });

  final TextEditingController phone;
  final TextEditingController code;
  final bool reset;
  final ValueChanged<bool> onRequested;
  final bool disabled;

  @override
  ConsumerState<SmsVerificationFields> createState() =>
      _SmsVerificationFieldsState();
}

class _SmsVerificationFieldsState extends ConsumerState<SmsVerificationFields> {
  Timer? _timer;
  bool _requested = false;
  bool _busy = false;
  int _wait = 0;
  String? _error;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _request() async {
    final validation = Validators.phone(widget.phone.text);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .requestOtp(widget.phone.text, reset: widget.reset);
      if (!mounted) return;
      widget.code.clear();
      setState(() {
        _requested = true;
        _wait = 30;
      });
      widget.onRequested(true);
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() => _wait--);
        if (_wait == 0) timer.cancel();
      });
    } on AppFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeNumber() {
    _timer?.cancel();
    widget.code.clear();
    setState(() {
      _requested = false;
      _wait = 0;
      _error = null;
    });
    widget.onRequested(false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: widget.phone,
          label: 'Phone number',
          keyboardType: TextInputType.phone,
          prefixIcon: Icons.phone_rounded,
          validator: Validators.phone,
          readOnly: _requested || _busy || widget.disabled,
        ),
        const SizedBox(height: 8),
        if (_requested) ...[
          Text(widget.reset
              ? 'If this number is eligible, a reset code will arrive by SMS.'
              : 'Enter the code sent by SMS.'),
          const SizedBox(height: 8),
          TextFormField(
            controller: widget.code,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 4,
            decoration:
                const InputDecoration(labelText: 'SMS code', counterText: ''),
            validator: (value) =>
                value?.length == 4 ? null : 'Enter the four-digit code.',
          ),
        ],
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            if (_requested)
              TextButton(
                  onPressed: _busy || widget.disabled ? null : _changeNumber,
                  child: const Text('Change number')),
            TextButton(
              onPressed:
                  _busy || _wait > 0 || widget.disabled ? null : _request,
              child: Text(_busy
                  ? 'Sending…'
                  : _wait > 0
                      ? 'Resend in ${_wait}s'
                      : _requested
                          ? 'Resend code'
                          : 'Send SMS code'),
            ),
          ],
        ),
        if (_error != null)
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
      ],
    );
  }
}
