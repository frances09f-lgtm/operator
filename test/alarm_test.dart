import 'package:flutter_test/flutter_test.dart';
import 'package:friday_app/features/alarm/alarm_time_parser.dart';
import 'package:friday_app/features/assistant/domain/intent_model.dart';
import 'package:friday_app/features/assistant/domain/intent_parser.dart';

void main() {
  group('AlarmTimeParser - relative', () {
    test('in 10 minutes is ~10 min ahead', () {
      final now = DateTime(2026, 9, 23, 8, 0);
      final parsed = parseAlarmTime('set an alarm in 10 minutes', now: now)!;
      expect(parsed.isRelative, isTrue);
      expect(parsed.when.difference(now).inMinutes, 10);
    });

    test('after 1 hour 30 minutes sums both parts', () {
      final now = DateTime(2026, 9, 23, 8, 0);
      final parsed = parseAlarmTime('remind me after 1 hour 30 minutes', now: now)!;
      expect(parsed.when.difference(now).inMinutes, 90);
    });

    test('5 minutes later works without in/after', () {
      final now = DateTime(2026, 9, 23, 8, 0);
      final parsed =
          parseAlarmTime('set alarm 5 minutes later', now: now)!;
      expect(parsed.when.difference(now).inMinutes, 5);
    });
  });

  group('AlarmTimeParser - absolute', () {
    test('7am today when in the future', () {
      final now = DateTime(2026, 9, 23, 6, 0);
      final parsed = parseAlarmTime('set an alarm for 7 am', now: now)!;
      expect(parsed.when, DateTime(2026, 9, 23, 7, 0));
    });

    test('past time rolls to tomorrow', () {
      final now = DateTime(2026, 9, 23, 9, 0);
      final parsed = parseAlarmTime('set an alarm for 7 am', now: now)!;
      expect(parsed.when, DateTime(2026, 9, 24, 7, 0));
    });

    test('7:30 pm parses with minutes', () {
      final now = DateTime(2026, 9, 23, 6, 0);
      final parsed = parseAlarmTime('wake me up at 7:30 pm', now: now)!;
      expect(parsed.when, DateTime(2026, 9, 23, 19, 30));
    });

    test('tomorrow forces next day', () {
      final now = DateTime(2026, 9, 23, 20, 0);
      final parsed =
          parseAlarmTime('set alarm tomorrow at 6:30 am', now: now)!;
      expect(parsed.when, DateTime(2026, 9, 24, 6, 30));
    });

    test('no time returns null', () {
      expect(parseAlarmTime('set an alarm'), isNull);
    });
  });

  group('AlarmTimeParser - messages and labels', () {
    test('reminder message strips verb and time', () {
      expect(
        parseReminderMessage('remind me to drink water in 10 minutes'),
        'drink water',
      );
    });

    test('remind me at 9pm to call mom keeps call mom', () {
      final msg = parseReminderMessage('remind me at 9pm to call mom');
      expect(msg.toLowerCase(), contains('call mom'));
    });

    test('alarm label after called', () {
      expect(parseAlarmLabel('set alarm for 7am called gym'), 'gym');
    });

    test('for 7am is not a label', () {
      expect(parseAlarmLabel('set alarm for 7am'), isEmpty);
    });
  });

  group('IntentParser - alarm intents (LLM path)', () {
    final parser = IntentParser();

    test('set_alarm with time string', () {
      final intent = parser.parse('{"action": "set_alarm", "time": "in 10 minutes"}');
      expect(intent, isA<SetAlarmIntent>());
      expect(
        (intent as SetAlarmIntent).time.isAfter(DateTime.now()),
        isTrue,
      );
    });

    test('set_reminder with message', () {
      final intent = parser.parse(
          '{"action": "set_reminder", "time": "in 10 minutes", "message": "drink water"}');
      expect(intent, isA<SetReminderIntent>());
      expect((intent as SetReminderIntent).message, 'drink water');
    });

    test('set_reminder without message is invalid', () {
      expect(
        () => parser.parse('{"action": "set_reminder", "time": "in 10 minutes"}'),
        throwsA(isA<Exception>()),
      );
    });

    test('list_alarms', () {
      expect(parser.parse('{"action": "list_alarms"}'), isA<ListAlarmsIntent>());
    });

    test('cancel_alarm keeps query', () {
      final intent =
          parser.parse('{"action": "cancel_alarm", "target": "7am"}');
      expect(intent, isA<CancelAlarmIntent>());
      expect((intent as CancelAlarmIntent).query, '7am');
    });

    test('alarm steps survive inside a JSON sequence', () {
      final intent = parser.parse(
          '[{"action": "set_alarm", "time": "in 10 minutes"}, {"action": "set_volume", "value": 40}]');
      expect(intent, isA<SequenceIntent>());
      final steps = (intent as SequenceIntent).steps;
      expect(steps[0], isA<SetAlarmIntent>());
      expect(steps[1], isA<VolumeIntent>());
    });
  });
}
