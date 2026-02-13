import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../ui/app_colors.dart';
import '../ui/app_loader.dart';
import '../services/firestore_service.dart';
import '../core/app_logger.dart';
import '../core/society_modules.dart';
import '../widgets/module_disabled_placeholder.dart';

/// Guard Report Violation Screen
/// Reports parking / fire-lane violations. Private – no names publicised.
class GuardReportViolationScreen extends StatefulWidget {
  final String guardId;
  final String societyId;
  final VoidCallback? onBackPressed;

  const GuardReportViolationScreen({
    super.key,
    required this.guardId,
    required this.societyId,
    this.onBackPressed,
  });

  @override
  State<GuardReportViolationScreen> createState() =>
      _GuardReportViolationScreenState();
}

class _GuardReportViolationScreenState
    extends State<GuardReportViolationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _flatController = TextEditingController();
  final _noteController = TextEditingController();
  final FirestoreService _firestore = FirestoreService();
  final ImagePicker _picker = ImagePicker();

  String _violationType = FirestoreService.violationTypeParking;
  File? _photo;
  bool _isLoading = false;
  bool _isSuccess = false;

  static const _types = [
    (
      FirestoreService.violationTypeParking,
      'Parking',
      Icons.directions_car_rounded
    ),
    (
      FirestoreService.violationTypeFireLane,
      'Fire lane',
      Icons.local_fire_department_rounded
    ),
    (FirestoreService.violationTypeOther, 'Other', Icons.warning_rounded),
  ];

  @override
  void dispose() {
    _flatController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final x = await _picker.pickImage(
          source: ImageSource.camera, imageQuality: 80, maxWidth: 1200);
      if (x != null) setState(() => _photo = File(x.path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Camera error: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<String?> _uploadPhoto() async {
    if (_photo == null) return null;
    final uid = const Uuid().v4();
    final ref = FirebaseStorage.instance
        .ref()
        .child('societies/${widget.societyId}/violations/$uid.jpg');
    await ref.putFile(_photo!);
    return ref.getDownloadURL();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _isSuccess = false;
    });
    try {
      String? photoUrl;
      try {
        photoUrl = await _uploadPhoto();
      } catch (e) {
        AppLogger.w('Violation photo upload failed', error: e.toString());
      }
      await _firestore.createViolation(
        societyId: widget.societyId,
        guardUid: widget.guardId,
        flatNo: _flatController.text.trim(),
        violationType: _violationType,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        photoUrl: photoUrl,
      );
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isSuccess = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Violation reported. Data is private.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _flatController.clear();
      _noteController.clear();
      setState(() => _photo = null);
    } catch (e, st) {
      AppLogger.e('Report violation failed', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!SocietyModules.isEnabled(SocietyModuleIds.violations)) {
      return ModuleDisabledPlaceholder(onBack: widget.onBackPressed);
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Report Violation',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (widget.onBackPressed != null) {
              widget.onBackPressed!();
            } else if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.lock_rounded,
                            color: AppColors.warning, size: 24),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Violations are private. No names are publicised. Only admins see full data; residents see only their flat.',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text2),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('Flat / Unit',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text2)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _flatController,
                    decoration: InputDecoration(
                      hintText: 'e.g. B-402',
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none),
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 20),
                  const Text('Violation type',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text2)),
                  const SizedBox(height: 8),
                  Row(
                    children: _types.map((t) {
                      final isSelected = _violationType == t.$1;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InkWell(
                            onTap: () => setState(() => _violationType = t.$1),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.border),
                              ),
                              child: Column(
                                children: [
                                  Icon(t.$3,
                                      size: 22,
                                      color: isSelected
                                          ? Colors.white
                                          : AppColors.text2),
                                  const SizedBox(height: 4),
                                  Text(t.$2,
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: isSelected
                                              ? Colors.white
                                              : AppColors.text2)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  const Text('Note (optional)',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text2)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _noteController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Brief note...',
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Photo (optional)',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text2)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _photo == null ? _pickImage : null,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 120,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: _photo != null
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.file(_photo!, fit: BoxFit.cover),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: IconButton(
                                    icon: const Icon(Icons.close,
                                        color: Colors.white),
                                    onPressed: () =>
                                        setState(() => _photo = null),
                                    style: IconButton.styleFrom(
                                        backgroundColor: Colors.black54),
                                  ),
                                ),
                              ],
                            )
                          : const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_a_photo,
                                      color: AppColors.textMuted, size: 36),
                                  SizedBox(height: 8),
                                  Text('Tap to add photo',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textMuted,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading || _isSuccess ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: _isSuccess
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                  Icon(Icons.check, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text('Reported')
                                ])
                          : Text(
                              _isLoading ? 'Submitting...' : 'Submit report'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading)
            AppLoader.overlay(
                showAfter: const Duration(milliseconds: 300),
                show: true,
                message: 'Submitting...'),
        ],
      ),
    );
  }
}
