import 'package:flutter/material.dart';

class GuardHistoryScreen extends StatelessWidget {
  final String guardId;
  final String? guardName;
  final String? societyId;

  const GuardHistoryScreen({
    super.key,
    required this.guardId,
    this.guardName,
    this.societyId,
  });

  @override
  Widget build(BuildContext context) {
    final name = (guardName ?? "").trim();
    final soc = (societyId ?? "").trim();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "History",
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              [
                if (name.isNotEmpty) "Guard: $name",
                if (soc.isNotEmpty) "Society: $soc",
                "Guard ID: $guardId",
              ].join(" • "),
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.withOpacity(0.2)),
              ),
              child: const Text(
                "This screen is a placeholder. We’ll connect it to Visitor logs next.",
              ),
            ),
          ],
        ),
      ),
    );
  }
}
