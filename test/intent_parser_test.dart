import 'package:flutter_test/flutter_test.dart';
import 'package:friday_app/core/errors/app_exceptions.dart';
import 'package:friday_app/features/assistant/domain/intent_model.dart';
import 'package:friday_app/features/assistant/domain/intent_parser.dart';

void main() {
  late IntentParser parser;

  setUp(() {
    parser = IntentParser();
  });

  group('IntentParser - Valid open_app commands', () {
    test('parses pure JSON open_app', () {
      const output = '{"action": "open_app", "target": "youtube"}';
      final intent = parser.parse(output);

      expect(intent, isA<OpenAppIntent>());
      expect((intent as OpenAppIntent).target, 'youtube');
    });

    test('parses markdown code-block wrapped JSON', () {
      const output = '```json\n{"action": "open_app", "target": "chrome"}\n```';
      final intent = parser.parse(output);

      expect(intent, isA<OpenAppIntent>());
      expect((intent as OpenAppIntent).target, 'chrome');
    });

    test('parses JSON with surrounding text from model', () {
      const output = 'Sure! {"action": "open_app", "target": "spotify"}';
      final intent = parser.parse(output);

      expect(intent, isA<OpenAppIntent>());
      expect((intent as OpenAppIntent).target, 'spotify');
    });

    test('trims whitespace around target', () {
      const output = '{"action": "open_app", "target": "  whatsapp  "}';
      final intent = parser.parse(output);

      expect(intent, isA<OpenAppIntent>());
      expect((intent as OpenAppIntent).target, 'whatsapp');
    });
  });

  group('IntentParser - Valid toggle_flashlight commands', () {
    test('parses toggle_flashlight with empty target', () {
      const output = '{"action": "toggle_flashlight", "target": ""}';
      final intent = parser.parse(output);

      expect(intent, isA<ToggleFlashlightIntent>());
    });

    test('parses markdown wrapped toggle_flashlight', () {
      const output = '```json\n{"action": "toggle_flashlight", "target": ""}\n```';
      final intent = parser.parse(output);

      expect(intent, isA<ToggleFlashlightIntent>());
    });

    test('parses toggle_flashlight ignoring any target value', () {
      const output = '{"action": "toggle_flashlight", "target": "light"}';
      final intent = parser.parse(output);

      expect(intent, isA<ToggleFlashlightIntent>());
    });
  });

  group('IntentParser - Valid toggle_device commands', () {
    test('parses toggle_bluetooth (default toggle)', () {
      const output = '{"action": "toggle_bluetooth", "target": ""}';
      final intent = parser.parse(output);

      expect(intent, isA<ToggleDeviceIntent>());
      expect((intent as ToggleDeviceIntent).device, 'bluetooth');
      expect((intent as ToggleDeviceIntent).desired, ToggleDesired.toggle);
    });

    test('parses toggle_bluetooth with target on', () {
      const output = '{"action": "toggle_bluetooth", "target": "on"}';
      final intent = parser.parse(output);

      expect(intent, isA<ToggleDeviceIntent>());
      expect((intent as ToggleDeviceIntent).device, 'bluetooth');
      expect((intent as ToggleDeviceIntent).desired, ToggleDesired.on);
    });

    test('parses toggle_bluetooth with target off', () {
      const output = '{"action": "toggle_bluetooth", "target": "off"}';
      final intent = parser.parse(output);

      expect(intent, isA<ToggleDeviceIntent>());
      expect((intent as ToggleDeviceIntent).device, 'bluetooth');
      expect((intent as ToggleDeviceIntent).desired, ToggleDesired.off);
    });

    test('parses toggle_wifi (default toggle)', () {
      const output = '{"action": "toggle_wifi", "target": ""}';
      final intent = parser.parse(output);

      expect(intent, isA<ToggleDeviceIntent>());
      expect((intent as ToggleDeviceIntent).device, 'wifi');
      expect((intent as ToggleDeviceIntent).desired, ToggleDesired.toggle);
    });

    test('parses toggle_wifi with target on', () {
      const output = '{"action": "toggle_wifi", "target": "on"}';
      final intent = parser.parse(output);

      expect(intent, isA<ToggleDeviceIntent>());
      expect((intent as ToggleDeviceIntent).device, 'wifi');
      expect((intent as ToggleDeviceIntent).desired, ToggleDesired.on);
    });

    test('parses toggle_wifi with target off', () {
      const output = '{"action": "toggle_wifi", "target": "off"}';
      final intent = parser.parse(output);

      expect(intent, isA<ToggleDeviceIntent>());
      expect((intent as ToggleDeviceIntent).device, 'wifi');
      expect((intent as ToggleDeviceIntent).desired, ToggleDesired.off);
    });

    test('parses markdown wrapped toggle_wifi', () {
      const output = '```json\n{"action": "toggle_wifi", "target": "on"}\n```';
      final intent = parser.parse(output);

      expect(intent, isA<ToggleDeviceIntent>());
      expect((intent as ToggleDeviceIntent).device, 'wifi');
      expect((intent as ToggleDeviceIntent).desired, ToggleDesired.on);
    });
  });

  group('IntentParser - Valid media commands', () {
    test('parses media_play', () {
      const output = '{"action": "media_play"}';
      final intent = parser.parse(output);

      expect(intent, isA<MediaIntent>());
      expect((intent as MediaIntent).action, MediaAction.play);
    });

    test('parses media_pause', () {
      const output = '{"action": "media_pause"}';
      final intent = parser.parse(output);

      expect(intent, isA<MediaIntent>());
      expect((intent as MediaIntent).action, MediaAction.pause);
    });

    test('parses media_resume', () {
      const output = '{"action": "media_resume"}';
      final intent = parser.parse(output);

      expect(intent, isA<MediaIntent>());
      expect((intent as MediaIntent).action, MediaAction.resume);
    });

    test('parses media_next', () {
      const output = '{"action": "media_next"}';
      final intent = parser.parse(output);

      expect(intent, isA<MediaIntent>());
      expect((intent as MediaIntent).action, MediaAction.next);
    });

    test('parses media_previous', () {
      const output = '{"action": "media_previous"}';
      final intent = parser.parse(output);

      expect(intent, isA<MediaIntent>());
      expect((intent as MediaIntent).action, MediaAction.previous);
    });

    test('parses media_stop', () {
      const output = '{"action": "media_stop"}';
      final intent = parser.parse(output);

      expect(intent, isA<MediaIntent>());
      expect((intent as MediaIntent).action, MediaAction.stop);
    });

    test('parses markdown code-block wrapped media JSON', () {
      const output = '```json\n{"action": "media_play"}\n```';
      final intent = parser.parse(output);

      expect(intent, isA<MediaIntent>());
      expect((intent as MediaIntent).action, MediaAction.play);
    });

    test('parses media JSON with surrounding text from model', () {
      const output = 'Sure! {"action": "media_pause"}';
      final intent = parser.parse(output);

      expect(intent, isA<MediaIntent>());
      expect((intent as MediaIntent).action, MediaAction.pause);
    });

    test('normalizes action case and whitespace', () {
      const output = '{"action": "  Media_Play  "}';
      final intent = parser.parse(output);

      expect(intent, isA<MediaIntent>());
      expect((intent as MediaIntent).action, MediaAction.play);
    });

    test('parses media intent ignoring any target value', () {
      const output = '{"action": "media_next", "target": "song"}';
      final intent = parser.parse(output);

      expect(intent, isA<MediaIntent>());
      expect((intent as MediaIntent).action, MediaAction.next);
    });
  });

  group('IntentParser - Rejects actions outside the media allowlist', () {
    test('rejects media_rewind', () {
      const output = '{"action": "media_rewind"}';
      expect(
        () => parser.parse(output),
        throwsA(isA<UnsupportedActionException>()),
      );
    });

    test('rejects open_settings', () {
      const output = '{"action": "open_settings"}';
      expect(
        () => parser.parse(output),
        throwsA(isA<UnsupportedActionException>()),
      );
    });

    test('parses send_message as SendSmsIntent', () {
      const output = '{"action": "send_message", "target": "FO", "message": "call mom and ask how she is"}';
      final intent = parser.parse(output);
      expect(intent, isA<SendSmsIntent>());
      expect((intent as SendSmsIntent).recipient, 'FO');
      expect(intent.message, 'call mom and ask how she is');
      expect(intent.phoneNumber, '+16289985940');
    });

    test('rejects make_call without a contact', () {
      const output = '{"action": "make_call"}';
      expect(
        () => parser.parse(output),
        throwsA(isA<InvalidIntentException>()),
      );
    });

    test('rejects launch_spotify', () {
      const output = '{"action": "launch_spotify"}';
      expect(
        () => parser.parse(output),
        throwsA(isA<UnsupportedActionException>()),
      );
    });

    test('rejects execute_shell', () {
      const output = '{"action": "execute_shell"}';
      expect(
        () => parser.parse(output),
        throwsA(isA<UnsupportedActionException>()),
      );
    });

    test('rejects misspelled media action', () {
      const output = '{"action": "media_pla"}';
      expect(
        () => parser.parse(output),
        throwsA(isA<UnsupportedActionException>()),
      );
    });
  });

  group('IntentParser - Malformed media AI responses & strict schema', () {
    test('rejects non-json media response', () {
      const output = 'Sure, I will pause the music.';
      expect(
        () => parser.parse(output),
        throwsA(isA<InvalidIntentException>()),
      );
    });

    test('rejects broken JSON', () {
      const output = '{"action": "media_play"';
      expect(
        () => parser.parse(output),
        throwsA(isA<InvalidIntentException>()),
      );
    });

    test('rejects media JSON with unexpected fields', () {
      const output = '{"action": "media_play", "command": "rm -rf /"}';
      expect(
        () => parser.parse(output),
        throwsA(isA<InvalidIntentException>()),
      );
    });

    test('rejects null action', () {
      const output = '{"action": null}';
      expect(
        () => parser.parse(output),
        throwsA(isA<InvalidIntentException>()),
      );
    });

    test('rejects missing action field', () {
      const output = '{"target": "music"}';
      expect(
        () => parser.parse(output),
        throwsA(isA<InvalidIntentException>()),
      );
    });
  });

  group('IntentParser - Unsupported actions', () {
    test('parses explicit unsupported action', () {
      const output = '{"action": "unsupported", "target": ""}';
      final intent = parser.parse(output);

      expect(intent, isA<UnsupportedIntent>());
    });

    test('parses call_phone as a phone call', () {
      const output = '{"action": "call_phone", "target": "john"}';
      final intent = parser.parse(output);

      expect(intent, isA<CallIntent>());
      expect((intent as CallIntent).contactName, 'john');
    });

    test('parses call with contact aliases', () {
      const output = '{"action": "call", "contact": "mom"}';
      final intent = parser.parse(output);

      expect(intent, isA<CallIntent>());
      expect((intent as CallIntent).contactName, 'mom');
    });

    test('parses send_sms as SendSmsIntent', () {
      const output = '{"action": "send_sms", "recipient": "FO", "message": "hello FO"}';
      final intent = parser.parse(output);
      expect(intent, isA<SendSmsIntent>());
      expect((intent as SendSmsIntent).recipient, 'FO');
      expect(intent.message, 'hello FO');
      expect(intent.phoneNumber, '+16289985940');
    });

    test('rejects play_music', () {
      const output = '{"action": "play_music", "target": "song"}';
      expect(
        () => parser.parse(output),
        throwsA(isA<UnsupportedActionException>()),
      );
    });

    test('rejects search_web', () {
      const output = '{"action": "search_web", "target": "weather"}';
      expect(
        () => parser.parse(output),
        throwsA(isA<UnsupportedActionException>()),
      );
    });

    test('rejects empty target for open_app', () {
      const output = '{"action": "open_app", "target": ""}';
      expect(
        () => parser.parse(output),
        throwsA(isA<UnsupportedActionException>()),
      );
    });
  });

  group('IntentParser - Malformed AI responses & strict schema', () {
    test('rejects non-json string', () {
      const output = 'I cannot do that.';
      expect(
        () => parser.parse(output),
        throwsA(isA<InvalidIntentException>()),
      );
    });

    test('rejects broken json', () {
      const output = '{"action": "open_app", "target": ';
      expect(
        () => parser.parse(output),
        throwsA(isA<InvalidIntentException>()),
      );
    });

    test('rejects unexpected fields in JSON (schema enforcement)', () {
      const output = '{"action": "open_app", "target": "youtube", "extra": "exploit"}';
      expect(
        () => parser.parse(output),
        throwsA(isA<InvalidIntentException>()),
      );
    });

    test('rejects missing action field', () {
      const output = '{"target": "youtube"}';
      expect(
        () => parser.parse(output),
        throwsA(isA<InvalidIntentException>()),
      );
    });
  });

  group('IntentParser - Valid volume commands', () {
    test('parses set_volume with numeric value', () {
      const output = '{"action": "set_volume", "value": 50}';
      final intent = parser.parse(output);

      expect(intent, isA<VolumeIntent>());
      expect((intent as VolumeIntent).level, 50);
    });

    test('parses set_volume with percent string value', () {
      const output = '{"action": "set_volume", "value": "75%"}';
      final intent = parser.parse(output);

      expect(intent, isA<VolumeIntent>());
      expect((intent as VolumeIntent).level, 75);
    });

    test('clamps out-of-range volume to 0-100', () {
      const output = '{"action": "set_volume", "value": 150}';
      final intent = parser.parse(output);

      expect(intent, isA<VolumeIntent>());
      expect((intent as VolumeIntent).level, 100);
    });

    test('parses volume_up as a relative increase', () {
      const output = '{"action": "volume_up"}';
      final intent = parser.parse(output);

      expect(intent, isA<VolumeIntent>());
      expect((intent as VolumeIntent).delta, 1);
      expect(intent.level, isNull);
    });

    test('parses volume_down as a relative decrease', () {
      const output = '{"action": "volume_down"}';
      final intent = parser.parse(output);

      expect(intent, isA<VolumeIntent>());
      expect((intent as VolumeIntent).delta, -1);
    });

    test('parses media_volume_up as a volume intent', () {
      const output = '{"action": "media_volume_up"}';
      final intent = parser.parse(output);

      expect(intent, isA<VolumeIntent>());
      expect((intent as VolumeIntent).delta, 1);
    });
test('parses mute as a mute request', () {
      const output = '{"action": "mute"}';

      final intent = parser.parse(output);

      expect(intent, isA<VolumeIntent>());
      expect((intent as VolumeIntent).mute, isTrue);
    });

    test('parses unmute as an unmute request', () {
      const output = '{"action": "unmute"}';
      final intent = parser.parse(output);

      expect(intent, isA<VolumeIntent>());
      expect((intent as VolumeIntent).unmute, isTrue);
    });

    test('parses set_volume max target as level 100', () {
      const output = '{"action": "set_volume", "target": "max"}';
      final intent = parser.parse(output);

      expect(intent, isA<VolumeIntent>());
      expect((intent as VolumeIntent).level, 100);
    });
  });

  group('IntentParser - Valid brightness commands', () {
    test('parses set_brightness with numeric value', () {
      const output = '{"action": "set_brightness", "value": 70}';
      final intent = parser.parse(output);

      expect(intent, isA<BrightnessIntent>());
      expect((intent as BrightnessIntent).level, 70);
    });

    test('parses set_brightness with level field', () {
      const output = '{"action": "set_brightness", "level": 40}';
      final intent = parser.parse(output);

      expect(intent, isA<BrightnessIntent>());
      expect((intent as BrightnessIntent).level, 40);
    });

    test('parses brightness_up as a relative increase', () {
      const output = '{"action": "brightness_up"}';
      final intent = parser.parse(output);

      expect(intent, isA<BrightnessIntent>());
      expect((intent as BrightnessIntent).delta, 1);
    });

    test('parses brightness_down as a relative decrease', () {
      const output = '{"action": "brightness_down"}';
      final intent = parser.parse(output);

      expect(intent, isA<BrightnessIntent>());
      expect((intent as BrightnessIntent).delta, -1);
    });

    test('parses dim as a relative decrease', () {
      const output = '{"action": "dim"}';
      final intent = parser.parse(output);

      expect(intent, isA<BrightnessIntent>());
      expect((intent as BrightnessIntent).delta, -1);
    });

     test('rejects invented brightness-shell action key', () {
       const output = '{"action": "brightness_up", "command": "rm -rf"}';
       expect(
         () => parser.parse(output),
         throwsA(isA<InvalidIntentException>()),
       );
     });
   });

   group('IntentParser - Hindi volume commands', () {
     test('awaaj badhao is volume_up', () {
       const output = '{"action": "awaaj_badhao"}';
       final intent = parser.parse(output);
       expect(intent, isA<VolumeIntent>());
       expect((intent as VolumeIntent).delta, 1);
     });

     test('awaaj ghatao is volume_down', () {
       const output = '{"action": "awaaj_ghatao"}';
       final intent = parser.parse(output);
       expect(intent, isA<VolumeIntent>());
       expect((intent as VolumeIntent).delta, -1);
     });

     test('awaaj band karo is mute', () {
       const output = '{"action": "awaaj_band_karo"}';
       final intent = parser.parse(output);
       expect(intent, isA<VolumeIntent>());
       expect((intent as VolumeIntent).mute, isTrue);
     });

     test('awaaj kholo is unmute', () {
       const output = '{"action": "awaaj_kholo"}';
       final intent = parser.parse(output);
       expect(intent, isA<VolumeIntent>());
       expect((intent as VolumeIntent).unmute, isTrue);
     });

     test('awaaj 50 karo sets volume to 50', () {
       const output = '{"action": "awaaj_50_karo", "value": 50}';
       final intent = parser.parse(output);
       expect(intent, isA<VolumeIntent>());
       expect((intent as VolumeIntent).level, 50);
     });
   });

   group('IntentParser - Marathi volume commands', () {
     test('chale badhao is volume_up', () {
       const output = '{"action": "chale_badhao"}';
       final intent = parser.parse(output);
       expect(intent, isA<VolumeIntent>());
       expect((intent as VolumeIntent).delta, 1);
     });

     test('ghatao is volume_down', () {
       const output = '{"action": "ghatao"}';
       final intent = parser.parse(output);
       expect(intent, isA<VolumeIntent>());
       expect((intent as VolumeIntent).delta, -1);
     });

     test('band_karo is mute', () {
       const output = '{"action": "band_karo"}';
       final intent = parser.parse(output);
       expect(intent, isA<VolumeIntent>());
       expect((intent as VolumeIntent).mute, isTrue);
     });

     test('kholo is unmute', () {
       const output = '{"action": "kholo"}';
       final intent = parser.parse(output);
       expect(intent, isA<VolumeIntent>());
       expect((intent as VolumeIntent).unmute, isTrue);
     });
   });

   group('IntentParser - Hindi brightness commands', () {
     test('chiya badhao is brightness_up', () {
       const output = '{"action": "chiya_badhao"}';
       final intent = parser.parse(output);
       expect(intent, isA<BrightnessIntent>());
       expect((intent as BrightnessIntent).delta, 1);
     });

     test('kashi karo is brightness_down', () {
       const output = '{"action": "kashi_karo"}';
       final intent = parser.parse(output);
       expect(intent, isA<BrightnessIntent>());
       expect((intent as BrightnessIntent).delta, -1);
     });
   });
}
