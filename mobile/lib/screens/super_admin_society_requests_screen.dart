import 'package:flutter/material.dart';

import '../services/society_requests_service.dart';
import '../ui/app_loader.dart';

class SuperAdminSocietyRequestsScreen extends StatefulWidget {
  const SuperAdminSocietyRequestsScreen({super.key});

  @override
  State<SuperAdminSocietyRequestsScreen> createState() =>
      _SuperAdminSocietyRequestsScreenState();
}

class _SuperAdminSocietyRequestsScreenState
    extends State<SuperAdminSocietyRequestsScreen> {
  final SocietyRequestsService _service = SocietyRequestsService();
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _service.getPendingRequests(limit: 100);
    if (!mounted) return;
    if (result.isSuccess) {
      setState(() {
        _items = result.data ?? [];
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = false;
      _error = result.error?.userMessage ?? 'Failed to load requests';
    });
  }

  Future<void> _approve(String requestId) async {
    setState(() => _busy = true);
    final result = await _service.approveRequest(requestId: requestId);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.isSuccess
              ? 'Society request approved'
              : (result.error?.userMessage ?? 'Approve failed'),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (result.isSuccess) await _load();
  }

  Future<void> _reject(String requestId) async {
    final reasonController = TextEditingController();
    final shouldReject = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Reject request?'),
            content: TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'Rejected due to invalid details',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Reject'),
              ),
            ],
          ),
        ) ??
        false;
    if (!shouldReject) return;

    setState(() => _busy = true);
    final result = await _service.rejectRequest(
      requestId: requestId,
      reason: reasonController.text.trim().isEmpty
          ? null
          : reasonController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.isSuccess
              ? 'Society request rejected'
              : (result.error?.userMessage ?? 'Reject failed'),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (result.isSuccess) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Society Requests'),
      ),
      body: Stack(
        children: [
          if (_loading)
            AppLoader.fullscreen(show: true)
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else if (_items.isEmpty)
            const Center(child: Text('No pending society requests'))
          else
            RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final requestId =
                      (item['requestId'] ?? item['id'] ?? '').toString();
                  final proposedName = (item['proposedName'] ?? '').toString();
                  final proposedCode = (item['proposedCode'] ?? '').toString();
                  final city = (item['city'] ?? '').toString();
                  final state = (item['state'] ?? '').toString();
                  final requester = (item['requesterName'] ?? '').toString();
                  final requesterPhone =
                      (item['requesterPhone'] ?? '').toString();

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          proposedName.isNotEmpty ? proposedName : 'Unnamed society',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text('Code: $proposedCode'),
                        if (city.isNotEmpty || state.isNotEmpty)
                          Text('Location: $city${city.isNotEmpty && state.isNotEmpty ? ", " : ""}$state'),
                        Text('Requester: ${requester.isNotEmpty ? requester : "Unknown"}'),
                        if (requesterPhone.isNotEmpty) Text('Phone: $requesterPhone'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: (_busy || requestId.isEmpty)
                                    ? null
                                    : () => _reject(requestId),
                                child: const Text('Reject'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: (_busy || requestId.isEmpty)
                                    ? null
                                    : () => _approve(requestId),
                                child: const Text('Approve'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          if (_busy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withOpacity(0.2),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
