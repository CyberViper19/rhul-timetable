import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'flutter_timetable_model.dart';
import 'app_theme_config.dart';
import 'main.dart' show themeNotifier;

class RHULBuildingInfo {
  final String canonicalName;

  const RHULBuildingInfo(this.canonicalName);
}

class EventDetailsModalSheet extends StatefulWidget {
  final TimetableEvent event;
  final Color typeColor;

  const EventDetailsModalSheet({
    super.key,
    required this.event,
    required this.typeColor,
  });

  @override
  State<EventDetailsModalSheet> createState() => _EventDetailsModalSheetState();
}

class _EventDetailsModalSheetState extends State<EventDetailsModalSheet> {
  WebViewController? _webViewController;
  bool _isLoadingMap = true;

  @override
  void initState() {
    super.initState();
    themeNotifier.addListener(_onThemeChanged);
    if (!_isOnline) {
      _initMapWebView();
    }
  }

  @override
  void dispose() {
    themeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  bool get _isOnline => widget.event.location.toLowerCase().contains('online');

  RHULBuildingInfo _resolveRHULBuilding(String location) {
    final loc = location.toLowerCase();

    // 1. Founder's Building
    if (loc.contains('founder') || loc.contains('fndr') || loc.contains('fnd') || loc.contains('picture') || loc.contains('crossland') || loc.contains('boiler')) {
      return const RHULBuildingInfo("Founder's Building");
    }
    // 2. Emily Wilding Davison Building
    if (loc.contains('davison') || loc.contains('ewd') || loc.contains('library')) {
      return const RHULBuildingInfo("Emily Wilding Davison Building");
    }
    // 3. Moore Building
    if (loc.contains('moore') || loc.contains('mr') || loc.startsWith('mr-')) {
      return const RHULBuildingInfo("Moore Building");
    }
    // 4. International Building
    if (loc.contains('international') || loc.contains('inter') || loc.contains('intl') || loc.contains('ib')) {
      return const RHULBuildingInfo("International Building");
    }
    // 5. Bedford Building
    if (loc.contains('bedford') || loc.contains('bed')) {
      return const RHULBuildingInfo("Bedford Building");
    }
    // 6. Wolfson Building
    if (loc.contains('wolfson') || loc.contains('wolf')) {
      return const RHULBuildingInfo("Wolfson Building");
    }
    // 7. McCrea Building
    if (loc.contains('mccrea') || loc.contains('mc') || loc.contains('mcc')) {
      return const RHULBuildingInfo("McCrea Building");
    }
    // 8. Katherine Worth Building
    if (loc.contains('katherine') || loc.contains('worth') || loc.contains('kw')) {
      return const RHULBuildingInfo("Katherine Worth Building");
    }
    // 9. Arts Building
    if (loc.contains('arts') || loc.contains('art') || loc.startsWith('a-')) {
      return const RHULBuildingInfo("Arts Building");
    }
    // 10. Windsor Building
    if (loc.contains('windsor') || loc.contains('win') || loc.contains('aud')) {
      return const RHULBuildingInfo("Windsor Building");
    }
    // 11. Bourne Building
    if (loc.contains('bourne') || loc.contains('brn') || loc.contains('blt')) {
      return const RHULBuildingInfo("Bourne Building");
    }
    // 12. Munro Fox Building
    if (loc.contains('munro') || loc.contains('fox') || loc.contains('mf')) {
      return const RHULBuildingInfo("Munro Fox Building");
    }
    // 13. Beatrice Schilling Building
    if (loc.contains('schilling') || loc.contains('beatrice') || loc.contains('shil') || loc.startsWith('sh')) {
      return const RHULBuildingInfo("Beatrice Schilling Building");
    }
    // 14. Horton Building
    if (loc.contains('horton') || loc.contains('hort')) {
      return const RHULBuildingInfo("Horton Building");
    }
    // 15. Tolansky Building
    if (loc.contains('tolansky') || loc.contains('tol')) {
      return const RHULBuildingInfo("Tolansky Building");
    }
    // 16. Queen's Building
    if (loc.contains('queen') || loc.contains('qns') || loc.contains('qn')) {
      return const RHULBuildingInfo("Queen's Building");
    }
    // 17. Wetton's Terrace
    if (loc.contains('wetton') || loc.contains('wet')) {
      return const RHULBuildingInfo("Wetton's Terrace");
    }

    // Fallback: Default RHUL Building
    final cleanName = location.split('-').first.trim();
    return RHULBuildingInfo("$cleanName Building");
  }

  void _initMapWebView() {
    final building = _resolveRHULBuilding(widget.event.location);
    final String query = "${building.canonicalName} egham";
    final String mapsEmbedUrl = "https://maps.google.com/maps?q=${Uri.encodeComponent(query)}&t=&z=17&ie=UTF8&iwloc=&output=embed";

    final htmlContent = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    body, html { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background-color: #121212; }
    iframe { width: 100%; height: 100%; border: 0; pointer-events: none; }
  </style>
</head>
<body>
  <iframe src="$mapsEmbedUrl" loading="lazy" allowfullscreen></iframe>
</body>
</html>
''';

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF121212))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _isLoadingMap = false);
            }
          },
        ),
      )
      ..loadHtmlString(htmlContent);

    _webViewController = controller;
  }

  Future<void> _launchGoogleMaps(BuildContext context) async {
    if (_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("This is an online lecture. No physical map location required."),
          backgroundColor: Color(0xFF6366F1),
        ),
      );
      return;
    }

    final building = _resolveRHULBuilding(widget.event.location);
    final String query = "${building.canonicalName} egham";
    final Uri googleMapsUrl = Uri.parse("https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}");

    try {
      final launched = await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      try {
        await launchUrl(googleMapsUrl, mode: LaunchMode.inAppWebView);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Could not launch maps: $e")),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final useIOSStyle = !kIsWeb && Platform.isIOS;
    final systemBrightness = MediaQuery.platformBrightnessOf(context);
    final activeTheme = AppThemeConfig.getTheme(themeNotifier.value, systemBrightness);
    final building = _resolveRHULBuilding(widget.event.location);

    return Container(
      decoration: BoxDecoration(
        color: activeTheme.cardBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag Handle Indicator
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: activeTheme.subtitleTextColor.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Module Title & Type Pill
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      widget.event.module,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: activeTheme.textColor,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: widget.typeColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: widget.typeColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      widget.event.type,
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.typeColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Details Grid Cards
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: activeTheme.containerBackgroundColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: activeTheme.borderColor),
                ),
                child: Column(
                  children: [
                    _buildDetailRow(
                      icon: useIOSStyle ? CupertinoIcons.calendar : Icons.calendar_today_rounded,
                      title: "Date",
                      value: "${widget.event.day}, ${widget.event.formattedDate}${widget.event.academicWeek > 0 ? ' (Week ${widget.event.academicWeek})' : ''}",
                      iconColor: activeTheme.lectureColor,
                      activeTheme: activeTheme,
                    ),
                    Divider(height: 20, color: activeTheme.borderColor),
                    _buildDetailRow(
                      icon: useIOSStyle ? CupertinoIcons.clock : Icons.access_time_rounded,
                      title: "Time Slot",
                      value: "${widget.event.start} - ${widget.event.finish}",
                      iconColor: activeTheme.assessmentColor,
                      activeTheme: activeTheme,
                    ),
                    Divider(height: 20, color: activeTheme.borderColor),
                    _buildDetailRow(
                      icon: useIOSStyle ? CupertinoIcons.location : Icons.location_on_rounded,
                      title: "Location",
                      value: _isOnline ? "Online Lecture" : "${building.canonicalName} (${widget.event.location})",
                      iconColor: activeTheme.optionalColor,
                      activeTheme: activeTheme,
                    ),
                    if (widget.event.staff.isNotEmpty) ...[
                      Divider(height: 20, color: activeTheme.borderColor),
                      _buildDetailRow(
                        icon: useIOSStyle ? CupertinoIcons.person : Icons.person_outline_rounded,
                        title: "Staff",
                        value: widget.event.staff,
                        iconColor: activeTheme.tutorialColor,
                        activeTheme: activeTheme,
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Embedded Interactive Google Maps Preview Card
              if (!_isOnline) ...[
                Text(
                  "GOOGLE MAPS CAMPUS PREVIEW",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: activeTheme.subtitleTextColor,
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _launchGoogleMaps(context),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 190,
                      decoration: BoxDecoration(
                        border: Border.all(color: activeTheme.borderColor, width: 1.5),
                        borderRadius: BorderRadius.circular(16),
                        color: activeTheme.containerBackgroundColor,
                      ),
                      child: Stack(
                        children: [
                          if (_webViewController != null)
                            WebViewWidget(controller: _webViewController!),
                          if (_isLoadingMap)
                            Center(
                              child: CircularProgressIndicator(
                                color: activeTheme.primaryColor,
                                strokeWidth: 2.5,
                              ),
                            ),
                          // Bottom Bar Overlay
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.88),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.map_rounded, color: Color(0xFF4285F4), size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    "Tap map to open in Google Maps",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(width: 4),
                                  Icon(Icons.open_in_new_rounded, color: Colors.white, size: 14),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Open in Google Maps Full Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () => _launchGoogleMaps(context),
                  icon: Icon(Icons.map_rounded, color: activeTheme.buttonTextColor),
                  label: Text(
                    _isOnline ? "Online Lecture" : "Open in Google Maps",
                    style: TextStyle(
                      color: activeTheme.buttonTextColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isOnline ? activeTheme.subtitleTextColor : activeTheme.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String title,
    required String value,
    required Color iconColor,
    required AppThemeConfig activeTheme,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: activeTheme.subtitleTextColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: activeTheme.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
