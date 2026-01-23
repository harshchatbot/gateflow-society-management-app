import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/app_logger.dart';
import '../core/env.dart';
import '../services/admin_service.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_service.dart';
import '../services/invite_claim_service.dart';
import '../ui/app_colors.dart';
import '../ui/glass_loader.dart';
import 'admin_shell_screen.dart';
import 'admin_login_screen.dart';
import '../core/storage.dart';
import '../services/invite_bulk_upload_service.dart';


/// Admin Onboarding Screen
///
/// Allows new admins to register/create their account.
/// Theme: Purple/Admin theme
class AdminOnboardingScreen extends StatefulWidget {
  const AdminOnboardingScreen({super.key});

  @override
  State<AdminOnboardingScreen> createState() => _AdminOnboardingScreenState();
}

class _AdminOnboardingScreenState extends State<AdminOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _societyCodeController = TextEditingController();
  final _societyNameController = TextEditingController();
  String? _selectedCity;
  String? _selectedState;
  final _adminIdController = TextEditingController();
  final _adminNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  late final AdminService _adminService = AdminService(
    baseUrl: Env.apiBaseUrl.isNotEmpty ? Env.apiBaseUrl : "http://192.168.29.195:8000",
  );

  final FirebaseAuthService _authService = FirebaseAuthService();
  final FirestoreService _firestore = FirestoreService();
  final InviteClaimService _inviteClaimService = InviteClaimService();

  bool _isLoading = false;
  bool _isLoadingLocations = false;
  bool _obscurePin = true;
  bool _obscureConfirmPin = true;
  bool _isCreatingSociety = true;
  String _selectedRole = "SUPER_ADMIN";

  late ConfettiController _confettiController;

  // Dynamic state & city lists loaded from Firestore
  List<Map<String, String>> _stateOptions = [];
  List<Map<String, String>> _cityOptions = [];
  String? _selectedStateId;

  final List<String> _roles = [
    "SUPER_ADMIN",
    "ADMIN",
    "PRESIDENT",
    "SECRETARY",
    "TREASURER",
    "COMMITTEE",
  ];

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 2));
    _loadStates();
  }

  Future<void> _loadStates() async {
    setState(() {
      _isLoadingLocations = true;
      _stateOptions = [];
      _cityOptions = [];
      _selectedStateId = null;
      _selectedState = null;
      _selectedCity = null;
    });

    final states = await _firestore.getStatesList();

    setState(() {
      _stateOptions = states;
      _isLoadingLocations = false;
    });
  }

  Future<void> _loadCitiesForState(String stateId) async {
    setState(() {
      _isLoadingLocations = true;
      _cityOptions = [];
      _selectedCity = null;
    });

    final cities = await _firestore.getCitiesForState(stateId);

    setState(() {
      _cityOptions = cities;
      _isLoadingLocations = false;
    });
  }

  @override
  void dispose() {
    _societyCodeController.dispose();
    _societyNameController.dispose();
    _adminIdController.dispose();
    _adminNameController.dispose();
    _phoneController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  // ✅ helper: create root pointer /members/{uid}
  Future<void> _setRootPointer({
    required String uid,
    required String societyId,
    required String systemRole,
  }) async {
    await FirebaseFirestore.instance.collection('members').doc(uid).set({
      'uid': uid,
      'societyId': societyId,
      'systemRole': systemRole,
      'active': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final societyCode = _societyCodeController.text.trim().toUpperCase();
    final adminName = _adminNameController.text.trim();
    final email = _adminIdController.text.trim();
    final phone = _phoneController.text.trim();
    final pin = _pinController.text.trim();

    setState(() => _isLoading = true);

    AppLogger.i("Admin onboarding attempt", data: {
      "society_code": societyCode,
      "email": email,
      "mode": _isCreatingSociety ? "create" : "join",
      "role": _selectedRole,
    });

    try {
      // Step 1: Login-or-signup (production safe)
      // NOTE: Add this method in FirebaseAuthService (I shared earlier)
      final userCredential = await _authService.signUpOrSignIn(
        email: email,
        password: pin,
      );

      final uid = userCredential.user?.uid;
      if (uid == null) {
        throw Exception("Failed to authenticate");
      }

      // Step 2: Resolve or create society
      String societyId;

      if (_isCreatingSociety) {
        // CREATE SOCIETY = SUPER_ADMIN bootstrap
        final societyName = _societyNameController.text.trim();
        final city = _selectedCity;
        final state = _selectedState;

        // Prevent duplicate society code reuse (optional but recommended)
        final existing = await _firestore.getSocietyIdByCode(societyCode);
        if (existing != null) {
          setState(() => _isLoading = false);
          _showError("Society code already exists. Choose a different code.");
          return;
        }

        societyId = 'soc_${societyCode.toLowerCase()}';

        await _firestore.createSociety(
          societyId: societyId,
          code: societyCode,
          name: societyName,
          city: city,
          state: state,
          createdByUid: uid,
        );



      final result = await InviteBulkUploadService().pickCsvAndUploadInvites(
        societyId: societyId,
      );

      AppLogger.i(
        "Bulk invite upload done",
        data: {
          'processed': result.processed,
          'created': result.created,
          'skipped': result.skipped,
          'errors': result.errors.length,
        },
      );

      await _setRootPointer(
        uid: uid,
        societyId: societyId,
        systemRole: 'super_admin',
      );


        // If you want confetti only for new society creation:
        _confettiController.play();
      } else {
        // JOIN SOCIETY = Invite → Self Signup → Claim Invite
        final existingSocietyId = await _firestore.getSocietyIdByCode(societyCode);
        if (existingSocietyId == null) {
          setState(() => _isLoading = false);
          _showError("Society not found or inactive for this code.");
          return;
        }
        societyId = existingSocietyId;

        final claimResult = await _inviteClaimService.claimInviteForSociety(
          societyId: societyId,
        );

        if (!claimResult.claimed) {
          setState(() => _isLoading = false);
          _showError("No pending admin invite found for this email.");
          return;
        }

        if ((claimResult.systemRole ?? '') != 'admin') {
          setState(() => _isLoading = false);
          _showError("This email is not invited as Admin for this society.");
          return;
        }

        // Update profile fields after claim (now allowed)
        await FirebaseFirestore.instance
            .collection('societies')
            .doc(societyId)
            .collection('members')
            .doc(uid)
            .set({
          'name': adminName,
          'phone': phone.isEmpty ? null : phone,
          'societyRole': _selectedRole.toLowerCase(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // Root pointer is created in claim batch, but safe to ensure:
        await _setRootPointer(uid: uid, societyId: societyId, systemRole: 'admin');
      }

      // Step 3: Save Firebase session
      final systemRoleForSession = _isCreatingSociety ? 'super_admin' : 'admin';

      await Storage.saveFirebaseSession(
        uid: uid,
        societyId: societyId,
        systemRole: systemRoleForSession,
        societyRole: _selectedRole,
        name: adminName,
      );

      AppLogger.i("Admin onboarding successful", data: {
        'uid': uid,
        'societyId': societyId,
        'systemRole': systemRoleForSession,
      });

      setState(() => _isLoading = false);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Account created successfully!",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.admin,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 2),
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AdminShellScreen(
            adminId: uid,
            adminName: adminName,
            societyId: societyId,
            role: _selectedRole,
          ),
        ),
      );
    } catch (e, stackTrace) {
      AppLogger.e("Admin onboarding exception", error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() => _isLoading = false);
        String errorMsg = "Registration failed. Please try again.";
        if (e.toString().contains('wrong-password') || e.toString().contains('invalid-credential')) {
          errorMsg = "Invalid password. Try again.";
        } else if (e.toString().contains('weak-password')) {
          errorMsg = "Password too weak. Please use at least 6 characters.";
        }
        _showError(errorMsg);
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: AppColors.text,
              size: 20,
            ),
          ),
          onPressed: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
            );
          },
        ),
      ),
      body: Stack(
        children: [
          // Gradient Background (Purple theme)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.admin.withOpacity(0.15),
                    AppColors.bg,
                    AppColors.bg,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  _buildBrandHeader(),
                  const SizedBox(height: 40),
                  _buildRegistrationForm(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          if (_isLoading || _isLoadingLocations)
            GlassLoader(
              show: true,
              message: _isLoading ? "Creating your account…" : "Loading locations…",
            ),

          // Confetti celebration
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              numberOfParticles: 25,
              maxBlastForce: 18,
              minBlastForce: 5,
              gravity: 0.25,
              colors: const [
                AppColors.admin,
                AppColors.success,
                Colors.orangeAccent,
                Colors.blueAccent,
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------
  // UI METHODS (your existing UI)
  // Copy-paste from your current AdminOnboardingScreen below
  // ---------------------------

  Widget _buildBrandHeader() {
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.admin, Color(0xFF7C3AED)],
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: AppColors.admin.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.person_add_rounded,
            size: 50,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          "Admin Onboarding",
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: AppColors.text,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Create your admin account",
          style: TextStyle(
            color: AppColors.text2,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  Future<void> _uploadInvitesCsv({
      required String societyId,
    }) async {
      try {
        setState(() => _isLoading = true);

        final result = await InviteBulkUploadService().pickCsvAndUploadInvites(
          societyId: societyId,
        );

        if (!mounted) return;
        setState(() => _isLoading = false);

        final msg =
            "Processed: ${result.processed} | Created: ${result.created} | Skipped: ${result.skipped}";
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );

        if (result.errors.isNotEmpty) {
          // optional: log errors
          AppLogger.w("Bulk invite upload errors", data: {"errors": result.errors});
        }
      } catch (e, st) {
        AppLogger.e("Bulk invite upload failed", error: e, stackTrace: st);
        if (!mounted) return;
        setState(() => _isLoading = false);
        _showError("Upload failed: ${e.toString()}");
      }
    }




  Widget _buildRegistrationForm() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Fill in your details",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.text2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // Toggle: Create vs Join society
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text(
                        "Create society",
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                      selected: _isCreatingSociety,
                      onSelected: (v) {
                        setState(() {
                          _isCreatingSociety = true;
                          _selectedRole = "SUPER_ADMIN";
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text(
                        "Join society",
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                      selected: !_isCreatingSociety,
                      onSelected: (v) {
                        setState(() {
                          _isCreatingSociety = false;
                          if (_selectedRole == "SUPER_ADMIN") {
                            _selectedRole = "ADMIN";
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            if (_isCreatingSociety) ...[
              _PremiumField(
                controller: _societyNameController,
                label: "Society Name",
                hint: "e.g. Kedia Amara",
                icon: Icons.location_city_rounded,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Please enter Society Name";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "State",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text2,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.bg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: DropdownButtonFormField<String>(
                            value: _selectedState,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              prefixIcon: Icon(Icons.map_rounded, color: AppColors.admin),
                            ),
                            hint: const Text(
                              "Select state",
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            items: _stateOptions
                                .map((st) => DropdownMenuItem<String>(
                                      value: st['name'],
                                      child: Text(
                                        st['name'] ?? '',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.text,
                                        ),
                                      ),
                                    ))
                                .toList(),
                            validator: (value) {
                              if (_isCreatingSociety && (value == null || value.isEmpty)) {
                                return "Please select State";
                              }
                              return null;
                            },
                            onChanged: (value) {
                              final stateMap = _stateOptions.firstWhere(
                                (st) => st['name'] == value,
                                orElse: () => {'id': '', 'name': ''},
                              );

                              setState(() {
                                _selectedState = value;
                                _selectedStateId = stateMap['id'];
                                _selectedCity = null;
                              });

                              if (_selectedStateId != null && _selectedStateId!.isNotEmpty) {
                                _loadCitiesForState(_selectedStateId!);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "City",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text2,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.bg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: DropdownButtonFormField<String>(
                            value: _selectedCity,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              prefixIcon: Icon(Icons.location_on_rounded, color: AppColors.admin),
                            ),
                            hint: const Text(
                              "Select city",
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            items: _cityOptions
                                .map((city) => DropdownMenuItem<String>(
                                      value: city['name'],
                                      child: Text(
                                        city['name'] ?? '',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.text,
                                        ),
                                      ),
                                    ))
                                .toList(),
                            validator: (value) {
                              if (_isCreatingSociety && (value == null || value.isEmpty)) {
                                return "Please select City";
                              }
                              return null;
                            },
                            onChanged: (_selectedStateId == null || _selectedStateId!.isEmpty)
                                ? null
                                : (value) {
                                    setState(() => _selectedCity = value);
                                  },
                            disabledHint: const Text(
                              "Select state first",
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],

            _PremiumField(
              controller: _societyCodeController,
              label: "Society Code",
              hint: "e.g. SOC001 (unique code for your society)",
              icon: Icons.apartment_rounded,
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return "Please enter Society Code";
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            _PremiumField(
              controller: _adminIdController,
              label: "Email Address",
              hint: "Your admin email (e.g. admin@example.com)",
              icon: Icons.email_rounded,
              textInputAction: TextInputAction.next,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return "Please enter your email";
                }
                if (!value.contains('@')) {
                  return "Please enter a valid email";
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            _PremiumField(
              controller: _adminNameController,
              label: "Full Name",
              hint: "Enter your full name",
              icon: Icons.person_rounded,
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return "Please enter your name";
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            _PremiumField(
              controller: _phoneController,
              label: "Phone Number (Optional)",
              hint: "e.g. 9876543210",
              icon: Icons.phone_rounded,
              textInputAction: TextInputAction.next,
              keyboardType: TextInputType.phone,
              validator: (value) {
                if (value != null && value.trim().isNotEmpty && value.trim().length < 10) {
                  return "Please enter a valid phone number";
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // Role Selection
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isCreatingSociety ? "Role (for new society creator)" : "Role",
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text2,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: DropdownButtonFormField<String>(
                    value: _selectedRole,
                    decoration: InputDecoration(
                      prefixIcon: Container(
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.admin.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.admin_panel_settings_rounded, color: AppColors.admin, size: 20),
                      ),
                      hintText: "Select role",
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                    ),
                    items: (_isCreatingSociety
                            ? ["SUPER_ADMIN"]
                            : _roles.where((r) => r != "SUPER_ADMIN"))
                        .map((role) {
                      return DropdownMenuItem(
                        value: role,
                        child: Text(
                          role == "SUPER_ADMIN" ? "SUPER ADMIN" : role,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _selectedRole = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            _PremiumField(
              controller: _pinController,
              label: "PIN/Password",
              hint: "Create a secure PIN (min 4 digits)",
              icon: Icons.lock_rounded,
              obscureText: _obscurePin,
              textInputAction: TextInputAction.next,
              keyboardType: TextInputType.number,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePin ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: AppColors.text2,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscurePin = !_obscurePin),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return "Please enter a PIN";
                if (value.trim().length < 4) return "PIN must be at least 4 characters";
                return null;
              },
            ),
            const SizedBox(height: 20),

            _PremiumField(
              controller: _confirmPinController,
              label: "Confirm PIN",
              hint: "Re-enter your PIN",
              icon: Icons.lock_outline_rounded,
              obscureText: _obscureConfirmPin,
              textInputAction: TextInputAction.done,
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _handleRegister(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPin ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: AppColors.text2,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscureConfirmPin = !_obscureConfirmPin),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return "Please confirm your PIN";
                if (value.trim() != _pinController.text.trim()) return "PINs do not match";
                return null;
              },
            ),
            const SizedBox(height: 32),

            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleRegister,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.admin,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  "CREATE ACCOUNT",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    fontSize: 16,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Already have an account? ",
                  style: TextStyle(
                    color: AppColors.text2,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
                    );
                  },
                  child: const Text(
                    "Login",
                    style: TextStyle(
                      color: AppColors.admin,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputAction textInputAction;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  const _PremiumField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    required this.textInputAction,
    this.keyboardType,
    this.onSubmitted,
    this.suffixIcon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: AppColors.text2,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextFormField(
            controller: controller,
            obscureText: obscureText,
            textInputAction: textInputAction,
            keyboardType: keyboardType,
            onFieldSubmitted: onSubmitted,
            validator: validator,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
            decoration: InputDecoration(
              prefixIcon: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.admin.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.admin, size: 20),
              ),
              suffixIcon: suffixIcon,
              hintText: hint,
              hintStyle: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            ),
          ),
        ),
      ],
    );
  }
}
