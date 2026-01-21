import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_logger.dart';
import '../core/app_error.dart';
import '../core/storage.dart';
import '../models/visitor.dart';
import '../services/visitor_service.dart';

import 'guard_login_screen.dart';
import 'visitor_list_screen.dart';

// New UI system
import '../ui/app_colors.dart';
import '../ui/glass_loader.dart';
import '../ui/app_icons.dart';

class NewVisitorScreen extends StatefulWidget {
  final String guardId;
  final String guardName;
  final String societyId;

  const NewVisitorScreen({
    super.key,
    required this.guardId,
    required this.guardName,
    required this.societyId,
  });

  @override
  State<NewVisitorScreen> createState() => _NewVisitorScreenState();
}

class _NewVisitorScreenState extends State<NewVisitorScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _flatNoController = TextEditingController();
  final _visitorPhoneController = TextEditingController();
  final _visitorService = VisitorService();
  late ConfettiController _confettiController;

  final ImagePicker _picker = ImagePicker();
  File? _visitorPhoto;

  String _selectedVisitorType = 'GUEST';
  bool _isLoading = false;
  Visitor? _createdVisitor;

  @override
  void initState() {
    super.initState();
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 2));
  }

  @override
  void dispose() {
    _flatNoController.dispose();
    _visitorPhoneController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  // --- LOGIC SECTION (UNCHANGED) ---

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _createdVisitor = null;
    });

    final result = (_visitorPhoto != null)
        ? await _visitorService.createVisitorWithPhoto(
            flatNo: _flatNoController.text.trim(),
            visitorType: _selectedVisitorType,
            visitorPhone: _visitorPhoneController.text.trim(),
            guardId: widget.guardId,
            photoFile: _visitorPhoto!,
            // authToken: await Storage.getToken(), // only if needed
          )
        : await _visitorService.createVisitor(
            flatNo: _flatNoController.text.trim(),
            visitorType: _selectedVisitorType,
            visitorPhone: _visitorPhoneController.text.trim(),
            guardId: widget.guardId,
          );

    if (!mounted) return;

    if (result.isSuccess) {
      setState(() {
        _isLoading = false;
        _createdVisitor = result.data!;
      });
      _confettiController.play();
    } else {
      setState(() => _isLoading = false);
      final err = result.error ??
          AppError(
              userMessage: 'Failed to create visitor',
              technicalMessage: 'Unknown');
      AppLogger.e('Visitor creation failed', error: err.technicalMessage);
      _showError(err.userMessage);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _clearForm() {
    setState(() {
      _flatNoController.clear();
      _visitorPhoneController.clear();
      _selectedVisitorType = 'GUEST';
      _createdVisitor = null;
      _visitorPhoto = null;
    });
  }

  Future<void> _logout() async {
    await Storage.clearGuardSession();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const GuardLoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 75,
        maxWidth: 1080,
      );

      if (picked == null) return;

      setState(() {
        _visitorPhoto = File(picked.path);
      });
    } catch (e) {
      if (!mounted) return;
      _showError("Camera error. Please allow camera permission and try again.");
      AppLogger.e("Camera pick failed", error: e.toString());
    }
  }

  // --- UI HELPERS (Premium) ---

  Widget _premiumCard({required Widget child, EdgeInsets? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.045),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildPhotoSection() {
    final photo = _visitorPhoto;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Visitor Photo",
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 10),
          if (photo == null)
            SizedBox(
              width: double.infinity,
              height: 150,
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _takePhoto,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  backgroundColor: AppColors.surface,
                ),
                icon: const Icon(AppIcons.camera),
                label: const Text(
                  "Take Photo",
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            )
          else
            Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    photo,
                    height: 210,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _takePhoto,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          backgroundColor: AppColors.surface,
                        ),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text(
                          "Retake",
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isLoading
                            ? null
                            : () => setState(() => _visitorPhoto = null),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: BorderSide(color: AppColors.error.withOpacity(0.28)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          backgroundColor: AppColors.surface,
                        ),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text(
                          "Remove",
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTypePill(String type, IconData icon) {
    final isSelected = _selectedVisitorType == type;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedVisitorType = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primarySoft : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? AppColors.primarySoft : AppColors.border,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 22,
                color: isSelected ? AppColors.primary : AppColors.text2,
              ),
              const SizedBox(height: 6),
              Text(
                type,
                style: TextStyle(
                  color: isSelected ? AppColors.primary : AppColors.text2,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntryForm() {
    return _premiumCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Visitor Details",
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w900,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Fill the details and send for resident approval.",
            style: TextStyle(
              fontSize: 12.2,
              fontWeight: FontWeight.w600,
              color: AppColors.text2,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 14),

          _buildPhotoSection(),
          const SizedBox(height: 14),

          // Flat No
          Container(
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: TextFormField(
              controller: _flatNoController,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              style: const TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w700,
                fontSize: 14.5,
              ),
              decoration: const InputDecoration(
                labelText: "Flat No",
                hintText: "e.g. A-101",
                prefixIcon: Icon(AppIcons.flat, color: AppColors.text2),
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
              validator: (v) => v!.isEmpty ? "Required" : null,
            ),
          ),
          const SizedBox(height: 14),

          // Visitor Type
          const Text(
            "Visitor Type",
            style: TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w900,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildTypePill("GUEST", AppIcons.guest),
              const SizedBox(width: 10),
              _buildTypePill("DELIVERY", AppIcons.delivery),
              const SizedBox(width: 10),
              _buildTypePill("CAB", AppIcons.cab),
            ],
          ),
          const SizedBox(height: 14),

          // Phone
          Container(
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: TextFormField(
              controller: _visitorPhoneController,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w700,
                fontSize: 14.5,
              ),
              decoration: const InputDecoration(
                labelText: "Phone Number",
                prefixIcon: Icon(AppIcons.phone, color: AppColors.text2),
                counterText: "",
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
              validator: (v) => v!.length < 10 ? "Invalid Phone" : null,
            ),
          ),

          const SizedBox(height: 16),

          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _handleSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.send_rounded),
              label: const Text(
                "Send for Approval",
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isStatus = false}) {
    Color chipBg = AppColors.warning.withOpacity(0.16);
    Color chipFg = AppColors.warning;

    if (value.toUpperCase().contains("APPROV")) {
      chipBg = AppColors.success.withOpacity(0.16);
      chipFg = AppColors.success;
    } else if (value.toUpperCase().contains("REJECT")) {
      chipBg = AppColors.error.withOpacity(0.14);
      chipFg = AppColors.error;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          isStatus
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: chipBg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: chipFg.withOpacity(0.25)),
                  ),
                  child: Text(
                    value,
                    style: TextStyle(
                      color: chipFg,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                )
              : Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.text,
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildSuccessCard() {
    final theme = Theme.of(context);
    final v = _createdVisitor!;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.success.withOpacity(0.28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 64,
            width: 64,
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.success.withOpacity(0.18)),
            ),
            child: const Icon(Icons.check_rounded,
                color: AppColors.success, size: 34),
          ),
          const SizedBox(height: 12),
          Text(
            "Entry Created",
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Waiting for resident approval…",
            style: TextStyle(
              color: AppColors.text2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          const Divider(height: 18),

          _buildInfoRow("Visitor Name", "Guest"),
          _buildInfoRow("Type", v.visitorType),
          _buildInfoRow("Flat", v.flatId),
          _buildInfoRow("Status", v.status, isStatus: true),

          const SizedBox(height: 16),

          SizedBox(
            height: 52,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _clearForm,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.text,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                "New Entry",
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        surfaceTintColor: AppColors.bg,
        title: const Text(
          'New Visitor',
          style: TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt, color: AppColors.text),
            tooltip: 'View Visitors',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VisitorListScreen(
                    guardId: widget.guardId,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.text),
            tooltip: 'Logout',
            onPressed: _isLoading ? null : _logout,
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primarySoft.withOpacity(0.75),
                    AppColors.bg,
                  ],
                ),
              ),
            ),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Guard info
                  _premiumCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Container(
                          height: 44,
                          width: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Icon(Icons.security_rounded,
                              color: AppColors.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.guardName,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.text,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "ID: ${widget.guardId} • Society: ${widget.societyId}",
                                style: const TextStyle(
                                  fontSize: 12.2,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.text2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  if (_createdVisitor != null) _buildSuccessCard() else _buildEntryForm(),
                ],
              ),
            ),
          ),

          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles: 20,
              colors: const [Colors.green, Colors.blue, Colors.orange],
            ),
          ),

          GlassLoader(
            show: _isLoading,
            message: "Creating entry…",
          ),
        ],
      ),
    );
  }
}
