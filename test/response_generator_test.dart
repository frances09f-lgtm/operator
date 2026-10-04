import 'package:flutter_test/flutter_test.dart';
import 'package:friday_app/features/assistant/domain/response_generator.dart';

void main() {
  const generator = ResponseGenerator();

  group('ResponseGenerator - App opening', () {
    test('opening uses the resolved app label', () {
      expect(generator.opening('YouTube'), 'Opening YouTube.');
      expect(generator.opening('Spotify'), 'Opening Spotify.');
    });

    test('appNotInstalled capitalizes a bare target name', () {
      expect(generator.appNotInstalled('Telegram'), 'Telegram isn\'t installed.');
      expect(generator.appNotInstalled('telegram'), 'Telegram isn\'t installed.');
    });
  });

  group('ResponseGenerator - Error responses', () {
    test('unsupported command response', () {
      expect(
        generator.unsupportedCommand(),
        'I can only open apps and control media, volume, brightness, alarms and reminders right now.',
      );
    });

    test('cannot understand response', () {
      expect(generator.cannotUnderstand(), 'I couldn\'t understand that command.');
    });

    test('empty input response', () {
      expect(generator.emptyInput(), 'Please tell me which app to open.');
    });

    test('model unavailable response', () {
      expect(generator.modelUnavailable(), 'The local AI model isn\'t available.');
    });

    test('media control failure response', () {
      expect(generator.mediaControlFailed(), 'I couldn\'t control the media.');
    });
  });

  group('ResponseGenerator - Media confirmations', () {
    test('play confirmation', () {
      expect(generator.mediaPlaying(), 'Playing.');
    });

    test('pause confirmation', () {
      expect(generator.mediaPaused(), 'Paused.');
    });

    test('resume confirmation', () {
      expect(generator.mediaResuming(), 'Resuming.');
    });

    test('next confirmation', () {
      expect(generator.mediaSkipping(), 'Skipping.');
    });

    test('previous confirmation', () {
      expect(generator.mediaGoingBack(), 'Going back.');
    });

    test('stop confirmation', () {
      expect(generator.mediaStopped(), 'Stopped.');
    });
  });

  group('ResponseGenerator - displayName', () {
    test('capitalizes first character', () {
      expect(generator.displayName('telegram'), 'Telegram');
      expect(generator.displayName('chrome'), 'Chrome');
    });

    test('handles blank input', () {
      expect(generator.displayName('   '), '');
      expect(generator.displayName(''), '');
    });

    test('preserves already-capitalized names', () {
      expect(generator.displayName('YouTube'), 'YouTube');
    });
  });
}