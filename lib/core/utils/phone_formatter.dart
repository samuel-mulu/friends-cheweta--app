/// Ethiopian numbers as people read them: 251962520885 -> +251 96 252 0885.
String formatPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 12 && digits.startsWith('251')) {
    return '+251 ${digits.substring(3, 5)} ${digits.substring(5, 8)} ${digits.substring(8)}';
  }
  return raw;
}
