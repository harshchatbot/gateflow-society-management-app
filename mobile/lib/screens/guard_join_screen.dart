import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/app_logger.dart';
import '../core/storage.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_service.dart';
import '../ui/app_colors.dart';
import '../ui/glass_loader.dart';
import 'guard_shell_screen.dart';

class GuardJoinScreen extends StatefulWidget {
  const GuardJoinScreen({super.key});

  @override
  State<GuardJoinScreen> createState() => _GuardJoinScreenState();
}

class _GuardJoinScreenState extends State<GuardJoinScreen> {
  final FirebaseAuthService _authService = FirebaseAuthService();
  final FirestoreService _firestore = FirestoreService();

  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _pinController = TextEditingController();
  final _shiftController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isScanning = true;
  bool _isProcessing = false;
  String? _societyId;
  String? _error;
  XFile? _selfie;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _pinController.dispose();
    _shiftController.dispose();
    super.dispose();
  }

  void _onBarcodeFound(BarcodeCapture capture) {
    if (!_isScanning) return;
    final barcode = capture.barcodes.isNotEmpty ? capture.barcodes.first : null;
    final raw = barcode?.rawValue;
    if (raw == null) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw Exception("Invalid QR payload");
      }

      final type = decoded['type']?.toString();
      final societyId = decoded['societyId']?.toString();
      final exp = decoded['exp'];

      if (type != 'guard_join_v1') {
        throw Exception("Unsupported QR type");
      }
      if (societyId == null || societyId.isEmpty) {
        throw Exception("QR missing fields");
      }

      if (exp is num) {
        final expiry = DateTime.fromMillisecondsSinceEpoch(exp.toInt());
        if (DateTime.now().isAfter(expiry)) {
          throw Exception("QR code has expired");
        }
      }

      setState(() {
        _isScanning = false;
        _societyId = societyId;
        _error = null;
      });
    } catch (e, st) {
      AppLogger.e("GuardJoinScreen QR parse error", error: e, stackTrace: st);
      setState(() {
        _error = "Invalid or expired QR code. Please ask admin to regenerate.";
      });
    }
  }

  Future<void> _handleJoin() async {
    if (!_formKey.currentState!.validate()) return;
    final societyId = _societyId;
    if (societyId == null) {
      setState(() {
        _error = "QR not scanned. Please scan a valid Guard Join QR.";
      });
      return;
    }

    final name = _nameController.text.trim();
    final username = _usernameController.text.trim();
    final pin = _pinController.text.trim();

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      AppLogger.i("GuardJoinScreen creating guard account", data: {
        'societyId': societyId,
        'username': username,
      });

      final cred = await _authService.createGuardAccountWithUsername(
        username: username,
        pin: pin,
      );
      final uid = cred.user?.uid;
      if (uid == null) {
        throw Exception("Guard account creation failed (uid null)");
      }

      // Derive email/phone from username
      String? email;
      String? phone;
      if (username.contains('@')) {
        email = username.toLowerCase();
      } else {
        phone = username;
      }

      // Upload selfie if provided
      String? photoUrl;
      if (_selfie != null) {
        try {
          final storage = FirebaseStorage.instance;
          final ref = storage.ref().child('societies/$societyId/guards/$uid.jpg');
          final file = File(_selfie!.path);
          final task = await ref.putFile(file);
          photoUrl = await task.ref.getDownloadURL();
        } catch (e, st) {
          AppLogger.e("GuardJoinScreen selfie upload failed", error: e, stackTrace: st);
        }
      }

      await _firestore.setMember(
        societyId: societyId,
        uid: uid,
        systemRole: 'guard',
        societyRole: null,
        name: name,
        phone: phone,
        email: email,
        flatNo: null,
        photoUrl: photoUrl,
        shiftTimings: _shiftController.text.trim().isEmpty ? null : _shiftController.text.trim(),
        active: true,
      );

      await Storage.saveFirebaseSession(
        uid: uid,
        societyId: societyId,
        systemRole: 'guard',
        name: name,
      );

      await Storage.saveGuardSession(
        guardId: uid,
        guardName: name,
        societyId: societyId,
      );

      if (!mounted) return;
      setState(() {
        _isProcessing = false;
      });

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => GuardShellScreen(
            guardId: uid,
            guardName: name,
            societyId: societyId,
          ),
        ),
        (route) => false,
      );
    } catch (e, st) {
      AppLogger.e("GuardJoinScreen join error", error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _error = "Failed to join as guard. Please try again or ask admin to regenerate QR.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasScanned = _societyId != null;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.text),
        title: const Text(
          "Join as Guard",
          style: TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    height: 260,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: hasScanned
                          ? Center(
                              child: Icon(
                                Icons.check_circle_rounded,
                                color: AppColors.success,
                                size: 64,
                              ),
                            )
                          : MobileScanner(
                              onDetect: _onBarcodeFound,
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    hasScanned
                        ? "QR scanned successfully.\nSet a 4–6 digit password to complete setup."
                        : "Ask your admin to show the Guard Join QR, then scan it to start.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.text2,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: AppColors.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (hasScanned) ...[
                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundColor: AppColors.surface,
                                backgroundImage: _selfie != null ? FileImage(File(_selfie!.path)) : null,
                                child: _selfie == null
                                    ? const Icon(Icons.camera_alt_rounded, color: AppColors.text2)
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextButton(
                                  onPressed: () async {
                                    final picker = ImagePicker();
                                    final picked = await picker.pickImage(
                                      source: ImageSource.camera,
                                      imageQuality: 80,
                                    );
                                    if (picked != null) {
                                      setState(() {
                                        _selfie = picked;
                                      });
                                    }
                                  },
                                  child: const Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      "Add selfie (optional)",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _nameController,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: "Full Name",
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return "Please enter name";
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _usernameController,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: "Phone number or email (username)",
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            validator: (value) {
                              final v = value?.trim() ?? "";
                              if (v.isEmpty) {
                                return "Please enter phone or email";
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _pinController,
                            keyboardType: TextInputType.number,
                            obscureText: true,
                            decoration: InputDecoration(
                              labelText: "Set Guard Password (4–6 digits)",
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            maxLength: 6,
                            validator: (value) {
                              final v = value?.trim() ?? "";
                              if (v.length < 4 || v.length > 6 || int.tryParse(v) == null) {
                                return "Please enter a 4–6 digit number";
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _shiftController,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              labelText: "Shift timings (optional, e.g. 8am–4pm)",
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing ? null : _handleJoin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text(
                          "Confirm & Join",
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          GlassLoader(show: _isProcessing, message: "Creating guard account…"),
        ],
      ),
    );
  }
}

