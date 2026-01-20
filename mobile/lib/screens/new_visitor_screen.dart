import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/api_client.dart';
import '../models/visitor.dart';

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
  final _apiClient = ApiClient();
  
  String _selectedVisitorType = 'GUEST';
  bool _isLoading = false;
  Visitor? _createdVisitor;

  @override
  void dispose() {
    _flatIdController.dispose();
    _visitorPhoneController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _createdVisitor = null;
    });

    try {
      final response = await _apiClient.createVisitor(
        flatId: _flatIdController.text.trim(),
        visitorType: _selectedVisitorType,
        visitorPhone: _visitorPhoneController.text.trim(),
        guardId: widget.guardId,
      );

      final visitor = Visitor.fromJson(response);

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _createdVisitor = visitor;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
            style: const TextStyle(fontSize: 18),
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Visitor'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Success state
                if (_createdVisitor != null) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green, width: 2),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 60,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Visitor Entry Created!',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildInfoRow('Visitor ID', _createdVisitor!.visitorId),
                        _buildInfoRow('Status', _createdVisitor!.status),
                        _buildInfoRow(
                          'Created At',
                          _formatDateTime(_createdVisitor!.createdAt),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _clearForm,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.green,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'New Entry',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],

                // Form inputs
                if (_createdVisitor == null) ...[
                  TextFormField(
                    controller: _flatIdController,
                    decoration: InputDecoration(
                      labelText: 'Flat ID',
                      hintText: 'Enter flat ID',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.home),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                    ),
                    style: const TextStyle(fontSize: 18),
                    textCapitalization: TextCapitalization.none,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter flat ID';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  // Visitor type buttons
                  const Text(
                    'Visitor Type',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildVisitorTypeButton('GUEST', Icons.person),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildVisitorTypeButton('DELIVERY', Icons.local_shipping),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildVisitorTypeButton('CAB', Icons.local_taxi),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  TextFormField(
                    controller: _visitorPhoneController,
                    decoration: InputDecoration(
                      labelText: 'Visitor Phone',
                      hintText: '+919999999999',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.phone),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                    ),
                    style: const TextStyle(fontSize: 18),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                    ],
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
                  const SizedBox(height: 40),

                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleSubmit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Send for Approval',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVisitorTypeButton(String type, IconData icon) {
    final isSelected = _selectedVisitorType == type;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedVisitorType = type;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey.shade700,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              type,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
