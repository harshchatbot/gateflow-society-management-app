import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';
import '../core/app_logger.dart';
import '../core/app_error.dart';
import '../core/storage.dart';
import '../models/visitor.dart';
import '../services/visitor_service.dart';
import 'guard_login_screen.dart';

import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'visitor_list_screen.dart';



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
  final _flatIdController = TextEditingController();
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
    _confettiController = ConfettiController(duration: const Duration(seconds: 2));
  }

  @override
  void dispose() {
    _flatIdController.dispose();
    _visitorPhoneController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  // --- LOGIC SECTION (Your Code) ---

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _createdVisitor = null;
    });

    // API Call
    final result = (_visitorPhoto != null)
    ? await _visitorService.createVisitorWithPhoto(
        flatId: _flatIdController.text.trim(),
        visitorType: _selectedVisitorType,
        visitorPhone: _visitorPhoneController.text.trim(),
        guardId: widget.guardId,
        photoFile: _visitorPhoto!,
        // authToken: await Storage.getToken(), // only if needed
      )
    : await _visitorService.createVisitor(
        flatId: _flatIdController.text.trim(),
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
      final err = result.error ?? AppError(userMessage: 'Failed to create visitor', technicalMessage: 'Unknown');
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
      _flatIdController.clear();
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

    if (picked == null) return; // cancelled

    setState(() {
      _visitorPhoto = File(picked.path);
    });
  } catch (e) {
    if (!mounted) return;
    _showError("Camera error. Please allow camera permission and try again.");
    AppLogger.e("Camera pick failed", error: e.toString());
  }
}

Widget _buildPhotoSection(ThemeData theme) {
  final photo = _visitorPhoto;

  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFDFE1E6)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Visitor Photo", style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),

        if (photo == null)
          SizedBox(
            width: double.infinity,
            height: 160,
            child: OutlinedButton.icon(
              onPressed: _isLoading ? null : _takePhoto,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text("Take Photo"),
            ),
          )
        else
          Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  photo,
                  height: 220,
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
                      icon: const Icon(Icons.refresh),
                      label: const Text("Retake"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => setState(() => _visitorPhoto = null),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text("Remove"),
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


  // --- UI SECTION (New Salesforce Design) ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
      title: const Text('New Visitor'),

      // 👇 ADD THIS
      actions: [
        IconButton(
          icon: const Icon(Icons.list_alt),
          tooltip: 'View Visitors',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => VisitorListScreen(
                  guardId: guardId, // 👈 use the same guardId already in this screen
                ),
              ),
            );
          },
        ),
      ],
    ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Guard Info Card
                  _buildGuardInfoCard(theme),
                  const SizedBox(height: 16),

                  // 2. Main Content (Form or Success)
                  if (_createdVisitor != null) 
                    _buildSuccessCard(theme)
                  else 
                    _buildEntryForm(theme),
                ],
              ),
            ),
          ),
          
          // Confetti Overlay
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles: 20,
              colors: const [Colors.green, Colors.blue, Colors.orange],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuardInfoCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDFE1E6)), // Subtle border
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: theme.primaryColor.withOpacity(0.1),
            child: Icon(Icons.security, color: theme.primaryColor),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.guardName, style: theme.textTheme.titleMedium),
              Text(
                "ID: ${widget.guardId} • Society: ${widget.societyId}",
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEntryForm(ThemeData theme) {
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Visitor Details", style: theme.textTheme.titleMedium),
          // Photo Section
          _buildPhotoSection(theme),
          const SizedBox(height: 16),

          
          // Flat ID
          TextFormField(
            controller: _flatIdController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: "Flat No",
              hintText: "e.g. A-101",
              prefixIcon: Icon(Icons.home_outlined),
            ),
            validator: (v) => v!.isEmpty ? "Required" : null,
          ),
          const SizedBox(height: 16),

          // Visitor Type Selector
          Text("Visitor Type", style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildTypeCard("GUEST", Icons.person_outline)),
              const SizedBox(width: 8),
              Expanded(child: _buildTypeCard("DELIVERY", Icons.local_shipping_outlined)),
              const SizedBox(width: 8),
              Expanded(child: _buildTypeCard("CAB", Icons.local_taxi_outlined)),
            ],
          ),
          const SizedBox(height: 16),

          // Phone
          TextFormField(
            controller: _visitorPhoneController,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: "Phone Number",
              prefixIcon: Icon(Icons.phone_outlined),
              counterText: "", // Hide counter
            ),
            validator: (v) => v!.length < 10 ? "Invalid Phone" : null,
          ),
          
          const SizedBox(height: 24),
          
          // Action Button
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _handleSubmit,
            icon: _isLoading 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.send),
            label: Text(_isLoading ? "Processing..." : "Send for Approval"),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessCard(ThemeData theme) {
    final v = _createdVisitor!;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 64),
          const SizedBox(height: 16),
          Text("Entry Approved", style: theme.textTheme.headlineMedium),
          Text("Waiting for resident...", style: theme.textTheme.bodySmall),
          const Divider(height: 32),
          
          _buildInfoRow("Visitor Name", "Guest"), // You might add Name field later
          _buildInfoRow("Type", v.visitorType),
          _buildInfoRow("Flat", v.flatId),
          _buildInfoRow("Status", v.status, isStatus: true),
          
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _clearForm,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[800]),
            child: const Text("New Entry"),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeCard(String type, IconData icon) {
    final isSelected = _selectedVisitorType == type;
    final color = isSelected ? Theme.of(context).primaryColor : Colors.grey[200];
    final textColor = isSelected ? Colors.white : Colors.black87;

    return GestureDetector(
      onTap: () => setState(() => _selectedVisitorType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Theme.of(context).primaryColor : Colors.grey[300]!,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.grey[600], size: 22),
            const SizedBox(height: 4),
            Text(
              type, 
              style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isStatus = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          isStatus 
            ? Chip(label: Text(value), backgroundColor: Colors.orange[100], labelStyle: TextStyle(color: Colors.orange[900]))
            : Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}