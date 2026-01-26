import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_logger.dart';
import '../core/app_error.dart';
import '../core/storage.dart';
import '../models/visitor.dart';
import '../services/firebase_visitor_service.dart';

import 'guard_login_screen.dart';

// UI system
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
  final _visitorService = FirebaseVisitorService();
  late ConfettiController _confettiController;

  final ImagePicker _picker = ImagePicker();
  File? _visitorPhoto;

  String _selectedVisitorType = 'GUEST';
  bool _isLoading = false;
  Visitor? _createdVisitor;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 2));
  }

  @override
  void dispose() {
    _flatNoController.dispose();
    _visitorPhoneController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  // --- LOGIC SECTION ---

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _createdVisitor = null;
    });

    final result = (_visitorPhoto != null)
        ? await _visitorService.createVisitorWithPhoto(
            societyId: widget.societyId,
            flatNo: _flatNoController.text.trim(),
            visitorType: _selectedVisitorType,
            visitorPhone: _visitorPhoneController.text.trim(),
            photoFile: _visitorPhoto!,
          )
        : await _visitorService.createVisitor(
            societyId: widget.societyId,
            flatNo: _flatNoController.text.trim(),
            visitorType: _selectedVisitorType,
            visitorPhone: _visitorPhoneController.text.trim(),
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
      final err = result.error ?? AppError(userMessage: 'Failed to create visitor', technicalMessage: 'Unknown');
      AppLogger.e('Visitor creation failed', error: err.technicalMessage);
      _showError(err.userMessage);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  Future<void> _takePhoto() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 75,
        maxWidth: 1080,
      );
      if (picked == null) return;
      setState(() => _visitorPhoto = File(picked.path));
    } catch (e) {
      if (!mounted) return;
      _showError("Camera error. Please allow permission.");
    }
  }

  // --- UI COMPONENTS ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('New Entry', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w900, fontSize: 22)),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 120), // Responsive bottom padding
            child: Form(
              key: _formKey,
              child: Column(
                children: [
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
              numberOfParticles: 25,
              colors: const [AppColors.primary, AppColors.success, Colors.orange],
            ),
          ),
          GlassLoader(show: _isLoading, message: "Syncing with Residents..."),
        ],
      ),
    );
  }

  Widget _buildEntryForm() {
    return Column(
      children: [
        _buildPhotoSection(),
        const SizedBox(height: 20),
        _buildInputCard(),
      ],
    );
  }

  Widget _buildPhotoSection() {
    return Container(
      width: double.infinity,
      height: 220,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: AppColors.text.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: _visitorPhoto == null
            ? InkWell(
                onTap: _takePhoto,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(AppIcons.camera, size: 40, color: AppColors.primary.withOpacity(0.5)),
                    const SizedBox(height: 12),
                    const Text("Capture Visitor Photo", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.text2)),
                  ],
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(_visitorPhoto!, fit: BoxFit.cover),
                  Positioned(
                    top: 12, right: 12,
                    child: CircleAvatar(
                      backgroundColor: Colors.black54,
                      child: IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _takePhoto),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildInputCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFieldLabel("Visitor Mobile"),
          _buildTextField(
            controller: _visitorPhoneController,
            hint: "10-digit mobile number",
            icon: AppIcons.phone,
            isPhone: true,
          ),
          const SizedBox(height: 18),
          _buildFieldLabel("Flat / Unit Number"),
          _buildTextField(
            controller: _flatNoController,
            hint: "e.g. B-402",
            icon: AppIcons.flat,
          ),
          const SizedBox(height: 18),
          _buildFieldLabel("Visitor Category"),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildTypePill("GUEST", AppIcons.guest),
              const SizedBox(width: 8),
              _buildTypePill("DELIVERY", AppIcons.delivery),
              const SizedBox(width: 8),
              _buildTypePill("CAB", AppIcons.cab),
            ],
          ),
          const SizedBox(height: 25),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: const Text("NOTIFY RESIDENT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String hint, required IconData icon, bool isPhone = false}) {
    return TextFormField(
      controller: controller,
      keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
      inputFormatters: isPhone ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)] : [],
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
        filled: true,
        fillColor: AppColors.bg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      ),
      validator: (v) => v!.isEmpty ? "Required" : null,
    );
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.text, fontSize: 13)),
    );
  }

  Widget _buildTypePill(String type, IconData icon) {
    final bool isSelected = _selectedVisitorType == type;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedVisitorType = type),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: isSelected ? Colors.white : AppColors.text2),
              const SizedBox(height: 4),
              Text(type, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : AppColors.text2)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessCard() {
    final v = _createdVisitor!;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.success.withOpacity(0.3))),
      child: Column(
        children: [
          const CircleAvatar(backgroundColor: AppColors.success, radius: 30, child: Icon(Icons.check, color: Colors.white, size: 35)),
          const SizedBox(height: 16),
          const Text("Notification Sent!", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
          const Text("Resident has been alerted.", style: TextStyle(color: AppColors.text2)),
          const Divider(height: 32),
          _buildInfoRow("Flat Number", v.flatNo),
          _buildInfoRow("Category", v.visitorType),
          _buildInfoRow("Status", v.status, isStatus: true),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton(
              onPressed: _clearForm,
              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), side: const BorderSide(color: AppColors.primary)),
              child: const Text("NEW ENTRY", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isStatus = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.bold)),
          isStatus 
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.statusChipBg(value), borderRadius: BorderRadius.circular(8)),
                child: Text(value, style: TextStyle(color: AppColors.statusChipFg(value), fontWeight: FontWeight.bold, fontSize: 12)),
              )
            : Text(value, style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.text)),
        ],
      ),
    );
  }
}