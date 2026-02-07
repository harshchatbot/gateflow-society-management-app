import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../ui/app_colors.dart';
import '../ui/app_loader.dart';
import '../services/firestore_service.dart';
import '../core/app_logger.dart';
import '../core/society_modules.dart';
import '../widgets/module_disabled_placeholder.dart';
import 'sos_detail_screen.dart';

class SosAlertsScreen extends StatefulWidget {
  final String societyId;
  final String role; // 'admin' or 'guard'

  const SosAlertsScreen({
    super.key,
    required this.societyId,
    required this.role,
  });

  @override
  State<SosAlertsScreen> createState() => _SosAlertsScreenState();
}

/// Page size for paginated SOS alerts. Load more fetches next [kSosPageSize] docs.
const int kSosPageSize = 30;

class _SosAlertsScreenState extends State<SosAlertsScreen> {
  final FirestoreService _firestore = FirestoreService();
  final TextEditingController _searchController = TextEditingController();
  bool _loading = true;
  bool _loadingMore = false;
  List<Map<String, dynamic>> _alerts = [];
  /// Cursor for "Load more" (null = no more or not loaded).
  DocumentSnapshot? _lastDoc;

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Filter alerts by search query (flat, name, phone, status, type, note, acknowledged/resolved by).
  List<Map<String, dynamic>> get _filteredAlerts {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _alerts;
    return _alerts.where((sos) {
      final flatNo = (sos['flatNo'] ?? sos['flat_no'] ?? '').toString().toLowerCase();
      final residentName = (sos['residentName'] ?? sos['resident_name'] ?? 'Resident').toString().toLowerCase();
      final phone = (sos['phone'] ?? '').toString().toLowerCase();
      final status = (sos['status'] ?? 'OPEN').toString().toLowerCase();
      final type = (sos['type'] ?? '').toString().toLowerCase();
      final note = (sos['note'] ?? '').toString().toLowerCase();
      final sosId = (sos['sosId'] ?? '').toString().toLowerCase();
      final ackBy = (sos['acknowledgedByName'] ?? sos['acknowledged_by_name'] ?? '').toString().toLowerCase();
      final resolvedBy = (sos['resolvedByName'] ?? sos['resolved_by_name'] ?? '').toString().toLowerCase();
      return flatNo.contains(query) ||
          residentName.contains(query) ||
          phone.contains(query) ||
          status.contains(query) ||
          type.contains(query) ||
          note.contains(query) ||
          sosId.contains(query) ||
          ackBy.contains(query) ||
          resolvedBy.contains(query);
    }).toList();
  }

  /// One-time fetch: first page. Resets _lastDoc on refresh.
  Future<void> _load() async {
    try {
      if (mounted) setState(() => _loading = true);
      final result = await _firestore.getSosRequestsPage(
        societyId: widget.societyId,
        limit: kSosPageSize,
        startAfter: null,
      );
      if (mounted) {
        setState(() {
          _alerts = result['list'] as List<Map<String, dynamic>>? ?? [];
          _lastDoc = result['lastDoc'] as DocumentSnapshot?;
          _loading = false;
        });
      }
    } catch (e, st) {
      AppLogger.e("Error loading SOS alerts list", error: e, stackTrace: st);
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _loadMore() {
    if (_lastDoc == null || _loadingMore || _loading) return;
    _loadMoreAsync();
  }

  Future<void> _loadMoreAsync() async {
    if (!mounted || _lastDoc == null) return;
    setState(() => _loadingMore = true);
    try {
      final result = await _firestore.getSosRequestsPage(
        societyId: widget.societyId,
        limit: kSosPageSize,
        startAfter: _lastDoc,
      );
      if (!mounted) return;
      final list = result['list'] as List<Map<String, dynamic>>? ?? [];
      final lastDoc = result['lastDoc'] as DocumentSnapshot?;
      setState(() {
        _alerts = [..._alerts, ...list];
        _lastDoc = list.length < kSosPageSize ? null : lastDoc;
        _loadingMore = false;
      });
    } catch (e, st) {
      AppLogger.e("Error loading more SOS alerts", error: e, stackTrace: st);
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!SocietyModules.isEnabled(SocietyModuleIds.sos)) {
      return const ModuleDisabledPlaceholder();
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('SOS Alerts'),
        backgroundColor: AppColors.error,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? AppLoader.fullscreen(show: true)
            : _alerts.isEmpty
                ? const Center(
                    child: Text(
                      'No SOS alerts yet.',
                      style: TextStyle(color: AppColors.text2),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildFilterBar(),
                      Expanded(
                        child: _filteredAlerts.isEmpty
                            ? _buildNoFilterResults()
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                                itemCount: _filteredAlerts.length + (_lastDoc != null ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == _filteredAlerts.length) {
                                    return _buildLoadMoreRow();
                                  }
                                  final sos = _filteredAlerts[index];
                      final sosId = (sos['sosId'] ?? '').toString();
                      final flatNo = (sos['flatNo'] ?? '').toString();
                      final residentName =
                          (sos['residentName'] ?? 'Resident').toString();
                      final phone = (sos['phone'] ?? '').toString();
                      final status = (sos['status'] ?? 'OPEN').toString();
                      final createdAt = sos['createdAt'];

                      final acknowledgedByName =
                          (sos['acknowledgedByName'] ?? sos['acknowledged_by_name'])
                              ?.toString();
                      final resolvedByName =
                          (sos['resolvedByName'] ?? sos['resolved_by_name'])
                              ?.toString();

                      DateTime? created;
                      if (createdAt is Timestamp) {
                        created = createdAt.toDate();
                      }

                      final statusUpper = status.toUpperCase();
                      Color statusColor;
                      if (statusUpper == 'OPEN') {
                        statusColor = AppColors.error;
                      } else if (statusUpper == 'ACKNOWLEDGED') {
                        statusColor = AppColors.warning;
                      } else {
                        statusColor = AppColors.success;
                      }

                      return InkWell(
                        onTap: () {
                          if (sosId.isEmpty) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SosDetailScreen(
                                societyId: widget.societyId,
                                sosId: sosId,
                                flatNo: flatNo,
                                residentName: residentName,
                                residentPhone:
                                    phone.isNotEmpty ? phone : null,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.sos_rounded,
                                  color: AppColors.error),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Flat $flatNo',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14,
                                        color: AppColors.text,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      residentName,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.text2,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (phone.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        phone,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.text2,
                                        ),
                                      ),
                                    ],
                                    if (created != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        created.toLocal().toString(),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.text2,
                                        ),
                                      ),
                                      ],
                                    if (acknowledgedByName != null &&
                                        acknowledgedByName.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Ack: $acknowledgedByName',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.text2,
                                        ),
                                      ),
                                    ],
                                    if (resolvedByName != null &&
                                        resolvedByName.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Resolved: $resolvedByName',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.text2,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: statusColor.withOpacity(0.3)),
                                ),
                                child: Text(
                                  statusUpper,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                                ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: "Search by flat, name, phone, status, type…",
              hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.error, size: 22),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 20),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              filled: true,
              fillColor: AppColors.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            style: const TextStyle(fontSize: 15),
            onChanged: (_) => setState(() {}),
          ),
          if (_alerts.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _searchController.text.trim().isEmpty
                  ? "${_alerts.length} alert${_alerts.length != 1 ? 's' : ''}"
                  : "Showing ${_filteredAlerts.length} of ${_alerts.length}",
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w500),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNoFilterResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.filter_list_off_rounded, size: 56, color: AppColors.text2),
          const SizedBox(height: 16),
          const Text(
            "No alerts match your search",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.text2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            "Try a different search term",
            style: TextStyle(fontSize: 14, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () => _searchController.clear(),
            icon: const Icon(Icons.clear_all_rounded, size: 20),
            label: const Text("Clear search"),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadMoreRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Center(
        child: _loadingMore
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : TextButton.icon(
                onPressed: _loadMore,
                icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                label: const Text("Load more"),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.error,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
      ),
    );
  }
}

