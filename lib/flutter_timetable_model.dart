import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';

/// Representation of a deduplicated university timetable event.
class TimetableEvent {
  final String id;
  final String day;
  final String dateRange;
  final String exactDate;
  final String formattedDate;
  final int academicWeek;
  final String module;
  final String type;
  final String start;
  final String finish;
  final String location;
  final String size;
  final String staff;
  final bool isCrossListed;

  TimetableEvent({
    required this.id,
    required this.day,
    required this.dateRange,
    required this.exactDate,
    required this.formattedDate,
    required this.academicWeek,
    required this.module,
    required this.type,
    required this.start,
    required this.finish,
    required this.location,
    required this.size,
    required this.staff,
  }) : isCrossListed = module.contains(' / ');

  factory TimetableEvent.fromJson(Map<String, dynamic> json) {
    return TimetableEvent(
      id: json['id'] ?? '',
      day: json['Day'] ?? '',
      dateRange: json['DateRange'] ?? '',
      exactDate: json['ExactDate'] ?? '',
      formattedDate: json['FormattedDate'] ?? '',
      academicWeek: json['AcademicWeek'] is int
          ? json['AcademicWeek']
          : int.tryParse(json['AcademicWeek']?.toString() ?? '0') ?? 0,
      module: json['Module'] ?? '',
      type: json['Type'] ?? '',
      start: json['Start'] ?? '',
      finish: json['Finish'] ?? '',
      location: json['Location'] ?? '',
      size: json['Size'] ?? '',
      staff: json['Staff'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'Day': day,
        'DateRange': dateRange,
        'ExactDate': exactDate,
        'FormattedDate': formattedDate,
        'AcademicWeek': academicWeek,
        'Module': module,
        'Type': type,
        'Start': start,
        'Finish': finish,
        'Location': location,
        'Size': size,
        'Staff': staff,
      };
}

/// Cache Manager that loads timetable instantly from Hive database before background sync.
class TimetableCacheManager {
  static const String _boxName = 'timetable_events_box';

  Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox<String>(_boxName);
  }

  Future<void> cacheEvents(List<TimetableEvent> events) async {
    final box = Hive.box<String>(_boxName);
    final rawJson = jsonEncode(events.map((e) => e.toJson()).toList());
    await box.put('cached_schedule', rawJson);
    await box.put('last_updated', DateTime.now().toIso8601String());
  }

  List<TimetableEvent> getCachedEvents() {
    final box = Hive.box<String>(_boxName);
    final rawJson = box.get('cached_schedule');
    if (rawJson == null || rawJson.isEmpty) return [];

    final List<dynamic> list = jsonDecode(rawJson);
    return list.map((item) => TimetableEvent.fromJson(Map<String, dynamic>.from(item))).toList();
  }

  String? getLastUpdatedTime() {
    final box = Hive.box<String>(_boxName);
    return box.get('last_updated');
  }

  // Notification Preferences
  Future<void> saveNotificationSettings({
    required bool cancellations,
    required bool roomChanges,
    required bool reschedules,
    required bool assessmentReminders,
    required List<int> reminderIntervalHours,
  }) async {
    final box = Hive.box<String>(_boxName);
    await box.put('settings_cancellations', cancellations.toString());
    await box.put('settings_room_changes', roomChanges.toString());
    await box.put('settings_reschedules', reschedules.toString());
    await box.put('settings_assessment_reminders', assessmentReminders.toString());
    await box.put('settings_reminder_hours', jsonEncode(reminderIntervalHours));
  }

  Map<String, dynamic> getNotificationSettings() {
    final box = Hive.box<String>(_boxName);
    final c = box.get('settings_cancellations');
    final rc = box.get('settings_room_changes');
    final rs = box.get('settings_reschedules');
    final ar = box.get('settings_assessment_reminders');
    final rh = box.get('settings_reminder_hours');

    List<int> reminderHours = [1, 24]; // default 1 hour and 24 hours before
    if (rh != null && rh.isNotEmpty) {
      try {
        final List<dynamic> parsed = jsonDecode(rh);
        reminderHours = parsed.map((e) => int.parse(e.toString())).toList();
      } catch (_) {}
    }

    return {
      'cancellations': c == null ? false : c == 'true',
      'roomChanges': rc == null ? false : rc == 'true',
      'reschedules': rs == null ? false : rs == 'true',
      'assessmentReminders': ar == null ? false : ar == 'true',
      'reminderHours': reminderHours,
    };
  }

  Future<void> setCompletedPermissionsOnboarding(bool completed) async {
    final box = Hive.box<String>(_boxName);
    await box.put('has_completed_permissions_onboarding', completed.toString());
  }

  bool hasCompletedPermissionsOnboarding() {
    final box = Hive.box<String>(_boxName);
    return box.get('has_completed_permissions_onboarding') == 'true';
  }

  Future<void> clearCache() async {
    final box = Hive.box<String>(_boxName);
    await box.clear();
  }
}
