import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';

class PoweredByFooter extends StatefulWidget {
  const PoweredByFooter({super.key});

  @override
  State<PoweredByFooter> createState() => _PoweredByFooterState();
}

class _PoweredByFooterState extends State<PoweredByFooter> {
  // To avoid memory leaks, we define recognizers here
  late TapGestureRecognizer _techFiRecognizer;
  late TapGestureRecognizer _ttfRecognizer;

  @override
  void initState() {
    super.initState();
    _techFiRecognizer = TapGestureRecognizer()
      ..onTap = () => _launchURL('https://www.techfilabs.com/');
    _ttfRecognizer = TapGestureRecognizer()
      ..onTap = () => _launchURL('https://thetechnologyfiction.com/');
  }

  @override
  void dispose() {
    _techFiRecognizer.dispose();
    _ttfRecognizer.dispose();
    super.dispose();
  }

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    // Directly try to launch. often canLaunchUrl returns false on newer SDKs due to visibility
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(
          color: onSurface.withValues(alpha: 0.05),
          indent: 50,
          endIndent: 50,
        ),
        Padding(
          padding:
              const EdgeInsets.only(top: 8, bottom: 24, left: 20, right: 20),
          child: RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.5),
                fontSize: 10,
                letterSpacing: 0.5,
              ),
              children: [
                const TextSpan(text: 'POWERED BY '),
                TextSpan(
                  text: 'TECHFI LABS',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: onSurface.withValues(alpha: 0.8),
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: _techFiRecognizer,
                ),
                const TextSpan(text: '  •  A UNIT OF '),
                TextSpan(
                  text: 'THE TECHNOLOGY FICTION',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: onSurface.withValues(alpha: 0.8),
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: _ttfRecognizer,
                ),
                const TextSpan(
                  text: '  •  Built with ❤️ from Rajasthan, India ',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
