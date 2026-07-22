import 'dart:async';
import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';
import 'flutter_timetable_model.dart';
import 'flutter_timetable_scraper.dart';
import 'flutter_auth_keystore.dart';

/// Background task identifier
const String kTimetableBackgroundSyncTask = "com.rhul.timetable.background_sync";

/// Top-level callback required by WorkManager for background execution
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final syncEngine = TimetableBackgroundSyncEngine();
      await syncEngine.executePeriodicSync();
      return Future.value(true);
    } catch (_) {
      return Future.value(false);
    }
  });
}

class TimetableBackgroundSyncEngine {
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  TimetableBackgroundSyncEngine() {
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );
    await _notificationsPlugin.initialize(settings: initSettings);
  }

  /// Request notification permissions for Android & iOS
  Future<void> requestPermissions() async {
    final androidImpl = _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.requestNotificationsPermission();
    }

    final iosImpl = _notificationsPlugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (iosImpl != null) {
      await iosImpl.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  /// Register periodic background sync (runs automatically in background every 15-30 minutes)
  static Future<void> initializeBackgroundSync() async {
    try {
      await Workmanager().initialize(
        callbackDispatcher,
      );

      await Workmanager().registerPeriodicTask(
        "rhul_timetable_periodic_sync",
        kTimetableBackgroundSyncTask,
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
      );
    } catch (_) {}
  }

  /// Executes background scrape & diff check against cached schedule
  Future<void> executePeriodicSync() async {
    final cacheManager = TimetableCacheManager();
    await cacheManager.init();

    final settings = cacheManager.getNotificationSettings();
    final notifyCancellations = settings['cancellations'] as bool;
    final notifyRoomChanges = settings['roomChanges'] as bool;
    final notifyReschedules = settings['reschedules'] as bool;
    final notifyAssessmentReminders = settings['assessmentReminders'] as bool;
    final reminderHours = (settings['reminderHours'] as List).cast<int>();

    // 1. Get cached events
    final oldEvents = cacheManager.getCachedEvents();

    // 2. Fetch fresh live events using stored credentials
    final newEvents = await _fetchLiveTimetableEvents();

    if (newEvents.isEmpty) return;

    // 3. Run Diff Engine if we had previous events
    if (oldEvents.isNotEmpty) {
      final diff = TimetableDiffEngine.compareSchedules(oldEvents, newEvents);

      // 4. Trigger Notifications for cancellations, room changes, and reschedules
      if (notifyCancellations) {
        for (final cancelled in diff.cancelledEvents) {
          final isAssessment = cancelled.type.toLowerCase().contains('assessment') ||
              cancelled.type.toLowerCase().contains('exam');
          final icon = isAssessment ? "📝 ASSESSMENT" : "📚 Lecture";
          await _showNotification(
            id: cancelled.id.hashCode,
            title: "🚨 $icon Cancelled",
            body: "${cancelled.module} on ${cancelled.formattedDate} (${cancelled.start}) has been cancelled.",
          );
        }
      }

      if (notifyRoomChanges) {
        for (final moved in diff.roomChangeEvents) {
          final isAssessment = moved.event.type.toLowerCase().contains('assessment') ||
              moved.event.type.toLowerCase().contains('exam');
          final icon = isAssessment ? "📝 Assessment" : "📍 Lecture";
          await _showNotification(
            id: moved.event.id.hashCode,
            title: "$icon Location Changed",
            body: "${moved.event.module} on ${moved.event.formattedDate} moved to ${moved.newLocation} (was ${moved.oldLocation}).",
          );
        }
      }

      if (notifyReschedules) {
        for (final rescheduled in diff.rescheduledEvents) {
          final isAssessment = rescheduled.event.type.toLowerCase().contains('assessment') ||
              rescheduled.event.type.toLowerCase().contains('exam');
          final icon = isAssessment ? "📝 Assessment" : "🕒 Lecture";
          await _showNotification(
            id: rescheduled.event.id.hashCode,
            title: "$icon Rescheduled",
            body: "${rescheduled.event.module} on ${rescheduled.event.formattedDate} rescheduled to ${rescheduled.newStart} - ${rescheduled.newFinish}.",
          );
        }
      }
    }

    // 5. Schedule Assessment Reminders if enabled
    if (notifyAssessmentReminders) {
      await scheduleAssessmentReminders(newEvents, reminderHours);
    }

    // 6. Update Hive Cache with fresh data
    await cacheManager.cacheEvents(newEvents);
  }

  /// Schedule customizable reminders for upcoming assessments
  Future<void> scheduleAssessmentReminders(
      List<TimetableEvent> events, List<int> reminderHours) async {
    if (reminderHours.isEmpty) return;

    final assessments = events.where((e) {
      final t = e.type.toLowerCase();
      return t.contains('assessment') || t.contains('exam') || t.contains('test');
    }).toList();

    final now = DateTime.now();

    for (final a in assessments) {
      final dateParts = a.exactDate.split('-');
      final timeParts = a.start.split(':');
      if (dateParts.length == 3 && timeParts.length >= 2) {
        try {
          final year = int.parse(dateParts[0]);
          final month = int.parse(dateParts[1]);
          final day = int.parse(dateParts[2]);
          final hour = int.parse(timeParts[0]);
          final minute = int.parse(timeParts[1]);

          final assessmentTime = DateTime(year, month, day, hour, minute);

          for (final hoursBefore in reminderHours) {
            final notifyTime = assessmentTime.subtract(Duration(hours: hoursBefore));
            if (notifyTime.isAfter(now)) {
              final tzTime = tz.TZDateTime.from(notifyTime, tz.local);
              final notificationId = (a.id + '_rem_' + hoursBefore.toString()).hashCode;

              String intervalText;
              if (hoursBefore == 1) {
                intervalText = "1 hour";
              } else if (hoursBefore < 24) {
                intervalText = "$hoursBefore hours";
              } else if (hoursBefore == 24) {
                intervalText = "1 day";
              } else if (hoursBefore % 24 == 0) {
                intervalText = "${hoursBefore ~/ 24} days";
              } else {
                intervalText = "$hoursBefore hours";
              }

              await _notificationsPlugin.zonedSchedule(
                id: notificationId,
                title: "📝 Upcoming Assessment Reminder",
                body: "${a.module} assessment is starting in $intervalText at ${a.start} in ${a.location}.",
                scheduledDate: tzTime,
                notificationDetails: const NotificationDetails(
                  android: AndroidNotificationDetails(
                    'assessment_reminders_channel',
                    'Assessment Reminders',
                    channelDescription: 'Customizable countdown reminders for upcoming university assessments',
                    importance: Importance.max,
                    priority: Priority.high,
                  ),
                  iOS: DarwinNotificationDetails(
                    presentAlert: true,
                    presentBadge: true,
                    presentSound: true,
                  ),
                ),
                androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
              );
            }
          }
        } catch (_) {}
      }
    }
  }

  Future<List<TimetableEvent>> _fetchLiveTimetableEvents() async {
    try {
      final storage = SecureCredentialStorage();
      final creds = await storage.getStudentCredentials();
      if (creds != null && creds.username.isNotEmpty && creds.password.isNotEmpty) {
        final scraper = DirectDartTimetableScraper();
        return await scraper.scrapeTimetable(
          username: creds.username,
          password: creds.password,
        );
      }
    } catch (_) {}
    return [];
  }

  Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'timetable_alerts_channel',
      'Timetable Alerts',
      channelDescription: 'Notifications for lecture/assessment cancellations, room changes, and reschedules',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'Timetable Change Alert',
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _notificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: notificationDetails,
    );
  }
}

/// Diff Engine for detecting schedule changes
class TimetableDiffEngine {
  static DiffReport compareSchedules(
      List<TimetableEvent> oldEvents, List<TimetableEvent> newEvents) {
    final List<TimetableEvent> cancelled = [];
    final List<RoomChange> roomChanges = [];
    final List<RescheduledEvent> rescheduled = [];

    // 1. Create mutable lists to track unmatched events
    final unmatchedOld = List<TimetableEvent>.from(oldEvents);
    final unmatchedNew = List<TimetableEvent>.from(newEvents);

    // 2. Exact Matches (Same Date, Module, Type, Start, Finish)
    for (int i = unmatchedOld.length - 1; i >= 0; i--) {
      final oldE = unmatchedOld[i];
      final matchIndex = unmatchedNew.indexWhere((newE) =>
          oldE.exactDate == newE.exactDate &&
          oldE.module == newE.module &&
          oldE.type == newE.type &&
          oldE.start == newE.start &&
          oldE.finish == newE.finish);

      if (matchIndex != -1) {
        final newE = unmatchedNew[matchIndex];
        // Detect Location Change
        if (oldE.location != newE.location &&
            newE.location.isNotEmpty &&
            oldE.location.isNotEmpty) {
          roomChanges.add(RoomChange(
            event: newE,
            oldLocation: oldE.location,
            newLocation: newE.location,
          ));
        }

        unmatchedOld.removeAt(i);
        unmatchedNew.removeAt(matchIndex);
      }
    }

    // 3. Reschedule Matches (Same Date, Module, Type, but DIFFERENT Time)
    for (int i = unmatchedOld.length - 1; i >= 0; i--) {
      final oldE = unmatchedOld[i];
      final matchIndex = unmatchedNew.indexWhere((newE) =>
          oldE.exactDate == newE.exactDate &&
          oldE.module == newE.module &&
          oldE.type == newE.type);

      if (matchIndex != -1) {
        final newE = unmatchedNew[matchIndex];
        rescheduled.add(RescheduledEvent(
          event: newE,
          oldStart: oldE.start,
          newStart: newE.start,
          oldFinish: oldE.finish,
          newFinish: newE.finish,
        ));

        // Also check if room changed during reschedule
        if (oldE.location != newE.location &&
            newE.location.isNotEmpty &&
            oldE.location.isNotEmpty) {
          roomChanges.add(RoomChange(
            event: newE,
            oldLocation: oldE.location,
            newLocation: newE.location,
          ));
        }

        unmatchedOld.removeAt(i);
        unmatchedNew.removeAt(matchIndex);
      }
    }

    // 4. Remaining unmatched old events are Cancellations
    cancelled.addAll(unmatchedOld);

    return DiffReport(
      cancelledEvents: cancelled,
      roomChangeEvents: roomChanges,
      rescheduledEvents: rescheduled,
    );
  }
}

class DiffReport {
  final List<TimetableEvent> cancelledEvents;
  final List<RoomChange> roomChangeEvents;
  final List<RescheduledEvent> rescheduledEvents;

  DiffReport({
    required this.cancelledEvents,
    required this.roomChangeEvents,
    required this.rescheduledEvents,
  });
}

class RoomChange {
  final TimetableEvent event;
  final String oldLocation;
  final String newLocation;

  RoomChange({
    required this.event,
    required this.oldLocation,
    required this.newLocation,
  });
}

class RescheduledEvent {
  final TimetableEvent event;
  final String oldStart;
  final String newStart;
  final String oldFinish;
  final String newFinish;

  RescheduledEvent({
    required this.event,
    required this.oldStart,
    required this.newStart,
    required this.oldFinish,
    required this.newFinish,
  });
}
