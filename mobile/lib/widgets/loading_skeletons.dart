import 'package:flutter/material.dart';

class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
  });

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface.withOpacity(0.08);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: base,
        borderRadius: borderRadius,
      ),
    );
  }
}

class HistorySkeletonList extends StatelessWidget {
  final int count;

  const HistorySkeletonList({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: count,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            SkeletonBox(width: 140, height: 18),
            SizedBox(height: 12),
            SkeletonBox(width: double.infinity, height: 14),
            SizedBox(height: 8),
            SkeletonBox(width: 220, height: 14),
            SizedBox(height: 8),
            SkeletonBox(width: 180, height: 14),
          ],
        ),
      ),
    );
  }
}
