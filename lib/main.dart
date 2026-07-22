import 'dart:io' show Platform, HttpOverrides, HttpClient, SecurityContext;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'flutter_timetable_model.dart';
import 'flutter_timetable_scraper.dart';
import 'flutter_auth_keystore.dart';

import 'flutter_background_sync.dart';
import 'flutter_permissions_screen.dart';

class DevHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    HttpOverrides.global = DevHttpOverrides();
  }
  final cacheManager = TimetableCacheManager();
  await cacheManager.init();

  if (!kIsWeb) {
    await TimetableBackgroundSyncEngine.initializeBackgroundSync();
  }

  runApp(const RHULTimetableApp());
}

class RHULTimetableApp extends StatelessWidget {
  const RHULTimetableApp({super.key});

  @override
  Widget build(BuildContext context) {
    final useIOSStyle = !kIsWeb && Platform.isIOS;

    return MaterialApp(
      title: 'RHUL Timetable',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: useIOSStyle ? CupertinoColors.black : const Color(0xFF0F172A),
        primaryColor: useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF6366F1),
        colorScheme: ColorScheme.dark(
          primary: useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF6366F1),
          surface: useIOSStyle ? const Color(0xFF1C1C1E) : const Color(0xFF1E293B),
        ),
      ),
      home: const MainAppWrapper(),
    );
  }
}

class MainAppWrapper extends StatefulWidget {
  const MainAppWrapper({super.key});

  @override
  State<MainAppWrapper> createState() => _MainAppWrapperState();
}

class _MainAppWrapperState extends State<MainAppWrapper> {
  final _secureStorage = SecureCredentialStorage();
  final _cacheManager = TimetableCacheManager();

  bool _isCheckingAuth = true;
  bool _isLoggedIn = false;
  bool _showPermissionsOnboarding = false;
  List<TimetableEvent> _events = [];
  StudentCredentials? _credentials;

  @override
  void initState() {
    super.initState();
    _checkInitialState();
  }

  Future<void> _checkInitialState() async {
    if (!kIsWeb) {
      try {
        final syncEngine = TimetableBackgroundSyncEngine();
        await syncEngine.requestPermissions();
      } catch (_) {}
    }

    final creds = await _secureStorage.getStudentCredentials();
    final cached = _cacheManager.getCachedEvents();

    if (creds != null) {
      final hasCompletedOnboarding = _cacheManager.hasCompletedPermissionsOnboarding();
      setState(() {
        _credentials = creds;
        _events = cached;
        _isLoggedIn = true;
        _showPermissionsOnboarding = !hasCompletedOnboarding;
        _isCheckingAuth = false;
      });

      _refreshTimetableSilently(creds);
    } else {
      setState(() {
        _isLoggedIn = false;
        _isCheckingAuth = false;
      });
    }
  }

  Future<void> _refreshTimetableSilently(StudentCredentials creds) async {
    try {
      final scraper = DirectDartTimetableScraper();
      final freshEvents = await scraper.scrapeTimetable(
        username: creds.username,
        password: creds.password,
      );

      if (mounted && freshEvents.isNotEmpty) {
        await _cacheManager.cacheEvents(freshEvents);
        setState(() {
          _events = freshEvents;
        });
      }
    } catch (_) {}
  }

  void _handleLoginSuccess(List<TimetableEvent> events, StudentCredentials creds) async {
    await _cacheManager.cacheEvents(events);
    final hasCompletedOnboarding = _cacheManager.hasCompletedPermissionsOnboarding();
    setState(() {
      _events = events;
      _credentials = creds;
      _isLoggedIn = true;
      _showPermissionsOnboarding = !hasCompletedOnboarding;
    });
  }

  Future<void> _completePermissionsOnboarding() async {
    await _cacheManager.setCompletedPermissionsOnboarding(true);
    setState(() {
      _showPermissionsOnboarding = false;
    });
  }

  Future<void> _handleLogout() async {
    final useIOSStyle = !kIsWeb && Platform.isIOS;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        if (useIOSStyle) {
          return CupertinoAlertDialog(
            title: const Text("Logout"),
            content: const Text("Are you sure you want to log out? Your encrypted security vault will be wiped."),
            actions: [
              CupertinoDialogAction(
                child: const Text("Cancel"),
                onPressed: () => Navigator.pop(ctx, false),
              ),
              CupertinoDialogAction(
                isDestructiveAction: true,
                child: const Text("Logout"),
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          );
        } else {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: const Text("Logout", style: TextStyle(color: Colors.white)),
            content: const Text(
              "Are you sure you want to log out? Your encrypted security vault will be wiped.",
              style: TextStyle(color: Color(0xFFCBD5E1)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Cancel", style: TextStyle(color: Color(0xFF94A3B8))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Logout", style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        }
      },
    );

    if (confirm == true) {
      await _secureStorage.wipeCredentials();
      await _cacheManager.clearCache();

      setState(() {
        _credentials = null;
        _events = [];
        _isLoggedIn = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final useIOSStyle = !kIsWeb && Platform.isIOS;

    if (_isCheckingAuth) {
      return Scaffold(
        body: Center(
          child: useIOSStyle
              ? const CupertinoActivityIndicator(radius: 16)
              : const CircularProgressIndicator(color: Color(0xFF6366F1)),
        ),
      );
    }

    if (!_isLoggedIn) {
      return StudentLoginScreen(onLoginSuccess: _handleLoginSuccess);
    }

    if (_showPermissionsOnboarding) {
      return OnboardingPermissionsScreen(onCompleted: _completePermissionsOnboarding);
    }

    return TimetableDashboardScreen(
      events: _events,
      credentials: _credentials,
      onLogout: _handleLogout,
      onRefresh: () => _credentials != null ? _refreshTimetableSilently(_credentials!) : Future.value(),
    );
  }
}

/// Dashboard Screen featuring Timetable Schedule with Interactive Calendar Navigation
class TimetableDashboardScreen extends StatefulWidget {
  final List<TimetableEvent> events;
  final StudentCredentials? credentials;
  final VoidCallback onLogout;
  final Future<void> Function() onRefresh;

  const TimetableDashboardScreen({
    super.key,
    required this.events,
    required this.credentials,
    required this.onLogout,
    required this.onRefresh,
  });

  @override
  State<TimetableDashboardScreen> createState() => _TimetableDashboardScreenState();
}

class _TimetableDashboardScreenState extends State<TimetableDashboardScreen> {
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _initializeInitialDate();
  }

  void _initializeInitialDate() {
    _selectedDate = DateTime.now();
  }

  void _jumpToToday() {
    setState(() {
      _selectedDate = DateTime.now();
    });
  }

  /// Opens platform native calendar date picker dialog
  Future<void> _openCalendarDatePicker() async {
    final useIOSStyle = !kIsWeb && Platform.isIOS;

    if (useIOSStyle) {
      showCupertinoModalPopup(
        context: context,
        builder: (ctx) => Container(
          height: 300,
          color: const Color(0xFF1C1C1E),
          child: Column(
            children: [
              Container(
                color: const Color(0xFF2C2C2E),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Select Date", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      child: const Text("Done"),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: _selectedDate,
                  minimumYear: 2024,
                  maximumYear: 2028,
                  onDateTimeChanged: (DateTime newDate) {
                    setState(() {
                      _selectedDate = newDate;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      final picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: DateTime(2024, 1, 1),
        lastDate: DateTime(2028, 12, 31),
        builder: (context, child) {
          return Theme(
            data: ThemeData.dark().copyWith(
              colorScheme: const ColorScheme.dark(
                primary: Color(0xFF6366F1),
                surface: Color(0xFF1E293B),
              ),
            ),
            child: child!,
          );
        },
      );
      if (picked != null) {
        setState(() {
          _selectedDate = picked;
        });
      }
    }
  }

  List<TimetableEvent> get _filteredEventsForDay {
    final year = _selectedDate.year.toString().padLeft(4, '0');
    final month = _selectedDate.month.toString().padLeft(2, '0');
    final day = _selectedDate.day.toString().padLeft(2, '0');
    final dateStr = '$year-$month-$day';

    return widget.events.where((e) => e.exactDate == dateStr).toList();
  }

  /// Checks if a given DateTime has any scheduled timetable events
  bool _hasEventsOnDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final dateStr = '$year-$month-$day';

    return widget.events.any((e) => e.exactDate == dateStr);
  }

  /// Returns the Monday of the week for a given date
  DateTime _getStartOfWeek(DateTime date) {
    return date.subtract(Duration(days: date.weekday - 1));
  }

  String _monthName(int month) {
    const months = [
      "January", "February", "March", "April", "May", "June",
      "July", "August", "September", "October", "November", "December"
    ];
    return months[month - 1];
  }

  String _weekdayShort(int weekday) {
    const days = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"];
    return days[weekday - 1];
  }

  String _getFormattedLastSyncTime() {
    final raw = TimetableCacheManager().getLastUpdatedTime();
    if (raw != null && raw.isNotEmpty) {
      final dt = DateTime.tryParse(raw)?.toLocal();
      if (dt != null) {
        final now = DateTime.now();
        final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
        final timeStr = "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
        if (isToday) {
          return "Synced Today, $timeStr";
        } else {
          const mn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
          return "Synced ${dt.day} ${mn[dt.month - 1]}, $timeStr";
        }
      }
    }
    return "Synced Recently";
  }

  int? _getAcademicWeekForSelectedDate() {
    final startOfWeek = _getStartOfWeek(_selectedDate);
    final endOfWeek = startOfWeek.add(const Duration(days: 6));

    for (final e in widget.events) {
      final dt = DateTime.tryParse(e.exactDate);
      if (dt != null) {
        if (!dt.isBefore(startOfWeek) && !dt.isAfter(endOfWeek)) {
          if (e.academicWeek > 0) {
            return e.academicWeek;
          }
        }
      }
    }

    final termStart = DateTime(2025, 9, 22);
    final diffDays = startOfWeek.difference(termStart).inDays;
    if (diffDays >= 0) {
      final wk = (diffDays ~/ 7) + 1;
      if (wk > 0 && wk <= 52) return wk;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final useIOSStyle = !kIsWeb && Platform.isIOS;
    final dayEvents = _filteredEventsForDay;
    final startOfWeek = _getStartOfWeek(_selectedDate);
    final academicWeek = _getAcademicWeekForSelectedDate();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: useIOSStyle ? const Color(0xFF1C1C1E) : const Color(0xFF1E293B),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "RHUL Timetable",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Text(
              _getFormattedLastSyncTime(),
              style: TextStyle(
                fontSize: 11,
                color: useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF818CF8),
              ),
            ),
          ],
        ),
      ),

      drawer: Drawer(
        backgroundColor: useIOSStyle ? const Color(0xFF1C1C1E) : const Color(0xFF1E293B),
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(
                color: useIOSStyle ? const Color(0xFF2C2C2E) : const Color(0xFF0F172A),
              ),
              currentAccountPicture: CircleAvatar(
                backgroundColor: useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF6366F1),
                child: Icon(
                  useIOSStyle ? CupertinoIcons.person_fill : Icons.person_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              accountName: Text(
                widget.credentials?.username ?? "Student User",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              accountEmail: Text(
                "Secured via ${PlatformSecurityInfo.storageEngineName}",
                style: TextStyle(
                  fontSize: 12,
                  color: useIOSStyle ? const Color(0xFF8E8E93) : const Color(0xFF94A3B8),
                ),
              ),
            ),
            ListTile(
              leading: Icon(
                useIOSStyle ? CupertinoIcons.calendar : Icons.calendar_month_rounded,
                color: useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF6366F1),
              ),
              title: const Text("My Schedule", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _jumpToToday();
              },
            ),
            ListTile(
              leading: Icon(
                useIOSStyle ? CupertinoIcons.doc_text : Icons.assignment_rounded,
                color: useIOSStyle ? const Color(0xFFFF9500) : const Color(0xFFF59E0B),
              ),
              title: const Text("My Assessments", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (ctx) => MyAssessmentsScreen(events: widget.events),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(
                useIOSStyle ? CupertinoIcons.gear : Icons.settings_rounded,
                color: useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF6366F1),
              ),
              title: const Text("Settings", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (ctx) => SettingsScreen(events: widget.events),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(
                useIOSStyle ? CupertinoIcons.arrow_clockwise : Icons.refresh_rounded,
                color: useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF6366F1),
              ),
              title: const Text("Sync Now", style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                await widget.onRefresh();
              },
            ),
            const Spacer(),
            const Divider(color: Color(0xFF334155)),

            ListTile(
              leading: const Icon(
                CupertinoIcons.power,
                color: Colors.redAccent,
              ),
              title: const Text(
                "Logout",
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
              ),
              onTap: () {
                Navigator.pop(context);
                widget.onLogout();
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),

      body: Column(
        children: [
          // Month Navigation Bar & Calendar Picker Trigger
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            color: useIOSStyle ? const Color(0xFF1C1C1E) : const Color(0xFF1E293B),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      icon: Icon(
                        useIOSStyle ? CupertinoIcons.chevron_left_circle_fill : Icons.arrow_back_ios_new_rounded,
                        size: 20,
                      ),
                      color: useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF6366F1),
                      tooltip: "Previous Week",
                      onPressed: () {
                        setState(() {
                          _selectedDate = _selectedDate.subtract(const Duration(days: 7));
                        });
                      },
                    ),
                    const SizedBox(width: 2),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      icon: Icon(
                        useIOSStyle ? CupertinoIcons.chevron_right_circle_fill : Icons.arrow_forward_ios_rounded,
                        size: 20,
                      ),
                      color: useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF6366F1),
                      tooltip: "Next Week",
                      onPressed: () {
                        setState(() {
                          _selectedDate = _selectedDate.add(const Duration(days: 7));
                        });
                      },
                    ),
                  ],
                ),
                // Tap Month Title to open full calendar
                Flexible(
                  child: GestureDetector(
                    onTap: _openCalendarDatePicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: (useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF6366F1)).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: (useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF6366F1)).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              "${_monthName(_selectedDate.month)} ${_selectedDate.year}",
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF818CF8),
                              ),
                            ),
                          ),
                          if (academicWeek != null) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: (useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF6366F1)).withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                "Wk $academicWeek",
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: useIOSStyle ? const Color(0xFF64D2FF) : const Color(0xFFA5B4FC),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 2),
                          Icon(
                            useIOSStyle ? CupertinoIcons.chevron_down : Icons.arrow_drop_down_rounded,
                            size: 16,
                            color: useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF818CF8),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  icon: Icon(
                    useIOSStyle ? CupertinoIcons.today : Icons.today_rounded,
                    size: 20,
                  ),
                  color: useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF818CF8),
                  tooltip: "Today",
                  onPressed: _jumpToToday,
                ),
              ],
            ),
          ),

          // Interactive Week Calendar Strip
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            color: useIOSStyle ? const Color(0xFF121214) : const Color(0xFF0F172A),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(7, (index) {
                final date = startOfWeek.add(Duration(days: index));
                final isSelected = date.year == _selectedDate.year &&
                    date.month == _selectedDate.month &&
                    date.day == _selectedDate.day;
                final isToday = date.year == DateTime.now().year &&
                    date.month == DateTime.now().month &&
                    date.day == DateTime.now().day;
                final hasEvents = _hasEventsOnDate(date);

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedDate = date;
                    });
                  },
                  child: Container(
                    width: 44,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF6366F1))
                          : (isToday ? const Color(0xFF1E293B) : Colors.transparent),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? Colors.transparent
                            : (isToday
                                ? (useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF6366F1))
                                : const Color(0xFF334155)),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _weekdayShort(date.weekday),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? Colors.white
                                : (isToday ? const Color(0xFF818CF8) : const Color(0xFF94A3B8)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "${date.day}",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Indicator dot for dates with classes
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hasEvents
                                ? (isSelected
                                    ? Colors.white
                                    : (useIOSStyle ? const Color(0xFF30D158) : const Color(0xFF34D399)))
                                : Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),

          const Divider(height: 1, color: Color(0xFF334155)),

          // Events List
          Expanded(
            child: RefreshIndicator(
              color: useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF6366F1),
              backgroundColor: useIOSStyle ? const Color(0xFF1C1C1E) : const Color(0xFF1E293B),
              onRefresh: widget.onRefresh,
              child: dayEvents.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.4,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  useIOSStyle ? CupertinoIcons.moon_stars : Icons.event_available_rounded,
                                  size: 48,
                                  color: const Color(0xFF64748B),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  "No classes scheduled for ${_weekdayShort(_selectedDate.weekday)}, ${_selectedDate.day} ${_monthName(_selectedDate.month)}.",
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: dayEvents.length,
                      itemBuilder: (context, index) {
                        final event = dayEvents[index];
                        return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        color: useIOSStyle ? const Color(0xFF1C1C1E) : const Color(0xFF1E293B),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(useIOSStyle ? 16 : 12),
                          side: BorderSide(
                            color: useIOSStyle ? const Color(0xFF2C2C2E) : const Color(0xFF334155),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      event.module,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: (useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF6366F1))
                                          .withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      event.type,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF818CF8),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    useIOSStyle ? CupertinoIcons.clock : Icons.access_time_rounded,
                                    size: 14,
                                    color: const Color(0xFF94A3B8),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    "${event.start} - ${event.finish}",
                                    style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
                                  ),
                                  const SizedBox(width: 16),
                                  Icon(
                                    useIOSStyle ? CupertinoIcons.location : Icons.location_on_rounded,
                                    size: 14,
                                    color: const Color(0xFF94A3B8),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    event.location,
                                    style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
                                  ),
                                ],
                              ),
                              if (event.staff.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(
                                      useIOSStyle ? CupertinoIcons.person : Icons.person_outline_rounded,
                                      size: 14,
                                      color: const Color(0xFF94A3B8),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      event.staff,
                                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Screen listing all university assessments in chronological order
class MyAssessmentsScreen extends StatelessWidget {
  final List<TimetableEvent> events;

  const MyAssessmentsScreen({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    final useIOSStyle = !kIsWeb && Platform.isIOS;

    final assessments = events.where((e) {
      final t = e.type.toLowerCase();
      return t.contains('assessment') || t.contains('exam') || t.contains('test');
    }).toList()
      ..sort((a, b) {
        final d = a.exactDate.compareTo(b.exactDate);
        return d != 0 ? d : a.start.compareTo(b.start);
      });

    return Scaffold(
      appBar: AppBar(
        backgroundColor: useIOSStyle ? const Color(0xFF1C1C1E) : const Color(0xFF1E293B),
        elevation: 0,
        title: const Text(
          "My Assessments",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: assessments.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    useIOSStyle ? CupertinoIcons.doc_text_search : Icons.assignment_turned_in_rounded,
                    size: 64,
                    color: const Color(0xFF64748B),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "No upcoming assessments found.",
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 16),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: assessments.length,
              itemBuilder: (context, index) {
                final item = assessments[index];
                final dt = DateTime.tryParse(item.exactDate);
                final isPast = dt != null && dt.isBefore(DateTime.now().subtract(const Duration(days: 1)));

                return Card(
                  margin: const EdgeInsets.only(bottom: 14),
                  color: useIOSStyle ? const Color(0xFF1C1C1E) : const Color(0xFF1E293B),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(useIOSStyle ? 16 : 12),
                    side: BorderSide(
                      color: isPast
                          ? const Color(0xFF334155)
                          : (useIOSStyle ? const Color(0xFFFF9500) : const Color(0xFFF59E0B)).withValues(alpha: 0.5),
                      width: isPast ? 1 : 1.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                item.module,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: (useIOSStyle ? const Color(0xFFFF9500) : const Color(0xFFF59E0B))
                                    .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                item.type,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: useIOSStyle ? const Color(0xFFFF9500) : const Color(0xFFF59E0B),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              useIOSStyle ? CupertinoIcons.calendar : Icons.calendar_today_rounded,
                              size: 14,
                              color: const Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "${item.day}, ${item.formattedDate}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            if (item.academicWeek > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF6366F1)).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  "Wk ${item.academicWeek}",
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: useIOSStyle ? const Color(0xFF64D2FF) : const Color(0xFFA5B4FC),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              useIOSStyle ? CupertinoIcons.clock : Icons.access_time_rounded,
                              size: 14,
                              color: const Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "${item.start} - ${item.finish}",
                              style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
                            ),
                            const SizedBox(width: 16),
                            Icon(
                              useIOSStyle ? CupertinoIcons.location : Icons.location_on_rounded,
                              size: 14,
                              color: const Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                item.location,
                                style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (item.staff.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                useIOSStyle ? CupertinoIcons.person : Icons.person_outline_rounded,
                                size: 14,
                                color: const Color(0xFF94A3B8),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                item.staff,
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Settings Screen allowing users to manage notification preferences and customizable assessment reminder intervals.
class SettingsScreen extends StatefulWidget {
  final List<TimetableEvent> events;

  const SettingsScreen({super.key, required this.events});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _cacheManager = TimetableCacheManager();

  bool _cancellations = true;
  bool _roomChanges = true;
  bool _reschedules = true;
  bool _assessmentReminders = true;
  List<int> _reminderHours = [1, 24];

  final List<Map<String, dynamic>> _availableIntervals = [
    {'label': '1 hour before', 'hours': 1},
    {'label': '3 hours before', 'hours': 3},
    {'label': '12 hours before', 'hours': 12},
    {'label': '1 day before', 'hours': 24},
    {'label': '2 days before', 'hours': 48},
    {'label': '1 week before', 'hours': 168},
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    final settings = _cacheManager.getNotificationSettings();
    setState(() {
      _cancellations = settings['cancellations'] as bool;
      _roomChanges = settings['roomChanges'] as bool;
      _reschedules = settings['reschedules'] as bool;
      _assessmentReminders = settings['assessmentReminders'] as bool;
      _reminderHours = (settings['reminderHours'] as List).cast<int>();
    });
  }

  Future<void> _saveSettings() async {
    await _cacheManager.saveNotificationSettings(
      cancellations: _cancellations,
      roomChanges: _roomChanges,
      reschedules: _reschedules,
      assessmentReminders: _assessmentReminders,
      reminderIntervalHours: _reminderHours,
    );

    if (_assessmentReminders && !kIsWeb) {
      try {
        final syncEngine = TimetableBackgroundSyncEngine();
        await syncEngine.scheduleAssessmentReminders(widget.events, _reminderHours);
      } catch (_) {}
    }
  }

  void _toggleInterval(int hours) {
    setState(() {
      if (_reminderHours.contains(hours)) {
        if (_reminderHours.length > 1) {
          _reminderHours.remove(hours);
        }
      } else {
        _reminderHours.add(hours);
        _reminderHours.sort();
      }
    });
    _saveSettings();
  }

  @override
  Widget build(BuildContext context) {
    final useIOSStyle = !kIsWeb && Platform.isIOS;
    final primaryColor = useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF6366F1);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: useIOSStyle ? const Color(0xFF1C1C1E) : const Color(0xFF1E293B),
        elevation: 0,
        title: const Text(
          "Settings",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Section Header: Notifications
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              "NOTIFICATION PREFERENCES",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
                color: useIOSStyle ? const Color(0xFF8E8E93) : const Color(0xFF94A3B8),
              ),
            ),
          ),

          Card(
            color: useIOSStyle ? const Color(0xFF1C1C1E) : const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: useIOSStyle ? const Color(0xFF2C2C2E) : const Color(0xFF334155),
              ),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  activeColor: primaryColor,
                  title: const Text("Cancellation Alerts", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: const Text("Notify if a lecture or assessment is cancelled", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  secondary: Icon(useIOSStyle ? CupertinoIcons.bell_fill : Icons.notifications_active_rounded, color: primaryColor),
                  value: _cancellations,
                  onChanged: (val) {
                    setState(() => _cancellations = val);
                    _saveSettings();
                  },
                ),
                const Divider(height: 1, color: Color(0xFF334155)),
                SwitchListTile(
                  activeColor: primaryColor,
                  title: const Text("Room Location Changes", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: const Text("Notify when a class moves to a different room", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  secondary: Icon(useIOSStyle ? CupertinoIcons.location : Icons.location_on_rounded, color: primaryColor),
                  value: _roomChanges,
                  onChanged: (val) {
                    setState(() => _roomChanges = val);
                    _saveSettings();
                  },
                ),
                const Divider(height: 1, color: Color(0xFF334155)),
                SwitchListTile(
                  activeColor: primaryColor,
                  title: const Text("Reschedule Alerts", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: const Text("Notify when a lecture or exam time changes", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  secondary: Icon(useIOSStyle ? CupertinoIcons.clock : Icons.access_time_filled_rounded, color: primaryColor),
                  value: _reschedules,
                  onChanged: (val) {
                    setState(() => _reschedules = val);
                    _saveSettings();
                  },
                ),
                const Divider(height: 1, color: Color(0xFF334155)),
                SwitchListTile(
                  activeColor: primaryColor,
                  title: const Text("Assessment Reminders", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: const Text("Receive countdown reminders for upcoming assessments", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  secondary: Icon(useIOSStyle ? CupertinoIcons.doc_text : Icons.assignment_rounded, color: const Color(0xFFF59E0B)),
                  value: _assessmentReminders,
                  onChanged: (val) {
                    setState(() => _assessmentReminders = val);
                    _saveSettings();
                  },
                ),
              ],
            ),
          ),

          if (_assessmentReminders) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                "ASSESSMENT REMINDER INTERVALS",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  color: useIOSStyle ? const Color(0xFF8E8E93) : const Color(0xFF94A3B8),
                ),
              ),
            ),
            Card(
              color: useIOSStyle ? const Color(0xFF1C1C1E) : const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: useIOSStyle ? const Color(0xFF2C2C2E) : const Color(0xFF334155),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _availableIntervals.map((item) {
                    final label = item['label'] as String;
                    final hours = item['hours'] as int;
                    final isSelected = _reminderHours.contains(hours);

                    return FilterChip(
                      selected: isSelected,
                      label: Text(label),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      selectedColor: primaryColor,
                      backgroundColor: useIOSStyle ? const Color(0xFF2C2C2E) : const Color(0xFF0F172A),
                      checkmarkColor: Colors.white,
                      onSelected: (_) => _toggleInterval(hours),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
