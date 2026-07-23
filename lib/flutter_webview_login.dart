import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
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
      "https://webtimetables.royalholloway.ac.uk/SWS/SDB2526SWS/Login.aspx";

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoadingPage = true;
                _errorMessage = null;
              });
            }
            _checkUrlForAuthenticatedSession(url);
          },
          onPageFinished: (String url) async {
            if (mounted) {
              setState(() {
                _isLoadingPage = false;
              });
            }
            await _checkUrlForAuthenticatedSession(url);
          },
          onWebResourceError: (WebResourceError error) {
            if (mounted) {
              setState(() {
                _isLoadingPage = false;
                _errorMessage = "Connection error: ${error.description}";
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_targetLoginUrl));
  }

  /// Checks if the user has completed login and landed on the authenticated portal
  Future<void> _checkUrlForAuthenticatedSession(String urlStr) async {
    final lowerUrl = urlStr.toLowerCase();

    if (lowerUrl.contains("default.aspx") ||
        (lowerUrl.contains("sws") && !lowerUrl.contains("login.aspx"))) {
      if (_isScraping) return;

      setState(() {
        _isScraping = true;
        _statusText = "Login Detected! Authenticating Session...";
      });

      try {
        // Extract session cookies via JavaScript document.cookie
        final rawCookie = await _controller.runJavaScriptReturningResult('document.cookie');
        var cookieStr = rawCookie.toString();
        if (cookieStr.startsWith('"') && cookieStr.endsWith('"')) {
          cookieStr = jsonDecode(cookieStr) as String;
        }

        final Map<String, String> sessionCookies = {};
        for (final pair in cookieStr.split(';')) {
          final parts = pair.split('=');
          if (parts.length >= 2) {
            final k = parts[0].trim();
            final v = parts.sublist(1).join('=').trim();
            if (k.isNotEmpty) {
              sessionCookies[k] = v;
            }
          }
        }

        setState(() {
          _statusText = "Fetching Timetable Events...";
        });

        // Use scraper to fetch schedule using session cookies
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
          WebViewWidget(controller: _controller),

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

          if (_isScraping)
            Container(
              color: activeTheme.scaffoldBackgroundColor.withValues(alpha: 0.95),
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
                        "Extracting session & building schedule...",
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
