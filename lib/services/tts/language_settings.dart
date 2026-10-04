/// Supported languages for FRIDAY assistant.
enum AppLanguage {
  english('en-US', 'English'),
  hindi('hi-IN', 'हिन्दी'),
  marathi('mr-IN', 'मराठी');

  const AppLanguage(this.locale, this.label);
  final String locale;
  final String label;
}

/// Detects the language of the user's input and returns the
/// corresponding [AppLanguage]. Defaults to [AppLanguage.english].
AppLanguage detectLanguage(String input) {
  if (input.isEmpty) return AppLanguage.english;

  // Check for Devanagari script (Hindi/Marathi) first.
  if (RegExp(r'[\u0900-\u097F]').hasMatch(input)) {
    return AppLanguage.hindi;
  }

  final lower = input.toLowerCase();

  // Hindi-specific keywords checked first for multi-word phrases.
  if (lower.contains('awaaj') || lower.contains('chiya badhao') || lower.contains('kashi karo')) {
    return AppLanguage.hindi;
  }

  // Marathi standalone words.
  if (lower.contains('ghatao') || lower.contains('band_karo') || lower.contains('kholo')) {
    return AppLanguage.marathi;
  }

  // Marathi multi-word phrases.
  if (lower.contains('chale badhao') || lower.contains('chale ghatao') ||
      lower.contains('chale kholo')) {
    return AppLanguage.marathi;
  }

  return AppLanguage.english;
}

extension AppLanguageExtension on AppLanguage {
  String get ttsLocale => locale;
}
