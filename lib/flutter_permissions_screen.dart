import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'flutter_timetable_model.dart';

class OnboardingPermissionsScreen extends StatefulWidget {
  final VoidCallback onCompleted;

  const OnboardingPermissionsScreen({super.key, required this.onCompleted});

  @override
  State<OnboardingPermissionsScreen> createState() => _OnboardingPermissionsScreenState();
}

class _OnboardingPermissionsScreenState extends State<OnboardingPermissionsScreen> with WidgetsBindingObserver {
  bool _notificationGranted = false;
  bool _batteryGranted = false;
  bool _isChecking = true;

  bool _cancellations = false;
  bool _roomChanges = false;
  bool _reschedules = false;
  bool _assessmentReminders = false;

  final _cacheManager = TimetableCacheManager();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkCurrentPermissions();
    _loadNotificationPreferences();
  }

  void _loadNotificationPreferences() {
    final settings = _cacheManager.getNotificationSettings();
    setState(() {
      _cancellations = settings['cancellations'] as bool;
      _roomChanges = settings['roomChanges'] as bool;
      _reschedules = settings['reschedules'] as bool;
      _assessmentReminders = settings['assessmentReminders'] as bool;
    });
  }

  Future<void> _saveAndComplete() async {
    final existingSettings = _cacheManager.getNotificationSettings();
    final reminderHours = (existingSettings['reminderHours'] as List?)?.cast<int>() ?? [1, 24];

    await _cacheManager.saveNotificationSettings(
      cancellations: _cancellations,
      roomChanges: _roomChanges,
      reschedules: _reschedules,
      assessmentReminders: _assessmentReminders,
      reminderIntervalHours: reminderHours,
    );

    widget.onCompleted();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkCurrentPermissionsWithRetry();
    }
  }

  Future<void> _checkCurrentPermissionsWithRetry() async {
    await _checkCurrentPermissions();
    if (_batteryGranted) return;

    for (final delayMs in [400, 800, 1500]) {
      await Future.delayed(Duration(milliseconds: delayMs));
      if (!mounted || _batteryGranted) break;
      await _checkCurrentPermissions();
    }
  }

  Future<void> _checkCurrentPermissions() async {
    final notifStatus = await Permission.notification.status;
    bool batteryStatus = true;
    if (Platform.isAndroid) {
      final status = await Permission.ignoreBatteryOptimizations.status;
      batteryStatus = status.isGranted;
    }

    if (mounted) {
      setState(() {
        _notificationGranted = notifStatus.isGranted;
        _batteryGranted = batteryStatus;
        _isChecking = false;
      });
    }
  }

  Future<void> _requestNotification() async {
    final status = await Permission.notification.status;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    } else {
      final result = await Permission.notification.request();
      if (result.isPermanentlyDenied) {
        await openAppSettings();
      }
    }
    await _checkCurrentPermissionsWithRetry();
  }

  Future<void> _requestBatteryOptimization() async {
    if (Platform.isAndroid) {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (status.isPermanentlyDenied) {
        await openAppSettings();
      } else {
        final result = await Permission.ignoreBatteryOptimizations.request();
        if (result.isPermanentlyDenied) {
          await openAppSettings();
        }
      }
      await _checkCurrentPermissionsWithRetry();
    }
  }

  bool get _allPermissionsGranted {
    if (!_notificationGranted) return false;
    if (Platform.isAndroid && !_batteryGranted) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = _allPermissionsGranted;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: _saveAndComplete,
                  child: const Text(
                    "Skip",
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Center(
                child: Icon(
                  Icons.notifications_active_rounded,
                  size: 64,
                  color: Color(0xFF6366F1),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "Stay Updated in Real-Time",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "Grant background permissions to receive instant alerts when lectures are cancelled, rooms are changed, or assessments are approaching.",
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              if (_isChecking)
                const Center(child: CircularProgressIndicator())
              else ...[
                // Notification Permission Card
                _buildPermissionCard(
                  title: "Push Notifications",
                  description: "Receive alerts for timetable changes and assessment reminders.",
                  icon: Icons.notifications_none_rounded,
                  isGranted: _notificationGranted,
                  onPressed: _requestNotification,
                  buttonText: "Allow Notifications",
                ),
                const SizedBox(height: 16),
                // Battery Optimization Card (Android only)
                if (Platform.isAndroid) ...[
                  _buildPermissionCard(
                    title: "Unrestricted Battery Saver",
                    description: "Allows background sync to check for timetable updates reliably in the background.",
                    icon: Icons.battery_saver_rounded,
                    isGranted: _batteryGranted,
                    onPressed: _requestBatteryOptimization,
                    buttonText: "Disable Battery Saver",
                  ),
                  const SizedBox(height: 24),
                ],

                // Notification Preferences Selection Section
                const Text(
                  "NOTIFICATION ALERTS TO ENABLE",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 8),
                Opacity(
                  opacity: _notificationGranted ? 1.0 : 0.6,
                  child: Card(
                    color: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: Color(0xFF334155)),
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          activeColor: const Color(0xFF6366F1),
                          title: const Text("Cancellation Alerts", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: const Text("Notify if a lecture is cancelled", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                          secondary: Icon(Icons.notifications_active_rounded, color: _notificationGranted ? const Color(0xFF6366F1) : const Color(0xFF64748B), size: 20),
                          value: _notificationGranted && _cancellations,
                          onChanged: _notificationGranted ? (val) => setState(() => _cancellations = val) : null,
                        ),
                        const Divider(height: 1, color: Color(0xFF334155)),
                        SwitchListTile(
                          activeColor: const Color(0xFF6366F1),
                          title: const Text("Room Location Changes", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: const Text("Notify when a class moves rooms", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                          secondary: Icon(Icons.location_on_rounded, color: _notificationGranted ? const Color(0xFF6366F1) : const Color(0xFF64748B), size: 20),
                          value: _notificationGranted && _roomChanges,
                          onChanged: _notificationGranted ? (val) => setState(() => _roomChanges = val) : null,
                        ),
                        const Divider(height: 1, color: Color(0xFF334155)),
                        SwitchListTile(
                          activeColor: const Color(0xFF6366F1),
                          title: const Text("Reschedule Alerts", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: const Text("Notify when class times change", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                          secondary: Icon(Icons.access_time_filled_rounded, color: _notificationGranted ? const Color(0xFF6366F1) : const Color(0xFF64748B), size: 20),
                          value: _notificationGranted && _reschedules,
                          onChanged: _notificationGranted ? (val) => setState(() => _reschedules = val) : null,
                        ),
                        const Divider(height: 1, color: Color(0xFF334155)),
                        SwitchListTile(
                          activeColor: const Color(0xFF6366F1),
                          title: const Text("Assessment Reminders", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: const Text("Receive countdown reminders for assessments", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                          secondary: Icon(Icons.assignment_rounded, color: _notificationGranted ? const Color(0xFFF59E0B) : const Color(0xFF64748B), size: 20),
                          value: _notificationGranted && _assessmentReminders,
                          onChanged: _notificationGranted ? (val) => setState(() => _assessmentReminders = val) : null,
                        ),
                        if (!_notificationGranted)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: const BoxDecoration(
                              color: Color(0xFF1E1B4B),
                              borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.lock_rounded, color: Color(0xFFF59E0B), size: 14),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "Allow 'Push Notifications' above to enable these alert preferences.",
                                    style: TextStyle(color: Color(0xFFA5B4FC), fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: const BoxDecoration(
                              color: Color(0xFF0F172A),
                              borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
                            ),
                            child: const Text(
                              "ℹ️ You can change or customize all of these choices anytime later in Settings.",
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: canContinue ? _saveAndComplete : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canContinue ? const Color(0xFF6366F1) : const Color(0xFF334155),
                    disabledBackgroundColor: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: canContinue ? 4 : 0,
                  ),
                  child: Text(
                    "Continue to App",
                    style: TextStyle(
                      color: canContinue ? Colors.white : const Color(0xFF64748B),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionCard({
    required String title,
    required String description,
    required IconData icon,
    required bool isGranted,
    required VoidCallback onPressed,
    required String buttonText,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isGranted ? const Color(0xFF10B981).withValues(alpha: 0.5) : const Color(0xFF334155),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: isGranted ? const Color(0xFF10B981) : const Color(0xFF6366F1), size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isGranted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 14),
                      SizedBox(width: 4),
                      Text(
                        "Enabled",
                        style: TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 13,
            ),
          ),
          if (!isGranted) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: OutlinedButton(
                onPressed: onPressed,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF6366F1)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  buttonText,
                  style: const TextStyle(
                    color: Color(0xFF6366F1),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
