import 'package:flutter/services.dart';
import 'package:friday_app/core/constants/app_constants.dart';
import 'package:friday_app/core/errors/app_exceptions.dart';

/// One scheduled alarm or reminder, as stored natively.
class AlarmItem {
  final int id;
  final String kind;
  final int triggerAtMillis;
  final String label;

  const AlarmItem({
    required this.id,
    required this.kind,
    required this.triggerAtMillis,
    required this.label,
  });

  DateTime get time =>
      DateTime.fromMillisecondsSinceEpoch(triggerAtMillis);

  factory AlarmItem.fromMap(Map<String, dynamic> map) => AlarmItem(
        id: (map['id'] as num?)?.toInt() ?? 0,
        kind: (map['kind'] as String?) ?? 'alarm',
        triggerAtMillis: (map['triggerAtMillis'] as num?)?.toInt() ?? 0,
        label: (map['label'] as String?) ?? '',
      );
}

/// Schedules exact alarms & reminders through the Android native layer.
///
/// Thin MethodChannel wrapper — all time parsing happens in Dart
/// ([alarm_time_parser]) so scheduling is instant and offline.
abstract class AlarmService {
  Future<AlarmItem> setAlarm(DateTime time, {String label = ''});
  Future<AlarmItem> setReminder(DateTime time, String message);
  Future<List<AlarmItem>> listAlarms();
  Future<int> cancelAlarm(String query);
}

class MethodChannelAlarmService implements AlarmService {
  final MethodChannel _channel;

  MethodChannelAlarmService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(AppConstants.alarmChannel);

  @override
  Future<AlarmItem> setAlarm(DateTime time, {String label = ''}) async {
    final map = await _invoke('setAlarm', {
      'triggerAtMillis': time.millisecondsSinceEpoch,
      'label': label,
      'kind': 'alarm',
    });
    return AlarmItem.fromMap(map);
  }

  @override
  Future<AlarmItem> setReminder(DateTime time, String message) async {
    final map = await _invoke('setReminder', {
      'triggerAtMillis': time.millisecondsSinceEpoch,
      'label': message,
      'kind': 'reminder',
    });
    return AlarmItem.fromMap(map);
  }

  @override
  Future<List<AlarmItem>> listAlarms() async {
    try {
      final result = await _channel.invokeMethod('listAlarms');
      if (result is List) {
        return result
            .whereType<Map>()
            .map((e) => AlarmItem.fromMap(
                e.map((k, v) => MapEntry(k.toString(), v))))
            .toList();
      }
      return const [];
    } on PlatformException catch (e) {
      throw AlarmException('Platform error: ${e.message}');
    }
  }

  @override
  Future<int> cancelAlarm(String query) async {
    try {
      final result = await _channel.invokeMethod('cancelAlarm', {
        'query': query,
      });
      if (result is Map) {
        return (result['cancelled'] as num?)?.toInt() ?? 0;
      }
      return 0;
    } on PlatformException catch (e) {
      throw AlarmException('Platform error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> _invoke(
      String method, Map<String, dynamic> args) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        method,
        args,
      );
      if (result == null || result['success'] != true) {
        final err = result?['errorMessage'] as String?;
        throw AlarmException(err ?? "I couldn't set that alarm.");
      }
      return result.map((k, v) => MapEntry(k.toString(), v));
    } on PlatformException catch (e) {
      throw AlarmException('Platform error: ${e.message}');
    }
  }
}
