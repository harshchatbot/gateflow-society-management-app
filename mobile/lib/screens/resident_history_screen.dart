import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/resident_service.dart';
import '../core/app_logger.dart';
import '../core/society_modules.dart';
import '../widgets/status_chip.dart';
import '../widgets/module_disabled_placeholder.dart';
import '../widgets/loading_skeletons.dart';
import '../core/env.dart';

/// Resident History Screen
/// 
/// Purpose: Read-only list of past visitor approvals/rejections
/// - Shows completed decisions (APPROVED/REJECTED)
/// - No actions - just viewing history
/// - Similar UI to approvals but read-only
/// 
/// Differences from Guard screens:
/// - No visitor creation or editing
/// - No guard-specific actions
/// - Focus on viewing past decisions only
class ResidentHistoryScreen extends StatefulWidget {
  final String residentId;
  final String societyId;
  final String flatNo;
  final VoidCallback? onBackPressed;

  const ResidentHistoryScreen({
    super.key,
    required this.residentId,
    required this.societyId,
    required this.flatNo,
    this.onBackPressed,
  });

  @override
  State<ResidentHistoryScreen> createState() => _ResidentHistoryScreenState();
}

/// Page size for paginated history. Load more fetches next [kHistoryPageSize] docs.
const int kHistoryPageSize = 30;

class _ResidentHistoryScreenState extends State<ResidentHistoryScreen> {
  late final ResidentService _service = ResidentService(
    baseUrl: Env.apiBaseUrl,
  );

  final TextEditingController _searchController = TextEditingController();

  List<dynamic> _history = [];
  /// Cursor for "Load more": last document from previous page (null = no more or not loaded).
  DocumentSnapshot? _lastDoc;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  DateTime? _filterDate; // null = show all dates

  String? _getCabDisplay(Map<String, dynamic> record) {
    final visitorType = (record['visitor_type']?.toString() ?? '').toUpperCase();
    if (visitorType != 'CAB') return null;

    final cabMap = record['cab'] is Map ? Map<String, dynamic>.from(record['cab'] as Map) : null;
    final provider = (cabMap?['provider'] ?? record['cab_provider'])?.toString().trim();
    final providerOther = (cabMap?['provider_other'] ?? record['cab_provider_other'])?.toString().trim();

    if (provider == null || provider.isEmpty) return null;
    if (provider.toLowerCase() == 'other') {
      return providerOther != null && providerOther.isNotEmpty ? providerOther : 'Other';
    }
    return provider;
  }

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Filter history by search query and selected date
  List<Map<String, dynamic>> get _filteredHistory {
    final query = _searchController.text.trim().toLowerCase();
    final date = _filterDate;

    return _history.where((e) {
      final record = e as Map<String, dynamic>;
      // Date filter: match created_at or approved_at date
      if (date != null) {
        final createdStr = record['created_at']?.toString() ?? '';
        final approvedStr = record['approved_at']?.toString() ?? '';
        DateTime? createdDt;
        DateTime? approvedDt;
        try {
          if (createdStr.isNotEmpty) createdDt = DateTime.parse(createdStr);
          if (approvedStr.isNotEmpty) approvedDt = DateTime.parse(approvedStr);
        } catch (_) {}
        matchDate(DateTime d) =>
            d.year == date.year && d.month == date.month && d.day == date.day;
        final onDate = (createdDt != null && matchDate(createdDt)) ||
            (approvedDt != null && matchDate(approvedDt));
        if (!onDate) return false;
      }
      // Search filter
      if (query.isEmpty) return true;
      final name = (record['visitor_name']?.toString() ?? '').toLowerCase();
      final phone = (record['visitor_phone']?.toString() ?? '').toLowerCase();
      final type = (record['visitor_type']?.toString() ?? '').toLowerCase();
      final dp = (record['delivery_partner']?.toString() ?? '').toLowerCase();
      final dpo = (record['delivery_partner_other']?.toString() ?? '').toLowerCase();
      final cabDisplay = (_getCabDisplay(record) ?? '').toLowerCase();
      final status = (record['status']?.toString() ?? '').toLowerCase();
      return name.contains(query) ||
          phone.contains(query) ||
          type.contains(query) ||
          dp.contains(query) ||
          dpo.contains(query) ||
          cabDisplay.contains(query) ||
          status.contains(query);
    }).cast<Map<String, dynamic>>().toList();
  }

  /// One-time fetch: first page of approval history (paginated via getHistoryPage).
  /// Resets _lastDoc so pull-to-refresh loads from the start.
  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _lastDoc = null;
    });

    try {
      final result = await _service.getHistoryPage(
        societyId: widget.societyId,
        flatNo: widget.flatNo,
        limit: kHistoryPageSize,
        startAfter: null,
      );

      if (!mounted) return;

      if (result.isSuccess && result.data != null) {
        final list = result.data!['visitors'] as List<dynamic>? ?? [];
        final lastDoc = result.data!['lastDoc'];
        setState(() {
          _history = list;
          _lastDoc = lastDoc is DocumentSnapshot ? lastDoc : null;
          _isLoading = false;
        });
        AppLogger.i("Loaded ${_history.length} history records (first page)");
      } else {
        setState(() {
          _isLoading = false;
          _error = result.error ?? "Failed to load history";
        });
        AppLogger.w("Failed to load history: ${result.error}");
      }
    } catch (e) {
      AppLogger.e("Error loading history", error: e);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = "Connection error. Please try again.";
        });
      }
    }
  }

  /// Load next page using cursor from previous page. Keeps existing list and appends.
  void _loadMore() {
    if (_lastDoc == null || _isLoadingMore || _isLoading) return;
    _loadMoreAsync();
  }

  Future<void> _loadMoreAsync() async {
    if (!mounted || _lastDoc == null) return;
    setState(() => _isLoadingMore = true);

    try {
      final result = await _service.getHistoryPage(
        societyId: widget.societyId,
        flatNo: widget.flatNo,
        limit: kHistoryPageSize,
        startAfter: _lastDoc,
      );

      if (!mounted) return;

      if (result.isSuccess && result.data != null) {
        final list = result.data!['visitors'] as List<dynamic>? ?? [];
        final lastDoc = result.data!['lastDoc'];
        setState(() {
          _history = [..._history, ...list];
          _lastDoc = list.length < kHistoryPageSize ? null : (lastDoc is DocumentSnapshot ? lastDoc : null);
          _isLoadingMore = false;
        });
        AppLogger.i("Loaded more: +${list.length} (total ${_history.length})");
      } else {
        setState(() => _isLoadingMore = false);
      }
    } catch (e) {
      AppLogger.e("Error loading more history", error: e);
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!SocietyModules.isEnabled(SocietyModuleIds.visitorManagement)) {
      return ModuleDisabledPlaceholder(onBack: widget.onBackPressed);
    }
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) {
          // If we're in a tab navigation, switch to dashboard
          if (widget.onBackPressed != null) {
            widget.onBackPressed!();
          } else if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          automaticallyImplyLeading: true,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: Theme.of(context).colorScheme.onSurface),
            onPressed: () {
              // If we're in a tab navigation, switch to dashboard
              if (widget.onBackPressed != null) {
                widget.onBackPressed!();
              } else if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
        title: Text(
          "Approval History",
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w900,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: Theme.of(context).colorScheme.primary),
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_error != null)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _loadHistory,
                    child: const Text("Retry"),
                  ),
                ],
              ),
            )
          else if (_history.isEmpty && !_isLoading)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_rounded, size: 64, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                  const SizedBox(height: 16),
                  Text(
                    "No history yet",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Your approval history will appear here",
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildFilterBar(),
                Expanded(
                  child: _filteredHistory.isEmpty
                      ? (_isLoading && _history.isEmpty
                          ? const HistorySkeletonList()
                          : Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.filter_list_off_rounded, size: 56, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                                  const SizedBox(height: 16),
                                  Text(
                                    "No entries match your filter",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "Try a different search or date",
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextButton.icon(
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _filterDate = null);
                                    },
                                    icon: const Icon(Icons.clear_all_rounded, size: 20),
                                    label: const Text("Clear filters"),
                                  ),
                                ],
                              ),
                            ))
                      : RefreshIndicator(
                          onRefresh: _loadHistory,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: _filteredHistory.length + (_lastDoc != null ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _filteredHistory.length) {
                                return _buildLoadMoreRow();
                              }
                              final record = _filteredHistory[index];
                              return _buildHistoryCard(record);
                            },
                          ),
                        ),
                ),
              ],
            ),
        ],
      ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: "Search by name, phone, category, delivery…",
              hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 14),
              prefixIcon: Icon(Icons.search_rounded, color: Theme.of(context).colorScheme.primary, size: 22),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 20),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            style: const TextStyle(fontSize: 15),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          // Date filter
          Row(
            children: [
              Text(
                "Date: ",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _filterDate = null),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _filterDate == null
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
                        : Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _filterDate == null
                          ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                          : Theme.of(context).dividerColor,
                    ),
                  ),
                  child: Text(
                    "All dates",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _filterDate == null ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _filterDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _filterDate = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _filterDate != null
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
                        : Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _filterDate != null
                          ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                          : Theme.of(context).dividerColor,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 16,
                        color: _filterDate != null ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _filterDate != null
                            ? "${_filterDate!.day}/${_filterDate!.month}/${_filterDate!.year}"
                            : "Pick date",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _filterDate != null ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_filterDate != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => setState(() => _filterDate = null),
                  child: Icon(Icons.close_rounded, size: 20, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                ),
              ],
            ],
          ),
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              "Showing ${_filteredHistory.length} of ${_history.length} entries",
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// "Load more" row at bottom when another page is available.
  Widget _buildLoadMoreRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Center(
        child: _isLoadingMore
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
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> record) {
    final visitorId = record['visitor_id']?.toString() ?? '';
    final visitorType = record['visitor_type']?.toString() ?? 'GUEST';
    final visitorPhone = record['visitor_phone']?.toString() ?? '';
    final visitorName = record['visitor_name']?.toString().trim();
    final deliveryPartner = record['delivery_partner']?.toString().trim();
    final deliveryPartnerOther = record['delivery_partner_other']?.toString().trim();
    final status = record['status']?.toString() ?? 'UNKNOWN';
    final createdAt = record['created_at']?.toString() ?? '';
    final approvedAt = record['approved_at']?.toString() ?? '';
    final photoUrl = record['photo_url']?.toString() ?? record['photoUrl']?.toString();
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    final hasDeliveryPartner = visitorType == 'DELIVERY' &&
        ((deliveryPartner != null && deliveryPartner.isNotEmpty) ||
            (deliveryPartnerOther != null && deliveryPartnerOther.isNotEmpty));
    final deliveryDisplay = hasDeliveryPartner
        ? (deliveryPartner == 'Other' ? (deliveryPartnerOther?.isNotEmpty == true ? deliveryPartnerOther! : 'Other') : (deliveryPartner ?? ''))
        : null;
    final cabDisplay = _getCabDisplay(record);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Type + Partner chip (delivery/cab) + Status
          Row(
            children: [
              Text(
                visitorType,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              if (deliveryDisplay != null && deliveryDisplay.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.local_shipping_outlined, size: 14, color: Colors.orange.shade700),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          deliveryDisplay,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.orange.shade800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (cabDisplay != null && cabDisplay.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blueGrey.withOpacity(0.28)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.local_taxi_rounded, size: 14, color: Colors.blueGrey),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          cabDisplay,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.blueGrey,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              StatusChip(label: status),
            ],
          ),
          const SizedBox(height: 12),
          
          // Visitor Details (with optional photo)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasPhoto) ...[
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _openPhotoPreview(photoUrl!),
                      borderRadius: BorderRadius.circular(999),
                      child: ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: photoUrl,
                          fit: BoxFit.cover,
                          width: 50,
                          height: 50,
                          placeholder: (context, url) => Container(
                            color: Colors.grey.shade300,
                            child: Center(child: Icon(Icons.person_rounded, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), size: 24)),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            child: Icon(Icons.person_rounded, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), size: 24),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (visitorName != null && visitorName.isNotEmpty) ...[
                      _buildDetailRow(Icons.person_outline_rounded, "Name", visitorName),
                      const SizedBox(height: 8),
                    ],
                    if (deliveryDisplay != null && deliveryDisplay.isNotEmpty) ...[
                      _buildDetailRow(Icons.local_shipping_outlined, "Delivery", deliveryDisplay),
                      const SizedBox(height: 8),
                    ],
                    if (cabDisplay != null && cabDisplay.isNotEmpty) ...[
                      _buildDetailRow(Icons.local_taxi_rounded, "Cab", cabDisplay),
                      const SizedBox(height: 8),
                    ],
                    _buildDetailRow(Icons.phone_rounded, "Phone", visitorPhone),
                    const SizedBox(height: 8),
                    _buildDetailRow(Icons.access_time_rounded, "Requested", _formatDateTime(createdAt)),
                    if (approvedAt.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildDetailRow(
                        Icons.check_circle_rounded,
                        "Decided",
                        _formatDateTime(approvedAt),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
        const SizedBox(width: 8),
        Text(
          "$label: ",
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  String _formatDateTime(String dateTimeStr) {
    if (dateTimeStr.isEmpty) return "Unknown";
    try {
      final dt = DateTime.parse(dateTimeStr);
      return "${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return dateTimeStr;
    }
  }

  Future<void> _openPhotoPreview(String imageUrl) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(12),
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.contain,
                      placeholder: (context, url) => const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      errorWidget: (context, url, error) => const Center(
                        child: Icon(Icons.broken_image_outlined, color: Colors.white, size: 42),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: IconButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
