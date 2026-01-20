import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gateflow/core/app_error.dart';
import 'package:gateflow/core/app_logger.dart';
import 'package:gateflow/models/visitor.dart';
import 'package:gateflow/services/visitor_service.dart';
import 'package:gateflow/widgets/app_text_field.dart';
import 'package:gateflow/widgets/primary_button.dart';
import 'package:gateflow/widgets/section_card.dart';
import 'package:gateflow/widgets/status_chip.dart';

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
  final _flatIdController = TextEditingController();
  final _visitorPhoneController = TextEditingController();
  final _visitorService = VisitorService();
  final _confettiController = ConfettiController(duration: const Duration(seconds: 1));

  String _selectedVisitorType = 'GUEST';
  bool _isLoading = false;
  Visitor? _createdVisitor;

  @override
  void dispose() {
    _flatIdController.dispose();
    _visitorPhoneController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _createdVisitor = null;
    });

    final result = await _visitorService.createVisitor(
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
        content: Text(message, style: const TextStyle(fontSize: 16)),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _clearForm() {
    setState(() {
      _flatIdController.clear();
      _visitorPhoneController.clear();
      _selectedVisitorType = 'GUEST';
      _createdVisitor = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Visitor'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildGuardInfo(colorScheme),
                    const SizedBox(height: 16),
                    if (_createdVisitor != null) _buildSuccessCard(colorScheme),
                    if (_createdVisitor == null) _buildFormCard(colorScheme),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              maxBlastForce: 8,
              minBlastForce: 4,
              emissionFrequency: 0.1,
              numberOfParticles: 20,
              gravity: 0.3,
              colors: [
                colorScheme.primary,
                Colors.green,
                Colors.orange,
                Colors.blueGrey,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuardInfo(ColorScheme colorScheme) {
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: colorScheme.primary.withOpacity(0.12),
            child: Icon(Icons.person, color: colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.guardName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Guard ID: ${widget.guardId}',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                Text(
                  'Society: ${widget.societyId}',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard(ColorScheme colorScheme) {
    return SectionCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Visitor Details',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Enter visitor info and send for resident approval.',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          AppTextField(
            controller: _flatIdController,
            label: 'Flat ID',
            hint: 'flat_101',
            icon: Icons.home,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter flat ID';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          Text(
            'Visitor Type',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildVisitorTypeButton('GUEST', Icons.person)),
              const SizedBox(width: 10),
              Expanded(child: _buildVisitorTypeButton('DELIVERY', Icons.local_shipping)),
              const SizedBox(width: 10),
              Expanded(child: _buildVisitorTypeButton('CAB', Icons.local_taxi)),
            ],
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _visitorPhoneController,
            label: 'Visitor Phone',
            hint: '+919999999999',
            icon: Icons.phone,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))],
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter visitor phone';
              }
              if (value.length < 10) {
                return 'Please enter valid phone number';
              }
              return null;
            },
          ),
          const SizedBox(height: 22),
          PrimaryButton(
            label: 'Send for Approval',
            icon: Icons.send,
            isLoading: _isLoading,
            onPressed: _isLoading ? null : _handleSubmit,
          ),
        ],
      ),
    );
  }

  Widget _buildVisitorTypeButton(String type, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = _selectedVisitorType == type;
    return AnimatedScale(
      duration: const Duration(milliseconds: 120),
      scale: isSelected ? 1.0 : 0.98,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() => _selectedVisitorType = type);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? colorScheme.primary : colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                size: 26,
              ),
              const SizedBox(height: 6),
              Text(
                type,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessCard(ColorScheme colorScheme) {
    final visitor = _createdVisitor!;
    return SectionCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle, color: Colors.green, size: 32),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Visitor entry created',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Sent for resident approval',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow('Visitor ID', visitor.visitorId),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Status:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              StatusChip(label: visitor.status),
            ],
          ),
          const SizedBox(height: 8),
          _buildInfoRow('Created At', _formatDateTime(visitor.createdAt)),
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'New Entry',
            icon: Icons.refresh,
            onPressed: _clearForm,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            '$label:',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
