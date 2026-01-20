import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gateflow/core/app_error.dart';
import 'package:gateflow/core/app_logger.dart';
import 'package:gateflow/core/storage.dart';
import 'package:gateflow/services/auth_service.dart';
import 'package:gateflow/widgets/app_text_field.dart';
import 'package:gateflow/widgets/full_screen_loader.dart';
import 'package:gateflow/widgets/powered_by_footer.dart';
import 'package:gateflow/widgets/primary_button.dart';
import 'package:gateflow/widgets/section_card.dart';
import 'new_visitor_screen.dart';

class GuardLoginScreen extends StatefulWidget {
  const GuardLoginScreen({super.key});

  @override
  State<GuardLoginScreen> createState() => _GuardLoginScreenState();
}

class _GuardLoginScreenState extends State<GuardLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _societyIdController = TextEditingController();
  final _pinController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;

  @override
  void dispose() {
    _societyIdController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final result = await _authService.login(
      societyId: _societyIdController.text.trim(),
      pin: _pinController.text.trim(),
    );

    if (!mounted) return;

    if (result.isSuccess) {
      final guard = result.data!;
      await Storage.saveGuardSession(
        guardId: guard.guardId,
        guardName: guard.guardName,
        societyId: guard.societyId,
      );
      AppLogger.i('Guard session saved', data: {'guardId': guard.guardId});

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => NewVisitorScreen(
            guardId: guard.guardId,
            guardName: guard.guardName,
            societyId: guard.societyId,
          ),
        ),
      );
    } else {
      setState(() => _isLoading = false);
      final error = result.error ?? AppError(userMessage: 'Login failed', technicalMessage: 'Unknown');
      _showError(error.userMessage);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 16)),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Icon(Icons.shield, color: colorScheme.primary, size: 28),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'GateFlow',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            'Guard-first visitor entry',
                            style: TextStyle(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Expanded(
                    child: Form(
                      key: _formKey,
                      child: SectionCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Sign in',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Enter your society ID and PIN to continue.',
                              style: TextStyle(color: colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 24),
                            AppTextField(
                              controller: _societyIdController,
                              label: 'Society ID',
                              hint: 'soc_ajmer_01',
                              icon: Icons.apartment,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter society ID';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            AppTextField(
                              controller: _pinController,
                              label: 'PIN',
                              hint: '1234',
                              icon: Icons.lock,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              obscureText: true,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter PIN';
                                }
                                if (value.length < 4) {
                                  return 'PIN must be at least 4 digits';
                                }
                                return null;
                              },
                            ),
                            const Spacer(),
                            PrimaryButton(
                              label: 'Login',
                              onPressed: _isLoading ? null : _handleLogin,
                              isLoading: _isLoading,
                              icon: Icons.login,
                            ),
                            const SizedBox(height: 12),
                            const PoweredByFooter(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading) const FullScreenLoader(message: 'Signing in...'),
        ],
      ),
    );
  }
}
