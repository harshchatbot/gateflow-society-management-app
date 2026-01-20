import 'dart:ui'; // Required for ImageFilter (Blur)
import 'package:flutter/material.dart';
import '../widgets/powered_by_footer.dart';
import '../core/storage.dart';
import 'new_visitor_screen.dart';

class GuardLoginScreen extends StatefulWidget {
  const GuardLoginScreen({super.key});

  @override
  State<GuardLoginScreen> createState() => _GuardLoginScreenState();
}

class _GuardLoginScreenState extends State<GuardLoginScreen> {
  final _guardIdController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _guardIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (_guardIdController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter Guard ID and Password")),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Simulate API delay
    await Future.delayed(const Duration(seconds: 2)); 
    
    // --- MOCK DATA ---
    final String guardId = _guardIdController.text;
    const String guardName = "Verified Guard"; 
    const String societyId = "SOC-001"; 
    // -----------------

    await Storage.saveGuardSession(
      guardId: guardId, 
      guardName: guardName,
      societyId: societyId,
    ); 

    if (mounted) {
      setState(() => _isLoading = false);
      Navigator.pushReplacement(
        context, 
        MaterialPageRoute(
          builder: (_) => NewVisitorScreen(
            guardId: guardId, 
            guardName: guardName,
            societyId: societyId,
          )
        )
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          // 1. The Main Login UI (Bottom Layer)
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: theme.primaryColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.security_rounded, size: 56, color: theme.primaryColor),
                          ),
                          const SizedBox(height: 24),
                          Text("GateFlow", style: theme.textTheme.headlineMedium),
                          const SizedBox(height: 8),
                          Text("Guard Access Portal", style: theme.textTheme.bodySmall),
                          
                          const SizedBox(height: 48),

                          Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFDFE1E6)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                TextField(
                                  controller: _guardIdController,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: "Guard ID",
                                    prefixIcon: Icon(Icons.badge_outlined),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                TextField(
                                  controller: _passwordController,
                                  obscureText: true,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _handleLogin(),
                                  decoration: const InputDecoration(
                                    labelText: "Password",
                                    prefixIcon: Icon(Icons.lock_outline),
                                  ),
                                ),
                                const SizedBox(height: 32),
                                ElevatedButton(
                                  onPressed: _isLoading ? null : _handleLogin,
                                  child: const Text("Secure Login"),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 24.0),
                  child: PoweredByFooter(),
                ),
              ],
            ),
          ),

          // 2. The "Glass" Loader Overlay (Top Layer)
          if (_isLoading)
            Positioned.fill(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), // The Blur Effect
                  child: Container(
                    color: Colors.white.withOpacity(0.5), // Semi-transparent white tint
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Floating Logo
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: theme.primaryColor.withOpacity(0.2),
                                  blurRadius: 30,
                                  spreadRadius: 10,
                                )
                              ],
                            ),
                            child: Icon(Icons.security_rounded, size: 48, color: theme.primaryColor),
                          ),
                          const SizedBox(height: 40),
                          
                          // Custom Spinner
                          SizedBox(
                            width: 50, 
                            height: 50,
                            child: CircularProgressIndicator(
                              color: theme.primaryColor,
                              strokeWidth: 4,
                              strokeCap: StrokeCap.round, // Rounded ends look cleaner
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          // Elegant Text
                          Text(
                            "Verifying Credentials...",
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.primaryColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}