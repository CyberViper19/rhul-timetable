import 'dart:io';
import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;

class DevHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}

String quotePlus(String s) {
  return Uri.encodeComponent(s)
      .replaceAll('*', '%2A')
      .replaceAll('!', '%21')
      .replaceAll('(', '%28')
      .replaceAll(')', '%29')
      .replaceAll("'", '%27')
      .replaceAll('%20', '+');
}

String encodeFormData(Map<String, String> data) {
  return data.entries.map((e) => '${quotePlus(e.key)}=${quotePlus(e.value)}').join('&');
}

final Map<String, String> _cookies = {};

void updateCookies(http.Response response) {
  final rawCookies = response.headers['set-cookie'];
  if (rawCookies != null && rawCookies.isNotEmpty) {
    final matches = RegExp(r'(?:^|,|\n)\s*([^=;\s]+)=([^;]*)').allMatches(rawCookies);
    for (final match in matches) {
      final key = match.group(1)?.trim();
      final value = match.group(2)?.trim();
      if (key != null && value != null && key.isNotEmpty) {
        final lowerKey = key.toLowerCase();
        if (!['expires', 'path', 'domain', 'samesite', 'httponly', 'secure', 'max-age'].contains(lowerKey)) {
          _cookies[key] = value;
        }
      }
    }
  }
}

String get cleanCookieHeader => _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

Map<String, String> get headers => {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'en-GB,en;q=0.9',
  if (_cookies.isNotEmpty) 'Cookie': cleanCookieHeader,
};

final _httpClient = http.Client();

Future<http.Response> doGet(String url) async {
  var uri = Uri.parse(url);
  for (int i = 0; i < 10; i++) {
    final res = await _httpClient.get(uri, headers: headers);
    updateCookies(res);
    if (res.statusCode == 301 || res.statusCode == 302) {
      final location = res.headers['location'] ?? '';
      uri = location.startsWith('http')
          ? Uri.parse(location)
          : Uri.parse('https://webtimetables.royalholloway.ac.uk$location');
      continue;
    }
    return res;
  }
  return await _httpClient.get(uri, headers: headers);
}

Future<http.Response> doPost(String url, Map<String, String> formData) async {
  final uri = Uri.parse(url);
  final res = await _httpClient.post(
    uri,
    headers: {...headers, 'Content-Type': 'application/x-www-form-urlencoded'},
    body: encodeFormData(formData),
  );
  updateCookies(res);
  if (res.statusCode == 301 || res.statusCode == 302) {
    final location = res.headers['location'] ?? '';
    final redirectUri = location.startsWith('http')
        ? location
        : 'https://webtimetables.royalholloway.ac.uk$location';
    return doGet(redirectUri);
  }
  return res;
}

Map<String, String> aspNetTokens(String htmlBody) {
  final doc = parse(htmlBody);
  return {
    '__VIEWSTATE': doc.querySelector('input[name="__VIEWSTATE"]')?.attributes['value'] ?? '',
    '__VIEWSTATEGENERATOR': doc.querySelector('input[name="__VIEWSTATEGENERATOR"]')?.attributes['value'] ?? '',
    '__EVENTVALIDATION': doc.querySelector('input[name="__EVENTVALIDATION"]')?.attributes['value'] ?? '',
  };
}

void main() async {
  HttpOverrides.global = DevHttpOverrides();

  const baseUrl = "https://webtimetables.royalholloway.ac.uk/SWS/SDB2526SWS";
  const loginUrl = "$baseUrl/Login.aspx";
  const defaultUrl = "$baseUrl/default.aspx";
  const username = "ZPAC516";
  const password = "Mancity2007**/";

  print("=== Step 1: GET Login.aspx ===");
  final loginPage = await doGet(loginUrl);
  print("Status: ${loginPage.statusCode}");
  final loginTokens = aspNetTokens(loginPage.body);

  print("=== Step 2: POST Login.aspx ===");
  final defaultPage = await doPost(loginUrl, {
    '__VIEWSTATE': loginTokens['__VIEWSTATE']!,
    '__VIEWSTATEGENERATOR': loginTokens['__VIEWSTATEGENERATOR']!,
    '__EVENTVALIDATION': loginTokens['__EVENTVALIDATION']!,
    'tUserName': username,
    'tPassword': password,
    'bLogin': 'Login',
  });
  print("Default status: ${defaultPage.statusCode}, Auth successful: ${defaultPage.body.contains('LinkBtn_studentMyTimetable')}");
  if (!defaultPage.body.contains('LinkBtn_studentMyTimetable')) {
    print("❌ Login failed!");
    return;
  }
  final defaultTokens = aspNetTokens(defaultPage.body);

  print("=== Step 3: Navigate to My Timetable ===");
  final ttNav1 = await doPost(defaultUrl, {
    '__EVENTTARGET': 'LinkBtn_studentMyTimetable',
    '__EVENTARGUMENT': '',
    '__VIEWSTATE': defaultTokens['__VIEWSTATE']!,
    '__VIEWSTATEGENERATOR': defaultTokens['__VIEWSTATEGENERATOR']!,
    '__EVENTVALIDATION': defaultTokens['__EVENTVALIDATION']!,
  });
  final userId = parse(ttNav1.body).querySelector('input[name="tUser"]')?.attributes['value'] ?? username;
  final ttTokens1 = aspNetTokens(ttNav1.body);

  const weeksString = "1;2;3;4;5;6;7;8;9;10;11;12;13;14;15;16;17;18;19;20;21;22;23;24;25;26;27;28;29;30;31;32;33;34;35;36;37;38;39;40;41;42;43;44;45;46;47;48;49;50;51;52";

  print("=== Step 4: POST TextSpreadsheet ===");
  final textPage = await doPost(defaultUrl, {
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
  print("Text report body length: ${textPage.body.length}");

  print("=== Step 5: POST Individual Grid ===");
  final ttNav2 = await doPost(defaultUrl, {
    '__EVENTTARGET': 'LinkBtn_studentMyTimetable',
    '__EVENTARGUMENT': '',
    '__VIEWSTATE': defaultTokens['__VIEWSTATE']!,
    '__VIEWSTATEGENERATOR': defaultTokens['__VIEWSTATEGENERATOR']!,
    '__EVENTVALIDATION': defaultTokens['__EVENTVALIDATION']!,
  });
  final ttTokens2 = aspNetTokens(ttNav2.body);

  final gridPage = await doPost(defaultUrl, {
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
  print("Grid report body length: ${gridPage.body.length}");

  // Test parsing
  final doc = parse(textPage.body);
  final body = doc.body!;
  final dayMap = {'Mon': 'Monday', 'Tue': 'Tuesday', 'Wed': 'Wednesday', 'Thu': 'Thursday', 'Fri': 'Friday'};

  int count = 0;
  String curDay = 'Monday';
  String curWks = '';
  final countsPerDay = <String, int>{};

  for (final elem in body.querySelectorAll('span, table')) {
    final cls = elem.attributes['class'] ?? '';
    if (cls.contains('labelone')) {
      final txt = elem.text.trim();
      if (dayMap.containsKey(txt)) curDay = dayMap[txt]!;
    } else if (cls.contains('labeltwo')) {
      curWks = elem.text.trim();
    } else if (elem.localName == 'table' && cls.contains('spreadsheet')) {
      final rows = elem.querySelectorAll('tr');
      for (final r in rows) {
        final cells = r.querySelectorAll('td, th').map((c) => c.text.trim()).toList();
        if (cells.length >= 5 && cells[0].isNotEmpty && cells[0] != 'Module') {
          final wksList = curWks.split(',').length; // simplified count
          count += 1;
          countsPerDay[curDay] = (countsPerDay[curDay] ?? 0) + 1;
        }
      }
    }
  }

  print("\n✅ Parsing successful!");
  print("Distinct timetable entries parsed across days: $count");
  print("Per-day breakdown: $countsPerDay");

  _httpClient.close();
}
