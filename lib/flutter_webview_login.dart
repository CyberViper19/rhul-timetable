import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'app_theme_config.dart';
import 'flutter_timetable_model.dart';
import 'flutter_timetable_scraper.dart';
import 'flutter_auth_keystore.dart';
import 'main.dart' show themeNotifier;

/// Embedded WebView Authentication Screen for Royal Holloway Timetables Portal
class LoginWebViewScreen extends StatefulWidget {
  final Function(List<TimetableEvent> events, StudentCredentials creds) onLoginSuccess;

  const LoginWebViewScreen({super.key, required this.onLoginSuccess});

  @override
  State<LoginWebViewScreen> createState() => _LoginWebViewScreenState();
}

class _LoginWebViewScreenState extends State<LoginWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoadingPage = true;
  bool _isScraping = false;
  String _statusText = "Loading Royal Holloway Portal...";
  String? _errorMessage;

  final String _targetLoginUrl =
      "https://webtimetables.royalholloway.ac.uk/";

  static const MethodChannel _cookieChannel =
      MethodChannel('com.example.rhul_timetable/cookies');

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
          "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36")
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final urlLower = request.url.toLowerCase();
            if (urlLower.contains("default.aspx") ||
                (urlLower.contains("sws") && !urlLower.contains("login.aspx"))) {
              // Intercept login redirect immediately so student does NOT enter portal website
              _interceptAndScrape(request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoadingPage = true;
                _errorMessage = null;
              });
            }
            final urlLower = url.toLowerCase();
            if (urlLower.contains("default.aspx") ||
                (urlLower.contains("sws") && !urlLower.contains("login.aspx"))) {
              _interceptAndScrape(url);
            }
          },
          onPageFinished: (String url) async {
            if (mounted) {
              setState(() {
                _isLoadingPage = false;
              });
            }
            final urlLower = url.toLowerCase();
            if (urlLower.contains("default.aspx") ||
                (urlLower.contains("sws") && !urlLower.contains("login.aspx"))) {
              await _interceptAndScrape(url);
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() {
                _isLoadingPage = false;
                _errorMessage = "Page error: ${error.description}";
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_targetLoginUrl));
  }

  /// Extracts native HttpOnly cookies and scrapes timetable
  Future<void> _interceptAndScrape(String currentUrl) async {
    if (_isScraping) return;

    setState(() {
      _isScraping = true;
      _statusText = "Login Detected! Extracting Session...";
    });

    try {
      final Map<String, String> sessionCookies = {};

      // 1. Attempt native CookieManager extraction (Android/iOS native)
      if (!kIsWeb && Platform.isAndroid) {
        try {
          final String? nativeCookiesStr = await _cookieChannel.invokeMethod<String>(
            'getCookies',
            {'url': currentUrl},
          );
          if (nativeCookiesStr != null && nativeCookiesStr.isNotEmpty) {
            for (final pair in nativeCookiesStr.split(';')) {
              final parts = pair.split('=');
              if (parts.length >= 2) {
                final k = parts[0].trim();
                final v = parts.sublist(1).join('=').trim();
                if (k.isNotEmpty) {
                  sessionCookies[k] = v;
                }
              }
            }
          }
        } catch (e) {
          debugPrint("Native cookie extraction error: $e");
        }
      }

      // 2. Fallback / supplementary document.cookie JS extraction
      try {
        final rawCookie = await _controller.runJavaScriptReturningResult('document.cookie');
        var jsCookieStr = rawCookie.toString();
        if (jsCookieStr.startsWith('"') && jsCookieStr.endsWith('"')) {
          jsCookieStr = jsonDecode(jsCookieStr) as String;
        }
        for (final pair in jsCookieStr.split(';')) {
          final parts = pair.split('=');
          if (parts.length >= 2) {
            final k = parts[0].trim();
            final v = parts.sublist(1).join('=').trim();
            if (k.isNotEmpty && !sessionCookies.containsKey(k)) {
              sessionCookies[k] = v;
            }
          }
        }
      } catch (e) {
        debugPrint("JS cookie extraction error: $e");
      }

      if (sessionCookies.isEmpty) {
        throw Exception("Could not retrieve session cookies. Please try logging in again.");
      }

      setState(() {
        _statusText = "Fetching Timetable Events...";
      });

      // Use scraper with extracted session cookies
      final scraper = DirectDartTimetableScraper();
      final events = await scraper.scrapeTimetableWithCookies(
        cookies: sessionCookies,
      );

      final dummyCreds = StudentCredentials(
        username: "RHUL Student",
        password: "",
      );

      final storage = SecureCredentialStorage();
      await storage.saveStudentCredentials(
        username: "RHUL Student",
        password: "",
        keepLoggedIn: true,
      );

      if (mounted) {
        widget.onLoginSuccess(events, dummyCreds);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScraping = false;
          _errorMessage = e.toString().replaceAll("Exception: ", "");
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final useIOSStyle = !kIsWeb && Platform.isIOS;
    final systemBrightness = MediaQuery.platformBrightnessOf(context);
    final activeTheme = AppThemeConfig.getTheme(themeNotifier.value, systemBrightness);

    return Scaffold(
      backgroundColor: activeTheme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: activeTheme.cardBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            useIOSStyle ? CupertinoIcons.back : Icons.arrow_back_rounded,
            color: activeTheme.textColor,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Royal Holloway Login",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: activeTheme.textColor,
              ),
            ),
            Text(
              "Official Web Timetables Portal",
              style: TextStyle(
                fontSize: 11,
                color: activeTheme.subtitleTextColor,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              useIOSStyle ? CupertinoIcons.refresh : Icons.refresh_rounded,
              color: activeTheme.primaryColor,
            ),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // WebView Widget
          WebViewWidget(controller: _controller),

          // Loading bar during page load
          if (_isLoadingPage && !_isScraping)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                backgroundColor: Colors.transparent,
                color: activeTheme.primaryColor,
                minHeight: 3,
              ),
            ),

          // Full-screen overlay immediately triggered on login to prevent website view
          if (_isScraping)
            Container(
              color: activeTheme.scaffoldBackgroundColor,
              width: double.infinity,
              height: double.infinity,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: activeTheme.cardBackgroundColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: activeTheme.borderColor),
                        ),
                        child: CircularProgressIndicator(
                          color: activeTheme.primaryColor,
                          strokeWidth: 3,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _statusText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: activeTheme.textColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Setting up your schedule...",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: activeTheme.subtitleTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Error Banner
          if (_errorMessage != null && !_isScraping)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                color: Colors.redAccent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 18),
                        onPressed: () => setState(() => _errorMessage = null),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
