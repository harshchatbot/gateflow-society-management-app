import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import '../ui/app_colors.dart';

class PoweredByFooter extends StatelessWidget {
  const PoweredByFooter({super.key});

  Future<void> _open(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      // Silently handle URL launch errors
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      color: AppColors.text2.withOpacity(0.7),
      fontSize: 11,
      fontWeight: FontWeight.w400,
      height: 1.4,
    );

    final linkStyle = TextStyle(
      color: AppColors.text2.withOpacity(0.9),
      fontSize: 11,
      fontWeight: FontWeight.w500,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.text2.withOpacity(0.4),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      child: Center(
        child: RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: baseStyle,
            children: [
              const TextSpan(text: 'Powered by '),
              TextSpan(
                text: 'TechFi Labs',
                style: linkStyle,
                recognizer: TapGestureRecognizer()
                  ..onTap = () => _open('https://www.techfilabs.com/'),
              ),
              const TextSpan(text: '. A Unit of '),
              TextSpan(
                text: 'The Technology Fiction',
                style: linkStyle,
                recognizer: TapGestureRecognizer()
                  ..onTap = () => _open('https://thetechnologyfiction.com/'),
              ),
              const TextSpan(text: '.'),
            ],
          ),
        ),
      ),
    );
  }
}
