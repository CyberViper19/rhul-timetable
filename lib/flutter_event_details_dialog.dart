import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'flutter_timetable_model.dart';

class EventDetailsModalSheet extends StatelessWidget {
  final TimetableEvent event;
  final Color typeColor;

  const EventDetailsModalSheet({
    super.key,
    required this.event,
    required this.typeColor,
  });

  LatLng _getBuildingCoordinates(String location) {
    final loc = location.toLowerCase();
    if (loc.contains('founder')) return const LatLng(51.4254, -0.5636);
    if (loc.contains('windsor')) return const LatLng(51.4248, -0.5631);
    if (loc.contains('davison') || loc.contains('library')) return const LatLng(51.4243, -0.5645);
    if (loc.contains('shilling')) return const LatLng(51.4262, -0.5620);
    if (loc.contains('moore')) return const LatLng(51.4242, -0.5619);
    if (loc.contains('bourne')) return const LatLng(51.4265, -0.5615);
    if (loc.contains('queen')) return const LatLng(51.4268, -0.5608);
    if (loc.contains('mccrea')) return const LatLng(51.4257, -0.5625);
    if (loc.contains('international')) return const LatLng(51.4250, -0.5628);
    if (loc.contains('bedford')) return const LatLng(51.4260, -0.5610);
    if (loc.contains('art')) return const LatLng(51.4253, -0.5640);
    if (loc.contains('wetton')) return const LatLng(51.4270, -0.5638);

    // Default RHUL Campus Center
    return const LatLng(51.4256, -0.5631);
  }

  bool get _isOnline => event.location.toLowerCase().contains('online');

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

    final query = "${event.location}, Royal Holloway University of London, Egham";
    final url = "https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}";
    final uri = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not launch Google Maps")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final useIOSStyle = !kIsWeb && Platform.isIOS;
    final coords = _getBuildingCoordinates(event.location);

    return Container(
      decoration: BoxDecoration(
        color: useIOSStyle ? const Color(0xFF1C1C1E) : const Color(0xFF1E293B),
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
                    color: const Color(0xFF64748B),
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
                      event.module,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: typeColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      event.type,
                      style: TextStyle(
                        fontSize: 12,
                        color: typeColor,
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
                  color: useIOSStyle ? const Color(0xFF2C2C2E) : const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  children: [
                    _buildDetailRow(
                      icon: useIOSStyle ? CupertinoIcons.calendar : Icons.calendar_today_rounded,
                      title: "Date",
                      value: "${event.day}, ${event.formattedDate}${event.academicWeek > 0 ? ' (Week ${event.academicWeek})' : ''}",
                      iconColor: const Color(0xFF38BDF8),
                    ),
                    const Divider(height: 20, color: Color(0xFF334155)),
                    _buildDetailRow(
                      icon: useIOSStyle ? CupertinoIcons.clock : Icons.access_time_rounded,
                      title: "Time Slot",
                      value: "${event.start} - ${event.finish}",
                      iconColor: const Color(0xFFF59E0B),
                    ),
                    const Divider(height: 20, color: Color(0xFF334155)),
                    _buildDetailRow(
                      icon: useIOSStyle ? CupertinoIcons.location : Icons.location_on_rounded,
                      title: "Location",
                      value: event.location,
                      iconColor: const Color(0xFF10B981),
                    ),
                    if (event.staff.isNotEmpty) ...[
                      const Divider(height: 20, color: Color(0xFF334155)),
                      _buildDetailRow(
                        icon: useIOSStyle ? CupertinoIcons.person : Icons.person_outline_rounded,
                        title: "Staff",
                        value: event.staff,
                        iconColor: const Color(0xFFA855F7),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Embedded Interactive Map Preview Card
              if (!_isOnline) ...[
                const Text(
                  "CAMPUS MAP PREVIEW",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _launchGoogleMaps(context),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 180,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF334155), width: 1.5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Stack(
                        children: [
                          FlutterMap(
                            options: MapOptions(
                              initialCenter: coords,
                              initialZoom: 16.5,
                              interactionOptions: const InteractionOptions(
                                flags: InteractiveFlag.none, // Lock gestures so map acts like a button
                              ),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.example.rhul_timetable',
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: coords,
                                    width: 44,
                                    height: 44,
                                    child: const Icon(
                                      Icons.location_on_rounded,
                                      color: Color(0xFFEF4444),
                                      size: 40,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          // Gradient Overlay with "Tap to open in Google Maps" prompt
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
                                    Colors.black.withValues(alpha: 0.85),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Image.network(
                                    'https://upload.wikimedia.org/wikipedia/commons/3/39/Google_Maps_icon_%282015-2020%29.svg',
                                    height: 18,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.map_rounded, color: Colors.white, size: 18),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    "Tap map to open in Google Maps",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.open_in_new_rounded, color: Colors.white, size: 14),
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
                  icon: const Icon(Icons.map_rounded, color: Colors.white),
                  label: Text(
                    _isOnline ? "Online Lecture" : "Open in Google Maps",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isOnline ? const Color(0xFF64748B) : const Color(0xFF4285F4),
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
            crossAxisAlignment: CrossAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
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
