import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'app_theme_config.dart';

class FeatureTourItem {
  final IconData icon;
  final String title;
  final String description;
  final Color accentColor;

  const FeatureTourItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.accentColor,
  });
}

void showFeatureTourModal(BuildContext context, AppThemeConfig activeTheme) {
  final isIOSStyle = !kIsWeb && Platform.isIOS;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _FeatureTourBottomSheet(activeTheme: activeTheme, isIOSStyle: isIOSStyle),
  );
}

class _FeatureTourBottomSheet extends StatefulWidget {
  final AppThemeConfig activeTheme;
  final bool isIOSStyle;

  const _FeatureTourBottomSheet({
    required this.activeTheme,
    required this.isIOSStyle,
  });

  @override
  State<_FeatureTourBottomSheet> createState() => _FeatureTourBottomSheetState();
}

class _FeatureTourBottomSheetState extends State<_FeatureTourBottomSheet> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  List<FeatureTourItem> _getTourItems() {
    final t = widget.activeTheme;
    return [
      FeatureTourItem(
        icon: Icons.swipe_rounded,
        title: "Swipe Days & Timetable",
        description: "Swipe left or right anywhere on your timetable or date bar to quickly switch between days of the week.",
        accentColor: t.lectureColor,
      ),
      FeatureTourItem(
        icon: widget.isIOSStyle ? CupertinoIcons.arrow_clockwise : Icons.refresh_rounded,
        title: "Pull Down to Sync",
        description: "Pull down on your schedule anytime to trigger a live background sync and fetch your latest university timetable changes.",
        accentColor: t.primaryColor,
      ),
      FeatureTourItem(
        icon: widget.isIOSStyle ? CupertinoIcons.today : Icons.today_rounded,
        title: "Jump to Today",
        description: "Tap the calendar icon in the top header bar from anywhere in the app to instantly snap back to today's schedule.",
        accentColor: t.secondaryColor,
      ),
      FeatureTourItem(
        icon: widget.isIOSStyle ? CupertinoIcons.map : Icons.map_rounded,
        title: "Tap for Room Maps & Details",
        description: "Tap on any lecture or assessment card to expand detailed room locations, lecturer info, and open full campus maps.",
        accentColor: t.practicalColor,
      ),
      FeatureTourItem(
        icon: widget.isIOSStyle ? CupertinoIcons.doc_text : Icons.assignment_rounded,
        title: "Assessments & Sidebar Menu",
        description: "Tap the ☰ menu in the top left to view assessment countdowns, customize themes, and manage notification alerts.",
        accentColor: t.assessmentColor,
      ),
    ];
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage(int total) {
    if (_currentIndex < total - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tourItems = _getTourItems();
    final buttonTextColor = widget.activeTheme.buttonTextColor;

    return Container(
      height: MediaQuery.of(context).size.height * 0.58,
      decoration: BoxDecoration(
        color: widget.activeTheme.cardBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: widget.activeTheme.borderColor, width: 1.5),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: widget.activeTheme.borderColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "APP QUICK GUIDE",
                  style: TextStyle(
                    color: widget.activeTheme.subtitleTextColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    "Skip",
                    style: TextStyle(
                      color: widget.activeTheme.subtitleTextColor,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Carousel PageView
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (idx) => setState(() => _currentIndex = idx),
              itemCount: tourItems.length,
              itemBuilder: (ctx, idx) {
                final item = tourItems[idx];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: item.accentColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: item.accentColor.withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          item.icon,
                          size: 36,
                          color: item.accentColor,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        item.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: widget.activeTheme.textColor,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        item.description,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: widget.activeTheme.subtitleTextColor,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Dots Indicator & Next/Done Button
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                // Page Indicator Dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(tourItems.length, (idx) {
                    final isSelected = _currentIndex == idx;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: isSelected ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? widget.activeTheme.primaryColor
                            : widget.activeTheme.borderColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 20),

                // Primary Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () => _nextPage(tourItems.length),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.activeTheme.primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 3,
                    ),
                    child: Text(
                      _currentIndex == tourItems.length - 1 ? "Got it! Open App" : "Next",
                      style: TextStyle(
                        color: buttonTextColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
