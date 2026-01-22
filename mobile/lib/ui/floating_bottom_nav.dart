import 'dart:ui';
import 'package:flutter/material.dart';

class FloatingNavItem {
  final IconData icon;
  final String label;

  const FloatingNavItem({
    required this.icon,
    required this.label,
  });
}

class SocietyBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<FloatingNavItem> items;

  // NEW (backward-compatible)
  final bool showCenterButton;
  final int centerIndex;
  final IconData centerIcon;
  final double centerGapWidth;

  const SocietyBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,

    // Defaults keep your Guard behaviour unchanged
    this.showCenterButton = true,
    this.centerIndex = 2,
    this.centerIcon = Icons.qr_code_scanner,
    this.centerGapWidth = 70,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          // 1) Glass Background Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withOpacity(0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: _buildRowTabs(),
                ),
              ),
            ),
          ),

          // 2) Center FAB (optional)
          if (showCenterButton)
            Positioned(
              bottom: 25,
              child: GestureDetector(
                onTap: () => onTap(centerIndex),
                child: Container(
                  width: 65,
                  height: 65,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2F6BFF), Color(0xFF0047FF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2F6BFF).withOpacity(0.4),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(centerIcon, color: Colors.white, size: 30),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildRowTabs() {
    // If center button is OFF -> show all items (up to 6 for admin/resident)
    if (!showCenterButton) {
      // Show all items
      return List.generate(items.length, (i) => _buildTab(i));
    }

    // If center button is ON (guard style)
    // Layout: 0,1, GAP, 3,4 (showing Home, Visitors, [GAP], History, Profile)
    // Note: Guard has 5 tabs total (Entry is center button at index 2)
    if (items.length == 5) {
      return [
        _buildTab(0), // Home
        _buildTab(1), // Visitors
        SizedBox(width: centerGapWidth), // Gap for center button
        _buildTab(3), // History
        _buildTab(4), // Profile
      ];
    }
    // Fallback for 6 tabs (if needed in future)
    return [
      _buildTab(0), // Home
      _buildTab(1), // Visitors
      SizedBox(width: centerGapWidth), // Gap for center button
      _buildTab(3), // History
      _buildTab(4), // Notices
      _buildTab(5), // Profile
    ];
  }

  Widget _buildTab(int index) {
    // Safety check to prevent red screen if list is too short during reload
    if (index >= items.length) return const SizedBox.shrink();

    final isSelected = currentIndex == index;
    // When center button is ON (guard), we show 5 tabs (0,1, gap, 3,4,5) so need compact layout
    // When center button is OFF (admin/resident), we show all 6 tabs
    final needsCompactLayout = showCenterButton && items.length >= 6;

    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              padding: EdgeInsets.all(needsCompactLayout ? 6 : 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF2F6BFF).withOpacity(0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                items[index].icon,
                color: isSelected ? const Color(0xFF2F6BFF) : Colors.grey.shade500,
                size: needsCompactLayout ? 22 : 26,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              items[index].label,
              style: TextStyle(
                fontSize: needsCompactLayout ? 8 : 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? const Color(0xFF2F6BFF) : Colors.grey.shade600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
