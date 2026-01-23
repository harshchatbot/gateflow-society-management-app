import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../ui/app_colors.dart';
import '../core/app_logger.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_service.dart';
import '../ui/glass_loader.dart';

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
  State<SuperAdminBulkUploadScreen> createState() => _SuperAdminBulkUploadScreenState();
}

class _SuperAdminBulkUploadScreenState extends State<SuperAdminBulkUploadScreen> {
  final FirebaseAuthService _authService = FirebaseAuthService();
  final FirestoreService _firestore = FirestoreService();

  bool _isUploadingGuards = false;
  bool _isUploadingResidents = false;
  String? _lastUploadStatus;

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
            child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
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
              message: _isUploadingGuards ? "Uploading guards..." : "Uploading residents...",
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
                child: const Icon(Icons.info_rounded, color: AppColors.admin, size: 24),
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
      onUpload: _uploadGuards,
      isUploading: _isUploadingGuards,
    );
  }

  Widget _buildResidentsSection() {
    return _buildUploadSection(
      title: "Residents",
      icon: Icons.people_rounded,
      onDownloadSample: _downloadResidentsSample,
      onUpload: _uploadResidents,
      isUploading: _isUploadingResidents,
    );
  }

  Widget _buildUploadSection({
    required String title,
    required IconData icon,
    required VoidCallback onDownloadSample,
    required VoidCallback onUpload,
    required bool isUploading,
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
                  onPressed: isUploading ? null : onUpload,
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
          const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 24),
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
      // Generate sample CSV content
      const csvContent = '''guardId,name,phone,pin,active
G001,John Doe,9876543210,1234,TRUE
G002,Jane Smith,9876543211,5678,TRUE
G003,Bob Wilson,9876543212,9012,TRUE''';

      await _saveFile('guards_sample.csv', csvContent);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Guards sample CSV downloaded to Downloads folder",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e, stackTrace) {
      AppLogger.e("Error downloading guards sample", error: e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Failed to download sample. Please try again."),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _downloadResidentsSample() async {
    try {
      // Generate sample CSV content
      const csvContent = '''flatNo,residentName,phone,pin,active
A-101,Ramesh Kumar,9876543210,1234,TRUE
A-102,Sunita Sharma,9876543211,5678,TRUE
B-201,Rajesh Patel,9876543212,9012,TRUE
B-202,Priya Singh,9876543213,3456,TRUE''';

      await _saveFile('residents_sample.csv', csvContent);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Residents sample CSV downloaded to Downloads folder",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e, stackTrace) {
      AppLogger.e("Error downloading residents sample", error: e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Failed to download sample. Please try again."),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _saveFile(String fileName, String content) async {
    try {
      // Request storage permission (for Android < 13)
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          // Try manage external storage for Android 11+
          final manageStatus = await Permission.manageExternalStorage.request();
          if (!manageStatus.isGranted) {
            throw Exception("Storage permission denied. Please grant storage permission in settings.");
          }
        }
      }

      // Get downloads directory
      Directory? directory;
      if (Platform.isAndroid) {
        // For Android, try to get Downloads directory
        try {
          directory = Directory('/storage/emulated/0/Download');
          if (!await directory.exists()) {
            // Fallback to external storage directory
            final extDir = await getExternalStorageDirectory();
            if (extDir != null) {
              directory = Directory('${extDir.path}/../Download');
            } else {
              directory = await getApplicationDocumentsDirectory();
            }
          }
        } catch (e) {
          // Fallback to app's external storage
          directory = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      if (directory == null) {
        throw Exception("Could not access storage directory");
      }

      // Ensure directory exists
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final file = File('${directory.path}/$fileName');
      await file.writeAsString(content);
      AppLogger.i("File saved", data: {'path': file.path});
    } catch (e, stackTrace) {
      AppLogger.e("Error saving file", error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // ============================================
  // Upload CSV
  // ============================================

  Future<void> _uploadGuards() async {
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

      setState(() => _isUploadingGuards = true);

      // Parse CSV
      final csvData = const CsvToListConverter().convert(content);
      if (csvData.isEmpty) {
        throw Exception("CSV file is empty");
      }

      // Validate headers
      final headers = csvData[0].map((e) => e.toString().trim().toLowerCase()).toList();
      final requiredHeaders = ['guardid', 'name', 'pin', 'active'];
      for (final header in requiredHeaders) {
        if (!headers.contains(header)) {
          throw Exception("Missing required column: $header");
        }
      }

      // Process rows
      int successCount = 0;
      int errorCount = 0;
      final errors = <String>[];

      for (int i = 1; i < csvData.length; i++) {
        final row = csvData[i];
        if (row.length < headers.length) continue;

        try {
          final guardId = row[headers.indexOf('guardid')].toString().trim();
          final name = row[headers.indexOf('name')].toString().trim();
          final phone = headers.contains('phone') && row.length > headers.indexOf('phone')
              ? row[headers.indexOf('phone')].toString().trim()
              : '';
          final pin = row[headers.indexOf('pin')].toString().trim();
          final activeStr = row[headers.indexOf('active')].toString().trim().toUpperCase();

          if (guardId.isEmpty || name.isEmpty || pin.isEmpty) {
            errors.add("Row ${i + 1}: Missing required fields");
            errorCount++;
            continue;
          }

          final isActive = activeStr == 'TRUE' || activeStr == '1' || activeStr == 'YES';

          // Create Firebase Auth account
          final userCredential = await _authService.createGuardAccount(
            societyId: widget.societyId,
            guardId: guardId,
            pin: pin,
          );

          final uid = userCredential.user?.uid;
          if (uid == null) {
            errors.add("Row ${i + 1}: Failed to create Firebase Auth account");
            errorCount++;
            continue;
          }

          // Create Firestore member document
          await _firestore.setMember(
            societyId: widget.societyId,
            uid: uid,
            systemRole: 'guard',
            name: name,
            phone: phone.isEmpty ? null : phone,
            active: isActive,
          );

          successCount++;
          AppLogger.i("Guard created via bulk upload", data: {'guardId': guardId, 'uid': uid});
        } catch (e, stackTrace) {
          AppLogger.e("Error processing guard row ${i + 1}", error: e, stackTrace: stackTrace);
          errors.add("Row ${i + 1}: ${e.toString()}");
          errorCount++;
        }
      }

      setState(() {
        _isUploadingGuards = false;
        _lastUploadStatus = "Guards: $successCount successful, $errorCount failed";
      });

      if (mounted) {
        _showUploadResults("Guards Upload", successCount, errorCount, errors);
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

  Future<void> _uploadResidents() async {
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

      setState(() => _isUploadingResidents = true);

      // Parse CSV
      final csvData = const CsvToListConverter().convert(content);
      if (csvData.isEmpty) {
        throw Exception("CSV file is empty");
      }

      // Validate headers
      final headers = csvData[0].map((e) => e.toString().trim().toLowerCase()).toList();
      final requiredHeaders = ['flatno', 'residentname', 'phone', 'pin', 'active'];
      for (final header in requiredHeaders) {
        if (!headers.contains(header)) {
          throw Exception("Missing required column: $header");
        }
      }

      // Process rows
      int successCount = 0;
      int errorCount = 0;
      final errors = <String>[];

      for (int i = 1; i < csvData.length; i++) {
        final row = csvData[i];
        if (row.length < headers.length) continue;

        try {
          final flatNo = row[headers.indexOf('flatno')].toString().trim();
          final residentName = row[headers.indexOf('residentname')].toString().trim();
          final phone = row[headers.indexOf('phone')].toString().trim();
          final pin = row[headers.indexOf('pin')].toString().trim();
          final activeStr = row[headers.indexOf('active')].toString().trim().toUpperCase();

          if (flatNo.isEmpty || residentName.isEmpty || phone.isEmpty || pin.isEmpty) {
            errors.add("Row ${i + 1}: Missing required fields");
            errorCount++;
            continue;
          }

          final isActive = activeStr == 'TRUE' || activeStr == '1' || activeStr == 'YES';

          // Create Firebase Auth account
          final userCredential = await _authService.createResidentAccount(
            societyId: widget.societyId,
            flatNo: flatNo,
            phone: phone,
            pin: pin,
          );

          final uid = userCredential.user?.uid;
          if (uid == null) {
            errors.add("Row ${i + 1}: Failed to create Firebase Auth account");
            errorCount++;
            continue;
          }

          // Create Firestore member document
          await _firestore.setMember(
            societyId: widget.societyId,
            uid: uid,
            systemRole: 'resident',
            name: residentName,
            phone: phone,
            flatNo: flatNo,
            active: isActive,
          );

          successCount++;
          AppLogger.i("Resident created via bulk upload", data: {'flatNo': flatNo, 'uid': uid});
        } catch (e, stackTrace) {
          AppLogger.e("Error processing resident row ${i + 1}", error: e, stackTrace: stackTrace);
          errors.add("Row ${i + 1}: ${e.toString()}");
          errorCount++;
        }
      }

      setState(() {
        _isUploadingResidents = false;
        _lastUploadStatus = "Residents: $successCount successful, $errorCount failed";
      });

      if (mounted) {
        _showUploadResults("Residents Upload", successCount, errorCount, errors);
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
                  ...errors.take(5).map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          e,
                          style: TextStyle(fontSize: 11, color: AppColors.text2),
                        ),
                      )),
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
