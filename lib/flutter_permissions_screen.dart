import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:permission_handler/permission_handler.dart';
import 'flutter_timetable_model.dart';
import 'app_theme_config.dart';
import 'main.dart' show themeNotifier;

class OnboardingPermissionsScreen extends StatefulWidget {
  final VoidCallback onCompleted;

  const OnboardingPermissionsScreen({super.key, required this.onCompleted});

  @override
  State<OnboardingPermissionsScreen> createState() => _OnboardingPermissionsScreenState();
}

class _OnboardingPermissionsScreenState extends State<OnboardingPermissionsScreen> with WidgetsBindingObserver {
  int _currentStep = 0; // 0: Permissions & Alerts, 1: Theme Selection & Live Preview

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

  void _goToThemeStep() {
    setState(() {
      _currentStep = 1;
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
    final systemBrightness = MediaQuery.platformBrightnessOf(context);
    final selectedThemeKey = themeNotifier.value;
    final activeTheme = AppThemeConfig.getTheme(selectedThemeKey, systemBrightness);

    return Scaffold(
      backgroundColor: activeTheme.scaffoldBackgroundColor,
      body: SafeArea(
        child: _currentStep == 0
            ? _buildPermissionsStep(context, activeTheme)
            : _buildThemeSelectionStep(context, selectedThemeKey, systemBrightness, activeTheme),
      ),
    );
  }

  Widget _buildPermissionsStep(BuildContext context, AppThemeConfig activeTheme) {
    final canContinue = _allPermissionsGranted;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.topRight,
            child: TextButton(
              onPressed: _goToThemeStep,
              child: Text(
                "Skip",
                style: TextStyle(
                  color: activeTheme.subtitleTextColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Icon(
              Icons.notifications_active_rounded,
              size: 64,
              color: activeTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "Stay Updated in Real-Time",
            style: TextStyle(
              color: activeTheme.textColor,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Grant background permissions to receive instant alerts when lectures are cancelled, rooms are changed, or assessments are approaching.",
            style: TextStyle(
              color: activeTheme.subtitleTextColor,
              fontSize: 15,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          if (_isChecking)
            Center(child: CircularProgressIndicator(color: activeTheme.primaryColor))
          else ...[
            _buildPermissionCard(
              title: "Push Notifications",
              description: "Receive alerts for timetable changes and assessment reminders.",
              icon: Icons.notifications_none_rounded,
              isGranted: _notificationGranted,
              onPressed: _requestNotification,
              buttonText: "Allow Notifications",
              activeTheme: activeTheme,
            ),
            const SizedBox(height: 16),
            if (Platform.isAndroid) ...[
              _buildPermissionCard(
                title: "Unrestricted Battery Saver",
                description: "Allows background sync to check for timetable updates reliably in the background.",
                icon: Icons.battery_saver_rounded,
                isGranted: _batteryGranted,
                onPressed: _requestBatteryOptimization,
                buttonText: "Disable Battery Saver",
                activeTheme: activeTheme,
              ),
              const SizedBox(height: 24),
            ],
            Text(
              "NOTIFICATION ALERTS TO ENABLE",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
                color: activeTheme.subtitleTextColor,
              ),
            ),
            const SizedBox(height: 8),
            Opacity(
              opacity: _notificationGranted ? 1.0 : 0.6,
              child: Card(
                color: activeTheme.cardBackgroundColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: activeTheme.borderColor),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      activeColor: activeTheme.primaryColor,
                      title: Text("Cancellation Alerts", style: TextStyle(color: activeTheme.textColor, fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text("Notify if a lecture is cancelled", style: TextStyle(color: activeTheme.subtitleTextColor, fontSize: 12)),
                      secondary: Icon(Icons.notifications_active_rounded, color: _notificationGranted ? activeTheme.primaryColor : activeTheme.subtitleTextColor, size: 20),
                      value: _notificationGranted && _cancellations,
                      onChanged: _notificationGranted ? (val) => setState(() => _cancellations = val) : null,
                    ),
                    Divider(height: 1, color: activeTheme.borderColor),
                    SwitchListTile(
                      activeColor: activeTheme.primaryColor,
                      title: Text("Room Location Changes", style: TextStyle(color: activeTheme.textColor, fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text("Notify when a class moves rooms", style: TextStyle(color: activeTheme.subtitleTextColor, fontSize: 12)),
                      secondary: Icon(Icons.location_on_rounded, color: _notificationGranted ? activeTheme.primaryColor : activeTheme.subtitleTextColor, size: 20),
                      value: _notificationGranted && _roomChanges,
                      onChanged: _notificationGranted ? (val) => setState(() => _roomChanges = val) : null,
                    ),
                    Divider(height: 1, color: activeTheme.borderColor),
                    SwitchListTile(
                      activeColor: activeTheme.primaryColor,
                      title: Text("Reschedule Alerts", style: TextStyle(color: activeTheme.textColor, fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text("Notify when class times change", style: TextStyle(color: activeTheme.subtitleTextColor, fontSize: 12)),
                      secondary: Icon(Icons.access_time_filled_rounded, color: _notificationGranted ? activeTheme.primaryColor : activeTheme.subtitleTextColor, size: 20),
                      value: _notificationGranted && _reschedules,
                      onChanged: _notificationGranted ? (val) => setState(() => _reschedules = val) : null,
                    ),
                    Divider(height: 1, color: activeTheme.borderColor),
                    SwitchListTile(
                      activeColor: activeTheme.primaryColor,
                      title: Text("Assessment Reminders", style: TextStyle(color: activeTheme.textColor, fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text("Receive countdown reminders for assessments. You can choose your preferred reminder intervals (e.g. 1 hr, 1 day, 1 week before) anytime in Settings.", style: TextStyle(color: activeTheme.subtitleTextColor, fontSize: 12)),
                      secondary: Icon(Icons.assignment_rounded, color: _notificationGranted ? activeTheme.assessmentColor : activeTheme.subtitleTextColor, size: 20),
                      value: _notificationGranted && _assessmentReminders,
                      onChanged: _notificationGranted ? (val) => setState(() => _assessmentReminders = val) : null,
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
              onPressed: _goToThemeStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: activeTheme.primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 4,
              ),
              child: Text(
                "Next: Choose Theme",
                style: TextStyle(
                  color: activeTheme.buttonTextColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildThemeSelectionStep(BuildContext context, String currentThemeKey, Brightness systemBrightness, AppThemeConfig activeTheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => setState(() => _currentStep = 0),
                icon: Icon(Icons.arrow_back_rounded, color: activeTheme.textColor),
              ),
              TextButton(
                onPressed: _saveAndComplete,
                child: Text(
                  "Done",
                  style: TextStyle(
                    color: activeTheme.primaryColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Choose App Theme",
            style: TextStyle(
              color: activeTheme.textColor,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Select your preferred look & feel. You can change your theme anytime later in Settings.",
            style: TextStyle(
              color: activeTheme.subtitleTextColor,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),

          // Live Interactive App Preview Card
          Text(
            "LIVE PREVIEW",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              color: activeTheme.subtitleTextColor,
            ),
          ),
          const SizedBox(height: 8),
          _buildAppPreviewCard(currentThemeKey, systemBrightness),

          const SizedBox(height: 20),
          Text(
            "SELECT THEME",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              color: activeTheme.subtitleTextColor,
            ),
          ),
          const SizedBox(height: 8),

          // Theme Selection Cards
          Card(
            color: activeTheme.cardBackgroundColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: activeTheme.borderColor),
            ),
            child: Column(
              children: [
                _buildThemeOptionTile("RHUL Theme (Default)", "Royal Holloway Pitch Black & Orange", "rhul", activeTheme),
                Divider(height: 1, color: activeTheme.borderColor),
                _buildThemeOptionTile("Colourful", "Vibrant Indigo & Slate", "colourful", activeTheme),
                Divider(height: 1, color: activeTheme.borderColor),
                _buildThemeOptionTile("System Default", "Automatically match your phone's dark/light mode", "system", activeTheme),
                Divider(height: 1, color: activeTheme.borderColor),
                _buildThemeOptionTile("Dark Mode", "Monochrome Pitch Black & White", "dark", activeTheme),
                Divider(height: 1, color: activeTheme.borderColor),
                _buildThemeOptionTile("Light Mode", "Clean White & Slate", "light", activeTheme),
                if (!kIsWeb && Platform.isIOS) ...[
                  Divider(height: 1, color: activeTheme.borderColor),
                  _buildThemeOptionTile("iOS Default", "Original Apple Blue Theme", "ios_default", activeTheme),
                ],
              ],
            ),
          ),

          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _saveAndComplete,
              style: ElevatedButton.styleFrom(
                backgroundColor: activeTheme.primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 4,
              ),
              child: Text(
                "Finish Setup & Open App",
                style: TextStyle(
                  color: activeTheme.buttonTextColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildAppPreviewCard(String themeKey, Brightness systemBrightness) {
    final previewTheme = AppThemeConfig.getTheme(themeKey, systemBrightness);
    final isIOSStyle = !kIsWeb && Platform.isIOS;
    final pillColor = (previewTheme.key == 'dark')
        ? previewTheme.lectureColor
        : previewTheme.primaryColor;

    return Card(
      color: previewTheme.cardBackgroundColor,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: previewTheme.borderColor, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview Header Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: previewTheme.primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.school, size: 16, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "RHUL Timetable",
                      style: TextStyle(
                        color: previewTheme.textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Icon(
                      isIOSStyle ? CupertinoIcons.today : Icons.today_rounded,
                      size: 16,
                      color: previewTheme.secondaryColor,
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      isIOSStyle ? CupertinoIcons.arrow_clockwise : Icons.refresh_rounded,
                      size: 16,
                      color: previewTheme.secondaryColor,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Day Strip Preview
            Row(
              children: [
                Expanded(child: _buildPreviewDayPill("MON", "20", false, previewTheme, pillColor: pillColor)),
                const SizedBox(width: 6),
                Expanded(child: _buildPreviewDayPill("TUE", "21", true, previewTheme, pillColor: pillColor)),
                const SizedBox(width: 6),
                Expanded(child: _buildPreviewDayPill("WED", "22", false, previewTheme, pillColor: pillColor)),
              ],
            ),
            const SizedBox(height: 12),
            // Sample Lecture Card
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: previewTheme.containerBackgroundColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: previewTheme.borderColor),
              ),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 36,
                    decoration: BoxDecoration(
                      color: previewTheme.lectureColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "CS2850 Operating Systems",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: previewTheme.textColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "10:00 - 12:00 • Windsor Aud",
                          style: TextStyle(
                            fontSize: 11,
                            color: previewTheme.subtitleTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: previewTheme.lectureColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      "Lecture",
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: previewTheme.lectureColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewDayPill(String day, String num, bool isSelected, AppThemeConfig previewTheme, {required Color pillColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? pillColor : previewTheme.containerBackgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isSelected ? pillColor : previewTheme.borderColor),
      ),
      child: Column(
        children: [
          Text(
            day,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : previewTheme.subtitleTextColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            num,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : previewTheme.textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOptionTile(String title, String subtitle, String themeKey, AppThemeConfig activeTheme) {
    final isSelected = themeNotifier.value == themeKey;

    return ListTile(
      onTap: () async {
        await _cacheManager.setAppTheme(themeKey);
        themeNotifier.value = themeKey;
        setState(() {});
      },
      leading: _buildThemePreviewBadge(themeKey, isSelected),
      title: Text(
        title,
        style: TextStyle(
          color: activeTheme.textColor,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: activeTheme.subtitleTextColor,
          fontSize: 11,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check_circle_rounded, color: activeTheme.primaryColor)
          : null,
    );
  }

  Widget _buildThemePreviewBadge(String themeKey, bool isSelected) {
    switch (themeKey) {
      case 'rhul':
        return Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: Color(0xFFF97316),
            shape: BoxShape.circle,
          ),
          child: isSelected ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
        );
      case 'colourful':
        return Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: Color(0xFF6366F1),
            shape: BoxShape.circle,
          ),
          child: isSelected ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
        );
      case 'system':
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF64748B), width: 1.5),
            gradient: const LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFFF8FAFC)],
              stops: [0.5, 0.5],
            ),
          ),
          child: isSelected ? const Icon(Icons.check, size: 14, color: Color(0xFF6366F1)) : null,
        );
      case 'dark':
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.black,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF52525B), width: 1.5),
          ),
          child: isSelected ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
        );
      case 'light':
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
          ),
          child: isSelected ? const Icon(Icons.check, size: 14, color: Color(0xFF0F172A)) : null,
        );
      case 'ios_default':
      default:
        return Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: Color(0xFF0A84FF),
            shape: BoxShape.circle,
          ),
          child: isSelected ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
        );
    }
  }

  Widget _buildPermissionCard({
    required String title,
    required String description,
    required IconData icon,
    required bool isGranted,
    required VoidCallback onPressed,
    required String buttonText,
    required AppThemeConfig activeTheme,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: activeTheme.cardBackgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isGranted ? const Color(0xFF10B981).withValues(alpha: 0.5) : activeTheme.borderColor,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: isGranted ? const Color(0xFF10B981) : activeTheme.primaryColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: activeTheme.textColor,
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
            style: TextStyle(
              color: activeTheme.subtitleTextColor,
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
                  side: BorderSide(color: activeTheme.primaryColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  buttonText,
                  style: TextStyle(
                    color: activeTheme.primaryColor,
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
