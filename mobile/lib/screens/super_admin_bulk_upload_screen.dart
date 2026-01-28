import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../ui/app_colors.dart';
import '../core/app_logger.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_service.dart';
import '../ui/glass_loader.dart';
import '../utils/csv_validators.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:cloud_firestore/cloud_firestore.dart';   // FirebaseFirestore, FieldValue, SetOptions
import 'package:firebase_auth/firebase_auth.dart';       // FirebaseAuth
import '../core/invite_utils.dart';                       // normalizeEmail, inviteKeyFromEmail


// ✅ ADDED
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart'; // adjust path if needed

/// Super Admin Bulk Upload Screen
///
/// Allows Super Admin to bulk upload guards and residents via CSV files.
/// Features:
/// - Download sample CSV templates
/// - Upload and parse CSV files
/// - Create Firebase Auth accounts + Firestore member documents
/// - Show upload progress and results
class SuperAdminBulkUploadScreen extends StatefulWidget {
  final String societyId;
  final String adminId;

  const SuperAdminBulkUploadScreen({
    super.key,
    required this.societyId,
    required this.adminId,
  });

  @override
  State<SuperAdminBulkUploadScreen> createState() =>
      _SuperAdminBulkUploadScreenState();
}

class _SuperAdminBulkUploadScreenState
    extends State<SuperAdminBulkUploadScreen> {
  final FirebaseAuthService _authService = FirebaseAuthService();
  final FirestoreService _firestore = FirestoreService();

  bool _isUploadingGuards = false;
  bool _isUploadingResidents = false;
  String? _lastUploadStatus;

  // Validation state
  ValidationResult? _guardsValidationResult;
  ValidationResult? _residentsValidationResult;
  String? _selectedGuardsCsvPath;
  String? _selectedResidentsCsvPath;

  // ✅ Secondary Auth (prevents current session from switching during createUser)
  FirebaseAuth? _secondaryAuth;
  FirebaseApp? _secondaryApp;

  // ✅ FIX: add missing method (keeps existing flow unchanged)
  // Ensures Firebase password requirement (>= 6 chars) always passes.
  String _generateTempPassword() {
    return 'Tmp@${DateTime.now().millisecondsSinceEpoch}';
  }

  // ✅ NEW: Secondary Firebase Auth helpers
  Future<FirebaseAuth> _getSecondaryAuth() async {
    if (_secondaryAuth != null) return _secondaryAuth!;

    final appName = 'secondary-${DateTime.now().millisecondsSinceEpoch}';
    _secondaryApp = await Firebase.initializeApp(
      name: appName,
      options: DefaultFirebaseOptions.currentPlatform,
    );

    _secondaryAuth = FirebaseAuth.instanceFor(app: _secondaryApp!);
    return _secondaryAuth!;
  }

  Future<void> _disposeSecondaryAuth() async {
    try {
      if (_secondaryAuth != null) {
        await _secondaryAuth!.signOut();
      }
      if (_secondaryApp != null) {
        await _secondaryApp!.delete();
      }
    } catch (_) {
      // ignore cleanup issues
    } finally {
      _secondaryAuth = null;
      _secondaryApp = null;
    }
  }

  @override
  void dispose() {
    _disposeSecondaryAuth();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.admin,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_back_rounded,
                color: Colors.white, size: 20),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Bulk Upload Members",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
      ),
      body: Stack(
        children: [
          // Gradient Background
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.admin.withOpacity(0.1),
                    AppColors.bg,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildInfoCard(),
                  const SizedBox(height: 24),
                  _buildGuardsSection(),
                  const SizedBox(height: 24),
                  _buildResidentsSection(),
                  const SizedBox(height: 24),
                  if (_lastUploadStatus != null) _buildLastUploadStatus(),
                  const SizedBox(height: 120), // Bottom nav spacer
                ],
              ),
            ),
          ),
          if (_isUploadingGuards || _isUploadingResidents)
            GlassLoader(
              show: true,
              message: _isUploadingGuards
                  ? "Uploading guards..."
                  : "Uploading residents...",
            ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.admin.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.info_rounded,
                    color: AppColors.admin, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "Bulk Upload Instructions",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInstructionItem(
            "1. Download the sample CSV template",
            Icons.download_rounded,
          ),
          const SizedBox(height: 8),
          _buildInstructionItem(
            "2. Fill in member details following the template",
            Icons.edit_rounded,
          ),
          const SizedBox(height: 8),
          _buildInstructionItem(
            "3. Upload the CSV file to import members",
            Icons.upload_rounded,
          ),
          const SizedBox(height: 8),
          _buildInstructionItem(
            "4. Review the upload results",
            Icons.check_circle_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionItem(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.text2),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.text2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGuardsSection() {
    return _buildUploadSection(
      title: "Guards",
      icon: Icons.security_rounded,
      onDownloadSample: _downloadGuardsSample,
      onUpload: _validateAndUploadGuards,
      isUploading: _isUploadingGuards,
      validationResult: _guardsValidationResult,
    );
  }

  Widget _buildResidentsSection() {
    return _buildUploadSection(
      title: "Residents",
      icon: Icons.people_rounded,
      onDownloadSample: _downloadResidentsSample,
      onUpload: _validateAndUploadResidents,
      isUploading: _isUploadingResidents,
      validationResult: _residentsValidationResult,
    );
  }

  Widget _buildUploadSection({
    required String title,
    required IconData icon,
    required VoidCallback onDownloadSample,
    required VoidCallback onUpload,
    required bool isUploading,
    ValidationResult? validationResult,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.admin.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.admin, size: 24),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isUploading ? null : onDownloadSample,
                  icon: const Icon(Icons.download_rounded, size: 20),
                  label: const Text(
                    "Download Sample",
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    foregroundColor: AppColors.text,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (isUploading ||
                          (validationResult != null &&
                              !validationResult.hasValidRows))
                      ? null
                      : onUpload,
                  icon: const Icon(Icons.upload_rounded, size: 20),
                  label: const Text(
                    "Upload CSV",
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.admin,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Show validation summary if available
          if (validationResult != null) ...[
            const SizedBox(height: 16),
            _buildValidationSummary(validationResult, title),
          ],
        ],
      ),
    );
  }

  Widget _buildLastUploadStatus() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              color: AppColors.success, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _lastUploadStatus!,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.success,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // Download Sample CSV
  // ============================================

  Future<void> _downloadGuardsSample() async {
    try {
      // Generate sample CSV content (new format with email)
      const csvContent = '''name,email,phone,shift,employeeId
"John Doe","john.doe@example.com","9876543210","Morning","G001"
"Jane Smith","jane.smith@example.com","9876543211","Evening","G002"
"Bob Wilson","bob.wilson@example.com","9876543212","Night","G003"''';

      await _generateAndShareSample('guards_sample.csv', csvContent, 'Guards');
    } catch (e, stackTrace) {
      AppLogger.e("Error generating guards sample", error: e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Failed to generate sample. Please try again."),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _downloadResidentsSample() async {
    try {
      // Generate sample CSV content (new format with email)
      const csvContent = '''name,email,phone,flatNo,tower,role
Ramesh Kumar,ramesh.kumar@example.com,9876543210,A-101,Tower A,owner
Sunita Sharma,sunita.sharma@example.com,9876543211,A-102,Tower A,resident
Rajesh Patel,rajesh.patel@example.com,9876543212,B-201,Tower B,owner
Priya Singh,priya.singh@example.com,9876543213,B-202,Tower B,tenant''';

      await _generateAndShareSample(
          'residents_sample.csv', csvContent, 'Residents');
    } catch (e, stackTrace) {
      AppLogger.e("Error generating residents sample",
          error: e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Failed to generate sample. Please try again."),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Generate CSV sample and share it via system share sheet
  ///
  /// Saves to app-specific temporary directory (no permissions needed)
  /// and opens share sheet so admin can email/upload to Drive/WhatsApp
  Future<void> _generateAndShareSample(
      String fileName, String content, String type) async {
    try {
      // Get app-specific temporary directory (no permissions needed)
      final tempDir = await getTemporaryDirectory();

      // Ensure directory exists
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }

      // Save CSV to temporary directory
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(content);
      AppLogger.i("Sample CSV generated", data: {'path': file.path, 'type': type});

      // Share the file via system share sheet
      final xFile = XFile(file.path);
      await Share.shareXFiles(
        [xFile],
        text: '$type sample CSV template',
        subject: '$type Sample CSV - Sentinel',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Sample ready. Share it via email or Drive to edit on desktop.",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e, stackTrace) {
      AppLogger.e("Error generating and sharing sample",
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // ============================================
  // Validation Summary Widget
  // ============================================

  Widget _buildValidationSummary(ValidationResult result, String type) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: result.hasValidRows
            ? AppColors.success.withOpacity(0.1)
            : AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: result.hasValidRows
              ? AppColors.success.withOpacity(0.3)
              : AppColors.error.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.hasValidRows
                    ? Icons.check_circle_rounded
                    : Icons.error_rounded,
                color:
                    result.hasValidRows ? AppColors.success : AppColors.error,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                "Validation Results",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: result.hasValidRows
                      ? AppColors.success
                      : AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatItem("Total", result.totalRows.toString(), AppColors.text2),
              _buildStatItem("Valid", result.validCount.toString(), AppColors.success),
              _buildStatItem("Invalid", result.invalidCount.toString(), AppColors.error),
            ],
          ),
          if (result.invalidCount > 0) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => _showValidationErrors(result, type),
              icon: const Icon(Icons.error_outline_rounded, size: 18),
              label: const Text(
                "View Errors",
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.error,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
          if (result.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...result.warnings.take(2).map(
              (warning) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 16, color: AppColors.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        warning,
                        style:
                            const TextStyle(fontSize: 12, color: AppColors.warning),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.text2,
          ),
        ),
      ],
    );
  }

  void _showValidationErrors(ValidationResult result, String type) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          "$type Validation Errors",
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${result.invalidCount} row(s) have errors:",
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 12),
                ...result.invalidRows.map(
                  (error) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.error.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.error_rounded,
                                size: 16, color: AppColors.error),
                            const SizedBox(width: 8),
                            Text(
                              "Row ${error.rowNumber}",
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: AppColors.error,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          error.reason,
                          style: const TextStyle(fontSize: 12, color: AppColors.text),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.admin,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("OK", style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  // ============================================
  // Validate and Upload CSV
  // ============================================

  Future<void> _validateAndUploadGuards() async {
    if (_guardsValidationResult == null || !_guardsValidationResult!.hasValidRows) {
      // First, pick and validate file
      await _pickAndValidateGuardsCsv();
      return;
    }

    // If validation passed, proceed with upload
    await _uploadGuardsFromValidated();
  }

  Future<void> _validateAndUploadResidents() async {
    if (_residentsValidationResult == null || !_residentsValidationResult!.hasValidRows) {
      // First, pick and validate file
      await _pickAndValidateResidentsCsv();
      return;
    }

    // If validation passed, proceed with upload
    await _uploadResidentsFromValidated();
  }

  Future<void> _pickAndValidateGuardsCsv() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null || result.files.single.path == null) {
        return; // User cancelled
      }

      final filePath = result.files.single.path!;
      final file = File(filePath);
      final content = await file.readAsString();

      // Validate CSV
      final validationResult = CsvValidators.validateGuardsCsv(content);

      setState(() {
        _guardsValidationResult = validationResult;
        _selectedGuardsCsvPath = filePath;
      });

      // Show validation results
      if (validationResult.invalidCount > 0) {
        _showValidationErrors(validationResult, 'Guards');
      }

      // If valid rows exist, ask user to confirm upload
      if (validationResult.hasValidRows) {
        final shouldUpload = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text(
              "Ready to Upload",
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            content: Text(
              "Found ${validationResult.validCount} valid guard(s). Proceed with upload?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.admin,
                  foregroundColor: Colors.white,
                ),
                child: const Text("Upload", style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        );

        if (shouldUpload == true) {
          await _uploadGuardsFromValidated();
        }
      }
    } catch (e, stackTrace) {
      AppLogger.e("Error validating guards CSV", error: e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Validation failed: ${e.toString()}"),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _pickAndValidateResidentsCsv() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null || result.files.single.path == null) {
        return; // User cancelled
      }

      final filePath = result.files.single.path!;
      final file = File(filePath);
      final content = await file.readAsString();

      // Validate CSV
      final validationResult = CsvValidators.validateResidentsCsv(content);

      setState(() {
        _residentsValidationResult = validationResult;
        _selectedResidentsCsvPath = filePath;
      });

      // Show validation results
      if (validationResult.invalidCount > 0) {
        _showValidationErrors(validationResult, 'Residents');
      }

      // If valid rows exist, ask user to confirm upload
      if (validationResult.hasValidRows) {
        final shouldUpload = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text(
              "Ready to Upload",
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            content: Text(
              "Found ${validationResult.validCount} valid resident(s). Proceed with upload?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.admin,
                  foregroundColor: Colors.white,
                ),
                child: const Text("Upload", style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        );

        if (shouldUpload == true) {
          await _uploadResidentsFromValidated();
        }
      }
    } catch (e, stackTrace) {
      AppLogger.e("Error validating residents CSV", error: e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Validation failed: ${e.toString()}"),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ============================================
  // Upload CSV (using validated rows)
  // ============================================

  Future<void> _uploadGuardsFromValidated() async {
    if (_guardsValidationResult == null || !_guardsValidationResult!.hasValidRows) {
      return;
    }

    final validRows = _guardsValidationResult!.validRows;
    setState(() => _isUploadingGuards = true);

    try {
      int successCount = 0;
      int errorCount = 0;
      final errors = <String>[];
      final createdUsers = <Map<String, String>>[];

      // ✅ Create Secondary Auth once for the entire run
      final secondaryAuth = await _getSecondaryAuth();

      // Process each validated row
      for (int i = 0; i < validRows.length; i++) {
        final row = validRows[i];
        final rowNumber = i + 1;

        try {
          final name = row['name']!;
          final email = row['email']!;
          final phone = row['phone']!;

          // Use employeeId as guardId if available, otherwise generate from email
          final guardId = row['employeeid']?.isNotEmpty == true
              ? row['employeeid']!
              : email.split('@').first.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');

          // ✅ IMPORTANT: Create user using secondary auth so current session doesn't switch
          final tempPassword = _generateTempPassword();
          final userCredential = await secondaryAuth.createUserWithEmailAndPassword(
            email: email.trim(),
            password: tempPassword,
          );

          // ✅ Send reset email from secondary auth
          await secondaryAuth.sendPasswordResetEmail(email: email.trim());

          final uid = userCredential.user?.uid;
          if (uid == null) {
            errors.add("Row $rowNumber: Failed to create Firebase Auth account");
            errorCount++;
            continue;
          }

          // Create Firestore member document (runs as super admin session, not switched)
          // ✅ Invite-only model: bulk upload writes ONLY invites.
          // The guard will "claim" after login using InviteClaimService.
          final emailNorm = normalizeEmail(email);
          final inviteKey = inviteKeyFromEmail(emailNorm);
          final societyRole = (row['societyrole'] ?? '').toString().trim().toLowerCase();
          final flatNo   = (row['flatno'] ?? '').toString().trim();


          final inviteRef = FirebaseFirestore.instance
              .collection('societies')
              .doc(widget.societyId)
              .collection('invites')
              .doc(inviteKey);

          await inviteRef.set({
            'email': emailNorm,
            'systemRole': 'resident',
            'societyRole': societyRole.isEmpty ? null : societyRole,
            'flatNo': flatNo.isEmpty ? null : flatNo,
            'status': 'pending',
            'active': true,
            'createdAt': FieldValue.serverTimestamp(),
          });


          createdUsers.add({
            'inviteKey': inviteKeyFromEmail(email),
            'name': name,
            'phone': phone,
            'type': 'Guard',
            'email': email,
            'status': 'pending',
          });


          successCount++;
          AppLogger.i("Guard invite created via bulk upload", data: {
            'inviteKey': inviteKeyFromEmail(email),
            'email': email,
          });

        } catch (e, stackTrace) {
          AppLogger.e("Error processing guard row $rowNumber", error: e, stackTrace: stackTrace);
          errors.add("Row $rowNumber: ${e.toString()}");
          errorCount++;
        }
      }

      await _disposeSecondaryAuth();

      setState(() {
        _isUploadingGuards = false;
        _lastUploadStatus = "Guards: $successCount successful, $errorCount failed";
      });

      if (mounted) {
        _showUploadResults("Guards Upload", successCount, errorCount, errors);

        if (successCount > 0 && createdUsers.isNotEmpty) {
          await _generateAndShareUserCredentials(createdUsers, 'Guards');
        }
      }
    } catch (e, stackTrace) {
      AppLogger.e("Error uploading guards CSV", error: e, stackTrace: stackTrace);
      setState(() => _isUploadingGuards = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Upload failed: ${e.toString()}"),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _uploadResidentsFromValidated() async {
    if (_residentsValidationResult == null || !_residentsValidationResult!.hasValidRows) {
      return;
    }

    final validRows = _residentsValidationResult!.validRows;
    setState(() => _isUploadingResidents = true);

    try {
      int successCount = 0;
      int errorCount = 0;
      final errors = <String>[];
      final createdUsers = <Map<String, String>>[];

      // ✅ Create Secondary Auth once for the entire run
      final secondaryAuth = await _getSecondaryAuth();

      for (int i = 0; i < validRows.length; i++) {
        final row = validRows[i];
        final rowNumber = i + 1;

        try {
          final name = row['name']!;
          final email = row['email']!;
          final phone = row['phone']!;
          final flatNo = row['flatno']!;
          final role = row['role'] ?? 'resident';

          // ✅ IMPORTANT: Create user using secondary auth so current session doesn't switch
          final tempPassword = _generateTempPassword();
          final userCredential = await secondaryAuth.createUserWithEmailAndPassword(
            email: email.trim(),
            password: tempPassword,
          );

          // ✅ Send reset email from secondary auth
          await secondaryAuth.sendPasswordResetEmail(email: email.trim());

          final uid = userCredential.user?.uid;
          if (uid == null) {
            errors.add("Row $rowNumber: Failed to create Firebase Auth account");
            errorCount++;
            continue;
          }

          final emailNorm = normalizeEmail(email);
final inviteKey = inviteKeyFromEmail(emailNorm);

final inviteRef = FirebaseFirestore.instance
    .collection('societies')
    .doc(widget.societyId)
    .collection('invites')
    .doc(inviteKey);

        await inviteRef.set({
          'email': emailNorm,
          'systemRole': 'resident',
          'societyRole': role,                 // e.g. president/secretary/etc or null
          'flatNo': flatNo.isEmpty ? null : flatNo,
          'status': 'pending',
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
          'createdByUid': FirebaseAuth.instance.currentUser?.uid,

          // Optional metadata (helps admin UI before claim)
          'meta': {
            'name': name,
            'phone': phone,
            'tower': row['tower'],
          },
        }, SetOptions(merge: true));

        AppLogger.i("Resident invite created via bulk upload", data: {
          'inviteKey': inviteKey,
          'email': emailNorm,
          'flatNo': flatNo,
          'role': role,
        });


          createdUsers.add({
            'inviteKey': inviteKey,
            'name': name,
            'phone': phone,
            'type': 'Resident',
            'email': emailNorm,
            'flatNo': flatNo,
            'status': 'pending',
          });


          successCount++;
          AppLogger.i("Resident created via bulk upload", data: {'flatNo': flatNo, 'uid': uid});
        } catch (e, stackTrace) {
          AppLogger.e("Error processing resident row $rowNumber", error: e, stackTrace: stackTrace);
          errors.add("Row $rowNumber: ${e.toString()}");
          errorCount++;
        }
      }

      await _disposeSecondaryAuth();

      setState(() {
        _isUploadingResidents = false;
        _lastUploadStatus = "Residents: $successCount successful, $errorCount failed";
      });

      if (mounted) {
        _showUploadResults("Residents Upload", successCount, errorCount, errors);

        if (successCount > 0 && createdUsers.isNotEmpty) {
          await _generateAndShareUserCredentials(createdUsers, 'Residents');
        }
      }
    } catch (e, stackTrace) {
      AppLogger.e("Error uploading residents CSV", error: e, stackTrace: stackTrace);
      setState(() => _isUploadingResidents = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Upload failed: ${e.toString()}"),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ============================================
  // Legacy Upload Methods (kept for reference, but should use validated versions)
  // ============================================
  //
  // NOTE: Kept untouched as requested.
  //

  Future<void> _uploadGuards() async {
    // kept unchanged
  }

  Future<void> _uploadResidents() async {
    // kept unchanged
  }

  /// Generate user credentials summary CSV and share via email
  ///
  /// Creates a CSV with user IDs, names, login credentials, and password reset instructions
  /// Admin can email this to users or use it to send individual password reset emails
  Future<void> _generateAndShareUserCredentials(
    List<Map<String, String>> users,
    String userType,
  ) async {
    try {
      final csvBuffer = StringBuffer();

      // CSV Header
      csvBuffer.writeln('User ID,Name,Phone,Email,Login Instructions,Password Reset');

      for (final user in users) {
        final userId = user['userId'] ?? 'N/A';
        final name = user['name'] ?? 'N/A';
        final phone = user['phone'] ?? 'N/A';
        final email = user['email'] ?? 'N/A';
        final type = user['type'] ?? userType;

        String loginInstructions;
        if (type == 'Guard') {
          loginInstructions =
              'Open email ($email) and set password using the reset link. Then login with Email + Password.';
        } else {
          loginInstructions =
              'Open email ($email) and set password using the reset link. Then login with Email + Password.';
        }

        final passwordReset =
            'Password setup email sent automatically. If not received, use “Forgot password” on login screen.';

        String escapeCsv(String value) {
          if (value.contains(',') || value.contains('"') || value.contains('\n')) {
            return '"${value.replaceAll('"', '""')}"';
          }
          return value;
        }

        csvBuffer.writeln([
          escapeCsv(userId),
          escapeCsv(name),
          escapeCsv(phone),
          escapeCsv(email),
          escapeCsv(loginInstructions),
          escapeCsv(passwordReset),
        ].join(','));
      }

      csvBuffer.writeln('');
      csvBuffer.writeln('--- IMPORTANT INSTRUCTIONS ---');
      csvBuffer.writeln('1. Share this file with users via email');
      csvBuffer.writeln('2. Users can use their User ID and PIN to login');
      csvBuffer.writeln('3. For password reset, users should contact society admin');
      csvBuffer.writeln('4. User IDs are: ${users.map((u) => u['userId']).join(", ")}');

      final csvContent = csvBuffer.toString();

      final tempDir = await getTemporaryDirectory();
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }

      final fileName = '${userType.toLowerCase()}_credentials_${DateTime.now().millisecondsSinceEpoch}.csv';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(csvContent);
      AppLogger.i("User credentials CSV generated", data: {'path': file.path, 'userCount': users.length});

      final xFile = XFile(file.path);
      await Share.shareXFiles(
        [xFile],
        text:
            '$userType Credentials - Sentinel\n\n${users.length} users created successfully.\n\nPlease share this file with users via email. Each user will receive their User ID and login instructions.',
        subject: '$userType Account Credentials - Sentinel Bulk Upload',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.email_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "User credentials ready. Share via email to send password reset info.",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.admin,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e, stackTrace) {
      AppLogger.e("Error generating user credentials", error: e, stackTrace: stackTrace);
    }
  }

  void _showUploadResults(String title, int successCount, int errorCount, List<String> errors) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    "Successful: $successCount",
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.success),
                  ),
                ],
              ),
              if (errorCount > 0) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.error_rounded, color: AppColors.error, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      "Failed: $errorCount",
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.error),
                    ),
                  ],
                ),
                if (errors.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    "Errors:",
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  ...errors.take(5).map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        e,
                        style: TextStyle(fontSize: 11, color: AppColors.text2),
                      ),
                    ),
                  ),
                  if (errors.length > 5)
                    Text(
                      "... and ${errors.length - 5} more",
                      style: TextStyle(fontSize: 11, color: AppColors.text2),
                    ),
                ],
              ],
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.admin,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("OK", style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}
