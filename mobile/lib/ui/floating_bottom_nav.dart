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

  /// When set (e.g. Resident shell), selected tab icon/label use this color instead of default.
  /// Used for Phase-3 accent (pastel teal) in one place only. Admin/Guard leave null.
  final Color? selectedItemColor;

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
    this.selectedItemColor,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final bottomPadding = bottomInset > 0 ? (bottomInset + 8) : 20.0;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
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
                  children: _buildRowTabs(context),
                ),
              ),
            ),
          ),

          // 2) Center FAB (optional) — uses theme primary, no blue
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
                    color: Theme.of(context).colorScheme.primary,
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.35),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(centerIcon, color: Theme.of(context).colorScheme.onPrimary, size: 30),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildRowTabs(BuildContext context) {
    // If center button is OFF -> show all items (up to 6 for admin/resident)
    if (!showCenterButton) {
      return List.generate(items.length, (i) => _buildTab(context, i));
    }

    // If center button is ON (guard style)
    if (items.length == 5) {
      return [
        _buildTab(context, 0),
        _buildTab(context, 1),
        SizedBox(width: centerGapWidth),
        _buildTab(context, 3),
        _buildTab(context, 4),
      ];
    }
    return [
      _buildTab(context, 0),
      _buildTab(context, 1),
      SizedBox(width: centerGapWidth),
      _buildTab(context, 3),
      _buildTab(context, 4),
      _buildTab(context, 5),
    ];
  }

  Widget _buildTab(BuildContext context, int index) {
    if (index >= items.length) return const SizedBox.shrink();

    final isSelected = currentIndex == index;
    final selectedColor = selectedItemColor ?? Theme.of(context).colorScheme.primary;
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
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                items[index].icon,
                color: isSelected ? selectedColor : Colors.grey.shade500,
                size: needsCompactLayout ? 22 : 26,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              items[index].label,
              style: TextStyle(
                fontSize: needsCompactLayout ? 8 : 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? selectedColor : Colors.grey.shade600,
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
