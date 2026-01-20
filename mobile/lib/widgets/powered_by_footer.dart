import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PoweredByFooter extends StatelessWidget {
  const PoweredByFooter({super.key});

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            Text('Powered by', style: TextStyle(color: color, fontSize: 13)),
            GestureDetector(
              onTap: () => _open('https://techfilabs.com'),
              child: Text(
                'TechFi Labs',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            Text('a unit of', style: TextStyle(color: color, fontSize: 13)),
            GestureDetector(
              onTap: () => _open('https://thetechnologyfiction.com'),
              child: Text(
                'The Technology Fiction',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
