import 'dart:io' show Platform, HttpOverrides, HttpClient, SecurityContext;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'flutter_timetable_model.dart';
import 'flutter_timetable_scraper.dart';
import 'flutter_auth_keystore.dart';

import 'flutter_background_sync.dart';
import 'flutter_permissions_screen.dart';
import 'flutter_event_details_dialog.dart';
import 'package:permission_handler/permission_handler.dart';

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

/// Interactive Rotating Sync Icon Button
class _SyncIconButton extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final Color? color;

  const _SyncIconButton({required this.onRefresh, this.color});

  @override
  State<_SyncIconButton> createState() => _SyncIconButtonState();
}

class _SyncIconButtonState extends State<_SyncIconButton> with SingleTickerProviderStateMixin {
  bool _isSyncing = false;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleSync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    _animController.repeat();
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        _animController.stop();
        _animController.reset();
        setState(() => _isSyncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final useIOSStyle = !kIsWeb && Platform.isIOS;
    final buttonColor = widget.color ?? (useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF818CF8));

    return IconButton(
      icon: RotationTransition(
        turns: _animController,
        child: Icon(
          useIOSStyle ? CupertinoIcons.arrow_clockwise : Icons.refresh_rounded,
          size: 22,
        ),
      ),
      color: buttonColor,
      tooltip: _isSyncing ? "Syncing..." : "Sync Now",
      onPressed: _isSyncing ? null : _handleSync,
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
  static final DateTime _baseAnchorDate = DateTime(2025, 1, 1);
  late PageController _weekPageController;

  int _pageIndexFromDate(DateTime date) {
    final startOfTarget = _getStartOfWeek(date);
    final startOfBase = _getStartOfWeek(_baseAnchorDate);
    final days = startOfTarget.difference(startOfBase).inDays;
    return 10000 + (days / 7).round();
  }

  DateTime _dateFromPageIndex(int pageIndex) {
    final weeksDiff = pageIndex - 10000;
    return _getStartOfWeek(_baseAnchorDate).add(Duration(days: weeksDiff * 7));
  }

  @override
  void initState() {
    super.initState();
    _initializeInitialDate();
    _weekPageController = PageController(initialPage: _pageIndexFromDate(_selectedDate));
  }

  @override
  void dispose() {
    _weekPageController.dispose();
    super.dispose();
  }

  void _initializeInitialDate() {
    _selectedDate = DateTime.now();
  }

  void _updateSelectedDateAndPage(DateTime newDate) {
    setState(() {
      _selectedDate = newDate;
    });
    final targetPage = _pageIndexFromDate(newDate);
    if (_weekPageController.hasClients && _weekPageController.page?.round() != targetPage) {
      _weekPageController.animateToPage(
        targetPage,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _jumpToToday() {
    _updateSelectedDateAndPage(DateTime.now());
  }

  void _previousWeek() {
    _updateSelectedDateAndPage(_selectedDate.subtract(const Duration(days: 7)));
  }

  void _nextWeek() {
    _updateSelectedDateAndPage(_selectedDate.add(const Duration(days: 7)));
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
                    _updateSelectedDateAndPage(newDate);
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
        _updateSelectedDateAndPage(picked);
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

  Color _getEventTypeColor(String type, bool useIOSStyle) {
    final lower = type.toLowerCase();

    // Assessments / Exams -> Orange
    if (lower.contains('assessment') ||
        lower.contains('exam') ||
        lower.contains('test') ||
        lower.contains('quiz') ||
        lower.contains('coursework') ||
        lower.contains('assignment') ||
        lower.contains('submission') ||
        lower.contains('viva') ||
        lower.contains('presentation')) {
      return useIOSStyle ? const Color(0xFFFF9500) : const Color(0xFFF59E0B);
    }

    // Optional Attendance / Drop ins -> Green
    if (lower.contains('optional') ||
        lower.contains('drop') ||
        lower.contains('drop-in') ||
        lower.contains('dropin') ||
        lower.contains('office hour') ||
        lower.contains('consultation') ||
        lower.contains('support')) {
      return useIOSStyle ? const Color(0xFF34C759) : const Color(0xFF10B981);
    }

    // Default / Regular Classes -> Blue/Indigo
    return useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF818CF8);
  }

  void _showEventDetailsModal(BuildContext context, TimetableEvent event, Color typeColor) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EventDetailsModalSheet(event: event, typeColor: typeColor),
    );
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
        actions: [
          _SyncIconButton(onRefresh: widget.onRefresh),
          IconButton(
            icon: Icon(
              useIOSStyle ? CupertinoIcons.today : Icons.today_rounded,
              size: 22,
            ),
            color: useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF818CF8),
            tooltip: "Jump to Today",
            onPressed: _jumpToToday,
          ),
          const SizedBox(width: 4),
        ],
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
                    builder: (ctx) => MyAssessmentsScreen(
                      events: widget.events,
                      onRefresh: widget.onRefresh,
                    ),
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
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  icon: Icon(
                    useIOSStyle ? CupertinoIcons.chevron_left_circle_fill : Icons.arrow_back_ios_new_rounded,
                    size: 22,
                  ),
                  color: useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF6366F1),
                  tooltip: "Previous Week",
                  onPressed: _previousWeek,
                ),
                Flexible(
                  child: GestureDetector(
                    onTap: _openCalendarDatePicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                    useIOSStyle ? CupertinoIcons.chevron_right_circle_fill : Icons.arrow_forward_ios_rounded,
                    size: 22,
                  ),
                  color: useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF6366F1),
                  tooltip: "Next Week",
                  onPressed: _nextWeek,
                ),
              ],
            ),
          ),

          // Interactive Week Calendar Strip (Finger Scrollable & Swipeable)
          SizedBox(
            height: 78,
            child: PageView.builder(
              controller: _weekPageController,
              onPageChanged: (pageIndex) {
                final newWeekStart = _dateFromPageIndex(pageIndex);
                final currentWeekday = _selectedDate.weekday;
                final newSelectedDate = newWeekStart.add(Duration(days: currentWeekday - 1));
                setState(() {
                  _selectedDate = newSelectedDate;
                });
              },
              itemBuilder: (context, pageIndex) {
                final weekStart = _dateFromPageIndex(pageIndex);
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  color: useIOSStyle ? const Color(0xFF121214) : const Color(0xFF0F172A),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(7, (index) {
                      final date = weekStart.add(Duration(days: index));
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
                          padding: const EdgeInsets.symmetric(vertical: 6),
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
                            mainAxisAlignment: MainAxisAlignment.center,
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
                              const SizedBox(height: 3),
                              Text(
                                "${date.day}",
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? Colors.white : Colors.white,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Container(
                                width: 4,
                                height: 4,
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
                );
              },
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
                        final typeColor = _getEventTypeColor(event.type, useIOSStyle);

                        return GestureDetector(
                          onTap: () => _showEventDetailsModal(context, event, typeColor),
                          child: Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          color: useIOSStyle ? const Color(0xFF1C1C1E) : const Color(0xFF1E293B),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(useIOSStyle ? 16 : 12),
                            side: BorderSide(
                              color: useIOSStyle ? const Color(0xFF2C2C2E) : const Color(0xFF334155),
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  width: 5,
                                  color: typeColor,
                                ),
                                Expanded(
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
                                                color: typeColor.withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                event.type,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: typeColor,
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
                                ),
                              ],
                            ),
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

/// Screen listing all university assessments in chronological order with collapsible completed tab
class MyAssessmentsScreen extends StatefulWidget {
  final List<TimetableEvent> events;
  final Future<void> Function()? onRefresh;

  const MyAssessmentsScreen({super.key, required this.events, this.onRefresh});

  @override
  State<MyAssessmentsScreen> createState() => _MyAssessmentsScreenState();
}

class _MyAssessmentsScreenState extends State<MyAssessmentsScreen> {
  bool _isCompletedExpanded = false;

  bool _isEventCompleted(TimetableEvent item) {
    DateTime? endDateTime;
    final dt = DateTime.tryParse(item.exactDate);
    if (dt != null) {
      final parts = item.finish.split(':');
      if (parts.length == 2) {
        final hour = int.tryParse(parts[0]) ?? 23;
        final min = int.tryParse(parts[1]) ?? 59;
        endDateTime = DateTime(dt.year, dt.month, dt.day, hour, min);
      } else {
        endDateTime = DateTime(dt.year, dt.month, dt.day, 23, 59);
      }
    }
    return endDateTime != null ? endDateTime.isBefore(DateTime.now()) : false;
  }

  @override
  Widget build(BuildContext context) {
    final useIOSStyle = !kIsWeb && Platform.isIOS;

    final allAssessments = widget.events.where((e) {
      final t = e.type.toLowerCase();
      return t.contains('assessment') || t.contains('exam') || t.contains('test');
    }).toList()
      ..sort((a, b) {
        final d = a.exactDate.compareTo(b.exactDate);
        return d != 0 ? d : a.start.compareTo(b.start);
      });

    final upcoming = allAssessments.where((e) => !_isEventCompleted(e)).toList();
    final completed = allAssessments.where((e) => _isEventCompleted(e)).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: useIOSStyle ? const Color(0xFF1C1C1E) : const Color(0xFF1E293B),
        elevation: 0,
        title: const Text(
          "My Assessments",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          if (widget.onRefresh != null)
            _SyncIconButton(onRefresh: widget.onRefresh!),
          const SizedBox(width: 4),
        ],
      ),
      body: allAssessments.isEmpty
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
                    "No assessments found.",
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 16),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (upcoming.isEmpty && completed.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      "No upcoming assessments.",
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                    ),
                  ),

                ...upcoming.map((item) => _buildAssessmentCard(item, isCompleted: false, useIOSStyle: useIOSStyle)),

                if (completed.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Card(
                    color: useIOSStyle ? const Color(0xFF1C1C1E) : const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Color(0xFF334155)),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        setState(() {
                          _isCompletedExpanded = !_isCompletedExpanded;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              color: Color(0xFF10B981),
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "Completed Assessments (${completed.length})",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            Icon(
                              _isCompletedExpanded
                                  ? (useIOSStyle ? CupertinoIcons.chevron_up : Icons.keyboard_arrow_up_rounded)
                                  : (useIOSStyle ? CupertinoIcons.chevron_down : Icons.keyboard_arrow_down_rounded),
                              color: const Color(0xFF94A3B8),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.fastOutSlowIn,
                    child: _isCompletedExpanded
                        ? Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Column(
                              children: completed
                                  .map((item) => _buildAssessmentCard(item, isCompleted: true, useIOSStyle: useIOSStyle))
                                  .toList(),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildAssessmentCard(TimetableEvent item, {required bool isCompleted, required bool useIOSStyle}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      color: isCompleted
          ? (useIOSStyle ? const Color(0xFF141416) : const Color(0xFF151E2E))
          : (useIOSStyle ? const Color(0xFF1C1C1E) : const Color(0xFF1E293B)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(useIOSStyle ? 16 : 12),
        side: BorderSide(
          color: isCompleted
              ? const Color(0xFF334155).withValues(alpha: 0.5)
              : (useIOSStyle ? const Color(0xFFFF9500) : const Color(0xFFF59E0B)).withValues(alpha: 0.5),
          width: isCompleted ? 1 : 1.5,
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
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isCompleted ? const Color(0xFF94A3B8) : Colors.white,
                      decoration: isCompleted ? TextDecoration.lineThrough : TextDecoration.none,
                      decorationColor: const Color(0xFF94A3B8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (isCompleted)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 12),
                        SizedBox(width: 4),
                        Text(
                          "Completed",
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF10B981),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                else
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
                  color: isCompleted ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                ),
                const SizedBox(width: 6),
                Text(
                  "${item.day}, ${item.formattedDate}",
                  style: TextStyle(
                    color: isCompleted ? const Color(0xFF94A3B8) : Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    decoration: isCompleted ? TextDecoration.lineThrough : TextDecoration.none,
                  ),
                ),
                if (item.academicWeek > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF6366F1))
                          .withValues(alpha: isCompleted ? 0.1 : 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      "Wk ${item.academicWeek}",
                      style: TextStyle(
                        fontSize: 10,
                        color: isCompleted
                            ? const Color(0xFF64748B)
                            : (useIOSStyle ? const Color(0xFF64D2FF) : const Color(0xFFA5B4FC)),
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
                  color: isCompleted ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                ),
                const SizedBox(width: 6),
                Text(
                  "${item.start} - ${item.finish}",
                  style: TextStyle(
                    color: isCompleted ? const Color(0xFF64748B) : const Color(0xFFCBD5E1),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 16),
                Icon(
                  useIOSStyle ? CupertinoIcons.location : Icons.location_on_rounded,
                  size: 14,
                  color: isCompleted ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.location,
                    style: TextStyle(
                      color: isCompleted ? const Color(0xFF64748B) : const Color(0xFFCBD5E1),
                      fontSize: 13,
                    ),
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
  }
}

/// Settings Screen allowing users to manage notification preferences and customizable assessment reminder intervals.
class SettingsScreen extends StatefulWidget {
  final List<TimetableEvent> events;

  const SettingsScreen({super.key, required this.events});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  final _cacheManager = TimetableCacheManager();

  bool _cancellations = false;
  bool _roomChanges = false;
  bool _reschedules = false;
  bool _assessmentReminders = false;
  List<int> _reminderHours = [1, 24];

  bool _notificationGranted = false;
  bool _batteryGranted = false;

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
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _loadSystemPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadSystemPermissionsWithRetry();
    }
  }

  Future<void> _loadSystemPermissionsWithRetry() async {
    await _loadSystemPermissions();
    if (_batteryGranted) return;

    for (final delayMs in [400, 800, 1500]) {
      await Future.delayed(Duration(milliseconds: delayMs));
      if (!mounted || _batteryGranted) break;
      await _loadSystemPermissions();
    }
  }

  Future<void> _loadSystemPermissions() async {
    final notifStatus = await Permission.notification.status;
    bool batteryStatus = true;
    if (!kIsWeb && Platform.isAndroid) {
      final status = await Permission.ignoreBatteryOptimizations.status;
      batteryStatus = status.isGranted;
    }

    if (mounted) {
      setState(() {
        _notificationGranted = notifStatus.isGranted;
        _batteryGranted = batteryStatus;
      });
    }
  }

  void _ensureIntervalsExist(List<int> hoursList) {
    for (final h in hoursList) {
      if (!_availableIntervals.any((item) => item['hours'] == h)) {
        _availableIntervals.add({
          'label': _formatIntervalLabel(h),
          'hours': h,
        });
      }
    }
    _availableIntervals.sort((a, b) => (a['hours'] as int).compareTo(b['hours'] as int));
  }

  String _formatIntervalLabel(int hours) {
    if (hours % 168 == 0) {
      final w = hours ~/ 168;
      return "$w week${w > 1 ? 's' : ''} before";
    } else if (hours % 24 == 0) {
      final d = hours ~/ 24;
      return "$d day${d > 1 ? 's' : ''} before";
    } else {
      return "$hours hour${hours > 1 ? 's' : ''} before";
    }
  }

  void _loadSettings() {
    final settings = _cacheManager.getNotificationSettings();
    setState(() {
      _cancellations = settings['cancellations'] as bool;
      _roomChanges = settings['roomChanges'] as bool;
      _reschedules = settings['reschedules'] as bool;
      _assessmentReminders = settings['assessmentReminders'] as bool;
      _reminderHours = (settings['reminderHours'] as List).cast<int>();
      _ensureIntervalsExist(_reminderHours);
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
        _reminderHours.remove(hours);
        if (_reminderHours.isEmpty) {
          _assessmentReminders = false;
        }
      } else {
        _reminderHours.add(hours);
        _reminderHours.sort();
        _assessmentReminders = true;
      }
    });
    _saveSettings();
  }

  void _showAddCustomIntervalDialog() {
    final useIOSStyle = !kIsWeb && Platform.isIOS;
    final controller = TextEditingController();
    int selectedUnitHours = 1;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: useIOSStyle ? const Color(0xFF1C1C1E) : const Color(0xFF1E293B),
              title: const Text("Add Custom Reminder", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Remind me before assessment:", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: "e.g. 4",
                            hintStyle: const TextStyle(color: Color(0xFF64748B)),
                            filled: true,
                            fillColor: useIOSStyle ? const Color(0xFF2C2C2E) : const Color(0xFF0F172A),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<int>(
                        value: selectedUnitHours,
                        dropdownColor: useIOSStyle ? const Color(0xFF2C2C2E) : const Color(0xFF0F172A),
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text("Hours")),
                          DropdownMenuItem(value: 24, child: Text("Days")),
                          DropdownMenuItem(value: 168, child: Text("Weeks")),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() => selectedUnitHours = val);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: useIOSStyle ? const Color(0xFF0A84FF) : const Color(0xFF6366F1),
                  ),
                  onPressed: () {
                    final valText = controller.text.trim();
                    final numVal = int.tryParse(valText);
                    if (numVal != null && numVal > 0) {
                      final totalHours = numVal * selectedUnitHours;
                      setState(() {
                        if (!_reminderHours.contains(totalHours)) {
                          _reminderHours.add(totalHours);
                          _reminderHours.sort();
                        }
                        _ensureIntervalsExist([totalHours]);
                        _assessmentReminders = true;
                      });
                      _saveSettings();
                      Navigator.pop(context);
                    }
                  },
                  child: const Text("Add", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
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
                    setState(() {
                      _assessmentReminders = val;
                    });
                    _saveSettings();
                  },
                ),
                // Collapsible Assessment Reminder Intervals directly under Assessment Reminders tab
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.fastOutSlowIn,
                  child: _assessmentReminders
                      ? Container(
                          width: double.infinity,
                          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16, top: 4),
                          decoration: const BoxDecoration(
                            border: Border(top: BorderSide(color: Color(0xFF334155), width: 1)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 8),
                              Text(
                                "REMINDER INTERVALS",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                  color: useIOSStyle ? const Color(0xFF8E8E93) : const Color(0xFF94A3B8),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ..._availableIntervals.map((item) {
                                    final label = item['label'] as String;
                                    final hours = item['hours'] as int;
                                    final isSelected = _reminderHours.contains(hours);

                                    return FilterChip(
                                      selected: isSelected,
                                      label: Text(label),
                                      labelStyle: TextStyle(
                                        color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        fontSize: 12,
                                      ),
                                      selectedColor: primaryColor,
                                      backgroundColor: useIOSStyle ? const Color(0xFF2C2C2E) : const Color(0xFF0F172A),
                                      checkmarkColor: Colors.white,
                                      onSelected: (_) => _toggleInterval(hours),
                                    );
                                  }),
                                  ActionChip(
                                    avatar: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                                    label: const Text("Custom"),
                                    labelStyle: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                    backgroundColor: primaryColor.withValues(alpha: 0.35),
                                    onPressed: _showAddCustomIntervalDialog,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Section Header: System Permissions
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              "SYSTEM PERMISSIONS & BACKGROUND SYNC",
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
                ListTile(
                  leading: Icon(useIOSStyle ? CupertinoIcons.bell : Icons.notifications_none_rounded, color: primaryColor),
                  title: const Text("System Push Notifications", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    _notificationGranted ? "Permission Granted" : "Permission Denied (Notifications Disabled)",
                    style: TextStyle(color: _notificationGranted ? const Color(0xFF10B981) : const Color(0xFFEF4444), fontSize: 12),
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      if (_notificationGranted) {
                        await openAppSettings();
                      } else {
                        final res = await Permission.notification.request();
                        if (res.isPermanentlyDenied) {
                          await openAppSettings();
                        }
                      }
                      await _loadSystemPermissions();
                    },
                    child: Text(_notificationGranted ? "Manage" : "Enable", style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
                  ),
                ),
                if (!kIsWeb && Platform.isAndroid) ...[
                  const Divider(height: 1, color: Color(0xFF334155)),
                  ListTile(
                    leading: Icon(useIOSStyle ? CupertinoIcons.battery_charging : Icons.battery_saver_rounded, color: const Color(0xFF10B981)),
                    title: const Text("Unrestricted Battery Optimization", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      _batteryGranted ? "Unrestricted (Background Sync active)" : "Optimized (Sync may be delayed by OS)",
                      style: TextStyle(color: _batteryGranted ? const Color(0xFF10B981) : const Color(0xFFF59E0B), fontSize: 12),
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        if (_batteryGranted) {
                          await openAppSettings();
                        } else {
                          final res = await Permission.ignoreBatteryOptimizations.request();
                          if (res.isPermanentlyDenied) {
                            await openAppSettings();
                          }
                        }
                        await _loadSystemPermissions();
                      },
                      child: Text(_batteryGranted ? "Manage" : "Disable", style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
