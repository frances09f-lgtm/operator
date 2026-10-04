import 'package:friday_app/services/tts/language_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('detectLanguage', () {
    test('detects English by default', () {
      expect(detectLanguage('hello'), equals(AppLanguage.english));
      expect(detectLanguage('open youtube'), equals(AppLanguage.english));
    });

    test('detects Hindi transliterated keywords', () {
      expect(detectLanguage('awaaj badhao'), equals(AppLanguage.hindi));
      expect(detectLanguage('awaaj ghatao'), equals(AppLanguage.hindi));
      expect(detectLanguage('awaaj band karo'), equals(AppLanguage.hindi));
      expect(detectLanguage('awaaj kholo'), equals(AppLanguage.hindi));
      expect(detectLanguage('awaaj 50 karo'), equals(AppLanguage.hindi));
      expect(detectLanguage('chiya badhao'), equals(AppLanguage.hindi));
      expect(detectLanguage('kashi karo'), equals(AppLanguage.hindi));
    });

    test('detects Hindi Devanagari script', () {
      expect(detectLanguage('हेलो'), equals(AppLanguage.hindi));
      expect(detectLanguage('वॉल्यूम बढ़ाओ'), equals(AppLanguage.hindi));
    });

    test('detects Marathi transliterated keywords', () {
      expect(detectLanguage('chale badhao'), equals(AppLanguage.marathi));
      expect(detectLanguage('ghatao'), equals(AppLanguage.marathi));
      expect(detectLanguage('band_karo'), equals(AppLanguage.marathi));
      expect(detectLanguage('kholo'), equals(AppLanguage.marathi));
    });

    test('returns english for empty input', () {
      expect(detectLanguage(''), equals(AppLanguage.english));
    });
  });

  group('AppLanguage', () {
    test('english locale is en-US', () {
      expect(AppLanguage.english.locale, equals('en-US'));
      expect(AppLanguage.english.label, equals('English'));
    });

    test('hindi locale is hi-IN', () {
      expect(AppLanguage.hindi.locale, equals('hi-IN'));
      expect(AppLanguage.hindi.label, equals('हिन्दी'));
    });

    test('marathi locale is mr-IN', () {
      expect(AppLanguage.marathi.locale, equals('mr-IN'));
      expect(AppLanguage.marathi.label, equals('मराठी'));
    });
  });
}
