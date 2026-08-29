abstract final class Validators {
  static String? required(String? value, {String label = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$label is required.';
    return null;
  }

  static String? phone(String? value) {
    final requiredError = required(value, label: 'Phone number');
    if (requiredError != null) return requiredError;
    final digits = value!.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.length < 9) return 'Enter a valid phone number.';
    return null;
  }

  static String? password(String? value) {
    final requiredError = required(value, label: 'Password');
    if (requiredError != null) return requiredError;
    if (value!.length < 8) return 'Use at least 8 characters.';
    return null;
  }

  static String? positiveAmount(String? value) {
    final requiredError = required(value, label: 'Amount');
    if (requiredError != null) return requiredError;
    final amount = double.tryParse(value!.replaceAll(',', '').trim());
    if (amount == null || amount <= 0) return 'Enter a valid amount greater than zero.';
    return null;
  }
}
