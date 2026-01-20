import 'package:flutter/material.dart';
import 'package:gateflow/models/visitor.dart';
import 'package:gateflow/services/visitor_service.dart';

class VisitorDetailsScreen extends StatefulWidget {
  final Visitor visitor;
  final String guardId;
  const VisitorDetailsScreen({super.key, required this.visitor, required this.guardId});

  @override
  State<VisitorDetailsScreen> createState() => _VisitorDetailsScreenState();
}

class _VisitorDetailsScreenState extends State<VisitorDetailsScreen> {
  final _service = VisitorService();
  bool _loading = false;
  String? _error;
  late Visitor _visitor;

  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _visitor = widget.visitor;
    _noteController.text = _visitor.note ?? "";
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _setStatus(String status) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final res = await _service.updateVisitorStatus(
      visitorId: _visitor.visitorId,
      status: status,
      approvedBy: "GUARD:${widget.guardId}", // later replace with resident
      note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
    );

    setState(() {
      _loading = false;
      if (res.isSuccess) {
        _visitor = res.data!;
      } else {
        _error = res.error?.userMessage ?? "Failed to update status";
      }
    });
  }

  Widget _photo() {
    if (_visitor.photoUrl != null && _visitor.photoUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          _visitor.photoUrl!,
          width: double.infinity,
          height: 220,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            height: 220,
            color: Colors.grey.withOpacity(0.15),
            child: const Center(child: Icon(Icons.image_not_supported)),
          ),
        ),
      );
    }
    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(child: Icon(Icons.person, size: 52)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Visitor Details")),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),

              _photo(),
              const SizedBox(height: 14),

              Text("${_visitor.visitorType} • Flat ${_visitor.flatId}",
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(_visitor.visitorPhone.isEmpty ? "No phone" : _visitor.visitorPhone),
              const SizedBox(height: 6),
              Text("Status: ${_visitor.status}", style: const TextStyle(fontWeight: FontWeight.w600)),

              const SizedBox(height: 16),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: "Note (optional)",
                  border: OutlineInputBorder(),
                ),
                minLines: 1,
                maxLines: 3,
              ),

              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _setStatus("APPROVED"),
                      child: const Text("Approve"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _setStatus("REJECTED"),
                      child: const Text("Reject"),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _setStatus("LEAVE_AT_GATE"),
                  child: const Text("Leave at Gate"),
                ),
              ),
            ],
          ),

          if (_loading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.05),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
