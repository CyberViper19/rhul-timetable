import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart' show Element;
import 'package:http/http.dart' as http;
import 'flutter_timetable_model.dart';

/// Clean Dart implementation of Royal Holloway Timetable Portal Web Scraper.
class DirectDartTimetableScraper {
  final String baseUrl;
  final String localProxyUrl;
  final DateTime defaultTermStart;

  final Map<String, String> _cookies = {};
  late final http.Client _httpClient;

  DirectDartTimetableScraper({
    this.baseUrl = "https://webtimetables.royalholloway.ac.uk/SWS/SDB2526SWS",
    this.localProxyUrl = "http://localhost:7070/api/sync",
    DateTime? termStart,
  })  : defaultTermStart = termStart ?? DateTime(2025, 9, 22) {
    _httpClient = http.Client();
  }

  String get _loginUrl => "$baseUrl/Login.aspx";
  String get _defaultUrl => "$baseUrl/default.aspx";

  String get _cleanCookieHeader =>
      _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  Map<String, String> get _headers => {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-GB,en;q=0.9',
        if (_cookies.isNotEmpty) 'Cookie': _cleanCookieHeader,
      };

  void _updateCookies(http.Response response) {
    final rawCookies = response.headers['set-cookie'];
    if (rawCookies == null || rawCookies.isEmpty) return;
    final matches =
        RegExp(r'(?:^|,|\n)\s*([^=;\s]+)=([^;]*)').allMatches(rawCookies);
    for (final match in matches) {
      final key = match.group(1)?.trim();
      final value = match.group(2)?.trim();
      if (key != null && value != null && key.isNotEmpty) {
        final lowerKey = key.toLowerCase();
        if (!['expires', 'path', 'domain', 'samesite', 'httponly', 'secure', 'max-age']
            .contains(lowerKey)) {
          _cookies[key] = value;
        }
      }
    }
  }

  Future<http.Response> _get(String url) async {
    var uri = Uri.parse(url);
    for (int i = 0; i < 10; i++) {
      final res = await _httpClient.get(uri, headers: _headers);
      _updateCookies(res);
      if (res.statusCode == 301 || res.statusCode == 302) {
        final location = res.headers['location'] ?? '';
        uri = location.startsWith('http')
            ? Uri.parse(location)
            : Uri.parse('https://webtimetables.royalholloway.ac.uk$location');
        continue;
      }
      return res;
    }
    return await _httpClient.get(uri, headers: _headers);
  }

  Future<http.Response> _post(String url, Map<String, String> formData) async {
    final uri = Uri.parse(url);
    final res = await _httpClient.post(
      uri,
      headers: {..._headers, 'Content-Type': 'application/x-www-form-urlencoded'},
      body: _encodeFormData(formData),
    );
    _updateCookies(res);
    if (res.statusCode == 301 || res.statusCode == 302) {
      final location = res.headers['location'] ?? '';
      final redirectUri = location.startsWith('http')
          ? location
          : 'https://webtimetables.royalholloway.ac.uk$location';
      return _get(redirectUri);
    }
    return res;
  }

  String _quotePlus(String s) {
    return Uri.encodeComponent(s)
        .replaceAll('*', '%2A')
        .replaceAll('!', '%21')
        .replaceAll('(', '%28')
        .replaceAll(')', '%29')
        .replaceAll("'", '%27')
        .replaceAll('%20', '+');
  }

  String _encodeFormData(Map<String, String> data) {
    return data.entries
        .map((e) => '${_quotePlus(e.key)}=${_quotePlus(e.value)}')
        .join('&');
  }

  Map<String, String> _extractTokens(String htmlBody) {
    final doc = parse(htmlBody);
    return {
      '__VIEWSTATE':
          doc.querySelector('input[name="__VIEWSTATE"]')?.attributes['value'] ?? '',
      '__VIEWSTATEGENERATOR':
          doc.querySelector('input[name="__VIEWSTATEGENERATOR"]')?.attributes['value'] ?? '',
      '__EVENTVALIDATION':
          doc.querySelector('input[name="__EVENTVALIDATION"]')?.attributes['value'] ?? '',
    };
  }

  /// Scrapes timetable using pre-authenticated session cookies extracted from WebView login
  Future<List<TimetableEvent>> scrapeTimetableWithCookies({
    required Map<String, String> cookies,
    String? username,
  }) async {
    _cookies.clear();
    _cookies.addAll(cookies);

    // ── Step 1: GET default.aspx to confirm active session ─────────────────
    final defaultPage = await _get(_defaultUrl);
    if (!defaultPage.body.contains('LinkBtn_studentMyTimetable')) {
      throw Exception('Session expired or authentication invalid. Please log in again via portal.');
    }
    final defaultTokens = _extractTokens(defaultPage.body);

    // ── Step 2: Navigate to My Timetable ──────────────────────────────────
    final ttNav1 = await _post(_defaultUrl, {
      '__EVENTTARGET': 'LinkBtn_studentMyTimetable',
      '__EVENTARGUMENT': '',
      '__VIEWSTATE': defaultTokens['__VIEWSTATE']!,
      '__VIEWSTATEGENERATOR': defaultTokens['__VIEWSTATEGENERATOR']!,
      '__EVENTVALIDATION': defaultTokens['__EVENTVALIDATION']!,
    });

    final ttDoc1 = parse(ttNav1.body);
    final userId = (username != null && username.isNotEmpty)
        ? username
        : (ttDoc1.querySelector('input[name="tUser"]')?.attributes['value'] ?? '');
    final ttTokens1 = _extractTokens(ttNav1.body);

    const weeksString =
        "1;2;3;4;5;6;7;8;9;10;11;12;13;14;15;16;17;18;19;20;21;22;23;24;25;26;27;28;29;30;31;32;33;34;35;36;37;38;39;40;41;42;43;44;45;46;47;48;49;50;51;52";

    // ── Step 3: POST TextSpreadsheet report ────────────────────────────────
    final textPage = await _post(_defaultUrl, {
      '__VIEWSTATE': ttTokens1['__VIEWSTATE']!,
      '__VIEWSTATEGENERATOR': ttTokens1['__VIEWSTATEGENERATOR']!,
      '__EVENTVALIDATION': ttTokens1['__EVENTVALIDATION']!,
      'tUser': userId,
      'lbWeeks': weeksString,
      'lbDays': '1-5',
      'dlPeriod': '1-28',
      'RadioType': 'textspreadsheet;swsurl;swscustomts',
      'bGetTimetable': 'View Timetable',
    });

    // ── Step 4: POST Individual Grid report ────────────────────────────────
    final ttNav2 = await _post(_defaultUrl, {
      '__EVENTTARGET': 'LinkBtn_studentMyTimetable',
      '__EVENTARGUMENT': '',
      '__VIEWSTATE': defaultTokens['__VIEWSTATE']!,
      '__VIEWSTATEGENERATOR': defaultTokens['__VIEWSTATEGENERATOR']!,
      '__EVENTVALIDATION': defaultTokens['__EVENTVALIDATION']!,
    });
    final ttTokens2 = _extractTokens(ttNav2.body);

    final gridPage = await _post(_defaultUrl, {
      '__VIEWSTATE': ttTokens2['__VIEWSTATE']!,
      '__VIEWSTATEGENERATOR': ttTokens2['__VIEWSTATEGENERATOR']!,
      '__EVENTVALIDATION': ttTokens2['__EVENTVALIDATION']!,
      'tUser': userId,
      'lbWeeks': weeksString,
      'lbDays': '1-5',
      'dlPeriod': '1-28',
      'RadioType': 'individual;swsurl;swsurl',
      'bGetTimetable': 'View Timetable',
    });

    // ── Step 5: Parse & Combine ─────────────────────────────────────────────
    final events = _parseAndExpandTimetable(textPage.body, gridPage.body);

    if (events.isEmpty) {
      throw Exception('Authenticated successfully, but no timetable events were found.');
    }

    return events;
  }

  Future<List<TimetableEvent>> scrapeTimetable({
    required String username,
    required String password,
  }) async {
    if (kIsWeb) return _scrapeViaProxy(username, password);

    _cookies.clear();

    // ── Step 1: GET Login.aspx ──────────────────────────────────────────────
    final loginPage = await _get(_loginUrl);
    if (loginPage.statusCode != 200) {
      throw Exception('Could not connect to Royal Holloway portal (Status ${loginPage.statusCode}).');
    }
    final loginTokens = _extractTokens(loginPage.body);

    // ── Step 2: POST Login.aspx ─────────────────────────────────────────────
    final defaultPage = await _post(_loginUrl, {
      '__VIEWSTATE': loginTokens['__VIEWSTATE']!,
      '__VIEWSTATEGENERATOR': loginTokens['__VIEWSTATEGENERATOR']!,
      '__EVENTVALIDATION': loginTokens['__EVENTVALIDATION']!,
      'tUserName': username,
      'tPassword': password,
      'bLogin': 'Login',
    });

    if (!defaultPage.body.contains('LinkBtn_studentMyTimetable')) {
      throw Exception('Authentication failed. Please check your username and password.');
    }
    final defaultTokens = _extractTokens(defaultPage.body);

    // ── Step 3: Navigate to My Timetable ──────────────────────────────────
    final ttNav1 = await _post(_defaultUrl, {
      '__EVENTTARGET': 'LinkBtn_studentMyTimetable',
      '__EVENTARGUMENT': '',
      '__VIEWSTATE': defaultTokens['__VIEWSTATE']!,
      '__VIEWSTATEGENERATOR': defaultTokens['__VIEWSTATEGENERATOR']!,
      '__EVENTVALIDATION': defaultTokens['__EVENTVALIDATION']!,
    });

    final ttDoc1 = parse(ttNav1.body);
    final userId =
        ttDoc1.querySelector('input[name="tUser"]')?.attributes['value'] ?? username;
    final ttTokens1 = _extractTokens(ttNav1.body);

    const weeksString =
        "1;2;3;4;5;6;7;8;9;10;11;12;13;14;15;16;17;18;19;20;21;22;23;24;25;26;27;28;29;30;31;32;33;34;35;36;37;38;39;40;41;42;43;44;45;46;47;48;49;50;51;52";

    // ── Step 4: POST TextSpreadsheet report ────────────────────────────────
    final textPage = await _post(_defaultUrl, {
      '__VIEWSTATE': ttTokens1['__VIEWSTATE']!,
      '__VIEWSTATEGENERATOR': ttTokens1['__VIEWSTATEGENERATOR']!,
      '__EVENTVALIDATION': ttTokens1['__EVENTVALIDATION']!,
      'tUser': userId,
      'lbWeeks': weeksString,
      'lbDays': '1-5',
      'dlPeriod': '1-28',
      'RadioType': 'textspreadsheet;swsurl;swscustomts',
      'bGetTimetable': 'View Timetable',
    });

    // ── Step 5: POST Individual Grid report (for week→date mapping) ────────
    // Refresh tokens by re-navigating
    final ttNav2 = await _post(_defaultUrl, {
      '__EVENTTARGET': 'LinkBtn_studentMyTimetable',
      '__EVENTARGUMENT': '',
      '__VIEWSTATE': defaultTokens['__VIEWSTATE']!,
      '__VIEWSTATEGENERATOR': defaultTokens['__VIEWSTATEGENERATOR']!,
      '__EVENTVALIDATION': defaultTokens['__EVENTVALIDATION']!,
    });
    final ttTokens2 = _extractTokens(ttNav2.body);

    final gridPage = await _post(_defaultUrl, {
      '__VIEWSTATE': ttTokens2['__VIEWSTATE']!,
      '__VIEWSTATEGENERATOR': ttTokens2['__VIEWSTATEGENERATOR']!,
      '__EVENTVALIDATION': ttTokens2['__EVENTVALIDATION']!,
      'tUser': userId,
      'lbWeeks': weeksString,
      'lbDays': '1-5',
      'dlPeriod': '1-28',
      'RadioType': 'individual;swsurl;swsurl',
      'bGetTimetable': 'View Timetable',
    });

    // ── Step 6: Parse & Combine ─────────────────────────────────────────────
    final events = _parseAndExpandTimetable(textPage.body, gridPage.body);

    if (events.isEmpty) {
      throw Exception('Authenticated successfully, but no timetable events were found for \'$username\'.');
    }

    return events;
  }

  // ── Parsing Logic ────────────────────────────────────────────────────────

  Map<int, DateTime> _extractWeekDateMapFromGrid(String htmlGrid) {
    final doc = parse(htmlGrid);
    final allTables = doc.querySelectorAll('table');
    final h2 = allTables
        .where((t) => (t.attributes['class'] ?? '').contains('header-2-args'))
        .toList();
    final gb = allTables
        .where((t) => (t.attributes['class'] ?? '').contains('grid-border-args'))
        .toList();

    final Map<int, DateTime> weekToMonday = {};

    for (int i = 0; i < h2.length && i < gb.length; i++) {
      final weeksText = h2[i].text.trim().replaceFirst(RegExp(r'[Ww]eeks?[:\s]*'), '');
      final weeks = _parseWeekString(weeksText);
      if (weeks.isEmpty) continue;

      final rows = gb[i].querySelectorAll('tr');
      if (rows.length < 2) continue;
      final row1 = rows[1].querySelectorAll('td, th').map((c) => c.text.trim()).toList();
      if (row1.length < 2) continue;

      final dateStr = row1[1].split('-')[0].trim();
      final firstDate = _parseDateStr(dateStr);
      if (firstDate == null) continue;

      final firstWk = weeks[0];
      for (final w in weeks) {
        weekToMonday[w] = firstDate.add(Duration(days: (w - firstWk) * 7));
      }
    }
    return weekToMonday;
  }

  DateTime? _parseDateStr(String s) {
    final parts = s.trim().split('/');
    if (parts.length != 3) return null;
    try {
      final d = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      var y = int.parse(parts[2]);
      if (y < 100) y += 2000;
      return DateTime(y, m, d);
    } catch (_) {
      return null;
    }
  }

  List<int> _parseWeekString(String wStr) {
    final cleaned = wStr.replaceAll(RegExp(r'[Ww]eeks?[:\s]*'), '').trim();
    final Set<int> weeks = {};
    for (final p in cleaned.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty)) {
      if (p.contains('-')) {
        final sub = p.split('-').map((x) => int.tryParse(x.trim())).whereType<int>().toList();
        if (sub.length == 2) {
          for (var w = sub[0]; w <= sub[1]; w++) weeks.add(w);
        }
      } else {
        final w = int.tryParse(p);
        if (w != null) weeks.add(w);
      }
    }
    return weeks.toList()..sort();
  }

  List<TimetableEvent> _parseAndExpandTimetable(String textHtml, String gridHtml) {
    final weekToMonday = _extractWeekDateMapFromGrid(gridHtml);

    final dayMap = {
      'Mon': 'Monday',
      'Tue': 'Tuesday',
      'Wed': 'Wednesday',
      'Thu': 'Thursday',
      'Fri': 'Friday',
    };
    final dayOffsets = {
      'Monday': 0,
      'Tuesday': 1,
      'Wednesday': 2,
      'Thursday': 3,
      'Friday': 4,
    };

    final doc = parse(textHtml);
    final body = doc.body;
    if (body == null) return [];

    String currentDay = 'Monday';
    String currentWeeksStr = '';

    final Map<String, List<Map<String, dynamic>>> groupedBySlot = {};

    // Document-order traversal over labelone, labeltwo, and spreadsheet tables
    for (final elem in body.querySelectorAll('span, table')) {
      final cls = elem.attributes['class'] ?? '';

      if (cls.contains('labelone')) {
        final txt = elem.text.trim();
        if (dayMap.containsKey(txt)) {
          currentDay = dayMap[txt]!;
        }
      } else if (cls.contains('labeltwo')) {
        currentWeeksStr = elem.text.trim();
      } else if (elem.localName == 'table' && cls.contains('spreadsheet')) {
        final weeks = _parseWeekString(currentWeeksStr);
        final dayOffset = dayOffsets[currentDay] ?? 0;

        final rows = elem.querySelectorAll('tr');
        for (final r in rows) {
          final cells = r.querySelectorAll('td, th').map((c) => c.text.trim()).toList();
          if (cells.length >= 5 && cells[0].isNotEmpty && cells[0] != 'Module') {
            final module = cells[0];
            final type = cells[1];
            var start = cells[2];
            var finish = cells[3];
            if (RegExp(r'^\d:\d{2}$').hasMatch(start)) start = '0$start';
            if (RegExp(r'^\d:\d{2}$').hasMatch(finish)) finish = '0$finish';

            var location = cells[4];
            if (location.trim().isEmpty) {
              location = 'Online';
            }
            final size = cells.length > 5 ? cells[5] : '';
            final staff = cells.length > 6 ? cells[6] : '';

            for (final wk in weeks) {
              final monday = weekToMonday[wk] ??
                  defaultTermStart.add(Duration(days: (wk - 1) * 7));
              final eventDate = monday.add(Duration(days: dayOffset));

              // Skip weekends
              if (eventDate.weekday >= 6) continue;

              final exactStr =
                  '${eventDate.year.toString().padLeft(4, '0')}-${eventDate.month.toString().padLeft(2, '0')}-${eventDate.day.toString().padLeft(2, '0')}';

              final slotKey = '${currentDay}_${exactStr}_${start}_${finish}_${type}_$location';

              groupedBySlot.putIfAbsent(slotKey, () => []);
              groupedBySlot[slotKey]!.add({
                'day': currentDay,
                'exactDate': exactStr,
                'formattedDate': _formatDateFull(eventDate),
                'academicWeek': wk,
                'monday': monday,
                'module': module,
                'type': type,
                'start': start,
                'finish': finish,
                'location': location,
                'size': size,
                'staff': staff,
              });
            }
          }
        }
      }
    }

    final List<TimetableEvent> events = [];

    groupedBySlot.forEach((slotKey, items) {
      if (items.isEmpty) return;

      final first = items.first;
      final currentDay = first['day'] as String;
      final exactStr = first['exactDate'] as String;
      final formattedDate = first['formattedDate'] as String;
      final wk = first['academicWeek'] as int;
      final monday = first['monday'] as DateTime;
      final type = first['type'] as String;
      final start = first['start'] as String;
      final finish = first['finish'] as String;
      final location = first['location'] as String;

      final List<String> codes = [];
      final Set<String> titles = {};
      final Set<String> staffs = {};
      final Set<String> sizes = {};

      for (final item in items) {
        final modStr = item['module'] as String;
        final parts = _parseModuleParts(modStr);
        final code = parts['code']!;
        final title = parts['title']!;

        if (code.isNotEmpty && !codes.contains(code)) {
          codes.add(code);
        }
        if (title.isNotEmpty) {
          titles.add(title);
        }
        if ((item['staff'] as String).isNotEmpty) {
          staffs.add(item['staff'] as String);
        }
        if ((item['size'] as String).isNotEmpty) {
          sizes.add(item['size'] as String);
        }
      }

      codes.sort();
      final codesStr = codes.join('/');
      final sortedTitles = titles.toList()..sort();
      final titleStr = sortedTitles.join(' / ');

      final combinedModule = titleStr.isNotEmpty
          ? (codesStr.isNotEmpty ? '$codesStr | $titleStr' : titleStr)
          : codesStr;

      final sortedStaff = staffs.toList()..sort();
      final combinedStaff = sortedStaff.join(', ');
      final combinedSize = sizes.isNotEmpty ? sizes.reduce((a, b) => a.length >= b.length ? a : b) : '';

      final weekEnd = monday.add(const Duration(days: 4));
      final dateRange = '${_formatDateShort(monday)} - ${_formatDateShort(weekEnd)}';

      events.add(TimetableEvent.fromJson({
        'id': '${currentDay.toLowerCase().substring(0, 3)}_${exactStr}_${start.replaceAll(':', '')}_${finish.replaceAll(':', '')}',
        'Day': currentDay,
        'DateRange': dateRange,
        'ExactDate': exactStr,
        'FormattedDate': formattedDate,
        'AcademicWeek': wk,
        'Module': combinedModule,
        'Type': type,
        'Start': start,
        'Finish': finish,
        'Location': location,
        'Size': combinedSize,
        'Staff': combinedStaff,
      }));
    });

    events.sort((a, b) {
      final d = a.exactDate.compareTo(b.exactDate);
      return d != 0 ? d : a.start.compareTo(b.start);
    });

    return events;
  }

  Map<String, String> _parseModuleParts(String moduleStr) {
    if (moduleStr.contains('|')) {
      final p = moduleStr.split('|');
      return {'code': p[0].trim(), 'title': p.sublist(1).join('|').trim()};
    } else if (moduleStr.contains(' ')) {
      final p = moduleStr.split(' ');
      return {'code': p[0].trim(), 'title': p.sublist(1).join(' ').trim()};
    }
    return {'code': moduleStr.trim(), 'title': ''};
  }

  String _formatDateShort(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _formatDateFull(DateTime d) {
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const mn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${wd[d.weekday - 1]}, ${d.day.toString().padLeft(2, '0')} ${mn[d.month - 1]} ${d.year}';
  }

  Future<List<TimetableEvent>> _scrapeViaProxy(String username, String password) async {
    final response = await _httpClient.post(
      Uri.parse(localProxyUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);
      if (data['success'] == true && data['events'] is List) {
        return (data['events'] as List)
            .map((e) => TimetableEvent.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      throw Exception(data['error'] ?? 'Failed to authenticate with RHUL portal.');
    }

    final Map<String, dynamic> data = jsonDecode(response.body);
    throw Exception(data['error'] ?? 'Invalid username or password.');
  }
}
