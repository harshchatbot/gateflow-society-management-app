import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/firestore_service.dart';
import '../core/app_logger.dart';
import '../core/society_modules.dart';
import '../widgets/module_disabled_placeholder.dart';
import '../widgets/loading_skeletons.dart';
import '../models/visitor.dart';
import '../widgets/status_chip.dart';
import 'visitor_details_screen.dart';

/// Guard History Screen
/// 
/// Displays all past visitor entries for the guard.
/// Theme: Blue/Primary theme (matching guard login and dashboard)
class GuardHistoryScreen extends StatefulWidget {
  final String guardId;
  final String? guardName;
  final String? societyId;
  final VoidCallback? onBackPressed;

  const GuardHistoryScreen({
    super.key,
    required this.guardId,
    this.guardName,
    this.societyId,
    this.onBackPressed,
  });

  @override
  State<GuardHistoryScreen> createState() => _GuardHistoryScreenState();
}

/// Page size for paginated history. Load more fetches next [kHistoryPageSize] docs.
const int kHistoryPageSize = 30;

class _GuardHistoryScreenState extends State<GuardHistoryScreen> {
  final FirestoreService _firestore = FirestoreService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _visitors = [];
  /// Cursor for "Load more": last document from previous page (null = no more or not loaded).
  DocumentSnapshot? _lastDoc;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  DateTime? _filterDate;

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

  List<Map<String, dynamic>> get _filteredVisitors {
    final query = _searchController.text.trim().toLowerCase();
    final date = _filterDate;

    return _visitors.where((v) {
        if (date != null) {
          DateTime? createdDt;
          dynamic createdAt = v['createdAt'];
          if (createdAt is Timestamp) {
            createdDt = createdAt.toDate();
          } else if (createdAt is DateTime) {
            createdDt = createdAt;
          }
          DateTime? approvedDt;
          final approvedAt = v['approvedAt'] ?? v['approved_at'];
          if (approvedAt is Timestamp) {
            approvedDt = approvedAt.toDate();
          } else if (approvedAt is DateTime) {
            approvedDt = approvedAt;
          }
        bool matchDate(DateTime d) => d.year == date.year && d.month == date.month && d.day == date.day;
        final onDate = (createdDt != null && matchDate(createdDt)) || (approvedDt != null && matchDate(approvedDt));
        if (!onDate) return false;
      }
      if (query.isEmpty) return true;
      final name = (v['visitor_name']?.toString() ?? '').toLowerCase();
      final phone = (v['visitor_phone']?.toString() ?? '').toLowerCase();
      final type = (v['visitor_type']?.toString() ?? '').toLowerCase();
      final flat = (v['flat_no']?.toString() ?? '').toLowerCase();
      final dp = (v['delivery_partner']?.toString() ?? '').toLowerCase();
      final dpo = (v['delivery_partner_other']?.toString() ?? '').toLowerCase();
      final status = (v['status']?.toString() ?? '').toLowerCase();
      return name.contains(query) || phone.contains(query) || type.contains(query) ||
          flat.contains(query) || dp.contains(query) || dpo.contains(query) || status.contains(query);
    }).toList();
  }

  /// One-time fetch: first page of guard history (society-scoped, paginated).
  /// Resets _lastDoc so pull-to-refresh loads from the start.
  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _lastDoc = null;
    });

    try {
      AppLogger.i("Loading guard history (first page)", data: {"guardId": widget.guardId});

      String? societyId = widget.societyId;
      if (societyId == null || societyId.isEmpty) {
        final membership = await _firestore.getCurrentUserMembership();
        societyId = membership?['societyId'] as String?;
      }
      if (societyId == null || societyId.isEmpty) {
        throw Exception("Society ID not found");
      }

      final visitorsRef = _db
          .collection('societies')
          .doc(societyId)
          .collection('visitors');

      // Paginated query: guard_uid + status in [APPROVED, REJECTED], orderBy createdAt desc, limit(kHistoryPageSize).
      // Requires composite index: guard_uid (==), status (in), createdAt (desc).
      Query<Map<String, dynamic>> query = visitorsRef
          .where('guard_uid', isEqualTo: widget.guardId)
          .where('status', whereIn: ['APPROVED', 'REJECTED'])
          .orderBy('createdAt', descending: true)
          .limit(kHistoryPageSize);

      QuerySnapshot<Map<String, dynamic>> querySnapshot = await query
          .get()
          .timeout(const Duration(seconds: 10));

      final List<Map<String, dynamic>> allVisitors = querySnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'visitor_id': doc.id,
          ...data,
        };
      }).toList();

      DocumentSnapshot? lastDoc = querySnapshot.docs.isEmpty
          ? null
          : querySnapshot.docs.last;

      if (mounted) {
        setState(() {
          _visitors = allVisitors;
          _lastDoc = lastDoc;
          _isLoading = false;
          _error = null;
        });
        AppLogger.i("Loaded ${_visitors.length} history visitors (first page)", data: {
          "guardId": widget.guardId,
          "societyId": societyId,
        });
      }
    } catch (e, stackTrace) {
      AppLogger.e("Error loading history", error: e, stackTrace: stackTrace, data: {
        "guardId": widget.guardId,
      });
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = "Connection error. Please check your network and try again.";
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
      String? societyId = widget.societyId;
      if (societyId == null || societyId.isEmpty) {
        final membership = await _firestore.getCurrentUserMembership();
        societyId = membership?['societyId'] as String?;
      }
      if (societyId == null || societyId.isEmpty) {
        setState(() => _isLoadingMore = false);
        return;
      }

      final visitorsRef = _db
          .collection('societies')
          .doc(societyId)
          .collection('visitors');

      Query<Map<String, dynamic>> query = visitorsRef
          .where('guard_uid', isEqualTo: widget.guardId)
          .where('status', whereIn: ['APPROVED', 'REJECTED'])
          .orderBy('createdAt', descending: true)
          .startAfterDocument(_lastDoc!)
          .limit(kHistoryPageSize);

      QuerySnapshot<Map<String, dynamic>> querySnapshot = await query.get();

      final List<Map<String, dynamic>> next = querySnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'visitor_id': doc.id,
          ...data,
        };
      }).toList();

      DocumentSnapshot? newLastDoc = querySnapshot.docs.isEmpty
          ? null
          : querySnapshot.docs.last;

      if (mounted) {
        setState(() {
          _visitors = [..._visitors, ...next];
          _lastDoc = next.length < kHistoryPageSize ? null : newLastDoc;
          _isLoadingMore = false;
        });
        AppLogger.i("Loaded more: +${next.length} (total ${_visitors.length})");
      }
    } catch (e, stackTrace) {
      AppLogger.e("Error loading more history", error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (!SocietyModules.isEnabled(SocietyModuleIds.visitorManagement)) {
      return ModuleDisabledPlaceholder(onBack: widget.onBackPressed);
    }
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) {
          // If we're in a tab navigation (IndexedStack), switch to dashboard
          if (widget.onBackPressed != null) {
            widget.onBackPressed!();
          } else if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.scaffoldBackgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: cs.onSurface),
            onPressed: () {
              // If we're in a tab navigation (IndexedStack), switch to dashboard
              if (widget.onBackPressed != null) {
                widget.onBackPressed!();
              } else if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
        title: Text(
          "Visitor History",
          style: TextStyle(
            color: cs.onSurface,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.refresh_rounded, color: cs.primary, size: 20),
            ),
            onPressed: _isLoading ? null : _loadHistory,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          if (_error != null)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.error.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.error_outline, size: 64, color: cs.error),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: cs.onSurface.withOpacity(0.7),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _loadHistory,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text("Retry"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            )
          else if (_visitors.isEmpty && !_isLoading)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.history_rounded,
                      size: 64,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "No History Yet",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Completed visitor entries will appear here",
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurface.withOpacity(0.7),
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
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
                  child: _filteredVisitors.isEmpty
                      ? (_isLoading && _visitors.isEmpty
                          ? const HistorySkeletonList()
                          : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.filter_list_off_rounded, size: 56, color: cs.onSurface.withOpacity(0.7)),
                              const SizedBox(height: 16),
                              Text(
                                "No entries match your filter",
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.7)),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Try a different search or date",
                                style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.6)),
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
                          color: cs.primary,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                            itemCount: _filteredVisitors.length + (_lastDoc != null ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _filteredVisitors.length) {
                                return _buildLoadMoreRow();
                              }
                              return _buildVisitorCard(_filteredVisitors[index]);
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: theme.scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: "Search by flat, phone, category, delivery…",
              hintStyle: TextStyle(color: cs.onSurface.withOpacity(0.55), fontSize: 14),
              prefixIcon: Icon(Icons.search_rounded, color: cs.primary, size: 22),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear_rounded, size: 20, color: cs.onSurface.withOpacity(0.6)),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              filled: true,
              fillColor: cs.surface,
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
          Row(
            children: [
              Text("Date: ", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.7))),
              GestureDetector(
                onTap: () => setState(() => _filterDate = null),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _filterDate == null ? cs.primary.withOpacity(0.12) : cs.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _filterDate == null ? cs.primary.withOpacity(0.3) : theme.dividerColor,
                    ),
                  ),
                  child: Text(
                    "All dates",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _filterDate == null ? cs.primary : cs.onSurface.withOpacity(0.7),
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
                    color: _filterDate != null ? cs.primary.withOpacity(0.12) : cs.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _filterDate != null ? cs.primary.withOpacity(0.3) : theme.dividerColor,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 16,
                        color: _filterDate != null ? cs.primary : cs.onSurface.withOpacity(0.7),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _filterDate != null
                            ? "${_filterDate!.day}/${_filterDate!.month}/${_filterDate!.year}"
                            : "Pick date",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _filterDate != null ? cs.primary : cs.onSurface.withOpacity(0.7),
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
                  child: Icon(Icons.close_rounded, size: 20, color: cs.onSurface.withOpacity(0.7)),
                ),
              ],
            ],
          ),
          if (_visitors.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              "Showing ${_filteredVisitors.length} of ${_visitors.length} entries",
              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6), fontWeight: FontWeight.w500),
            ),
          ],
        ],
      ),
    );
  }

  /// "Load more" row at bottom of list when another page is available.
  Widget _buildLoadMoreRow() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
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
                  foregroundColor: cs.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
      ),
    );
  }

  Visitor _mapToVisitor(Map<String, dynamic> data) {
    // Parse createdAt
    DateTime createdAt;
    final createdAtValue = data['createdAt'];
    if (createdAtValue is Timestamp) {
      createdAt = createdAtValue.toDate();
    } else if (createdAtValue is DateTime) {
      createdAt = createdAtValue;
    } else {
      createdAt = DateTime.now();
    }

    // Parse approvedAt if exists
    DateTime? approvedAt;
    final approvedAtValue = data['approvedAt'] ?? data['approved_at'];
    if (approvedAtValue != null) {
      if (approvedAtValue is Timestamp) {
        approvedAt = approvedAtValue.toDate();
      } else if (approvedAtValue is DateTime) {
        approvedAt = approvedAtValue;
      }
    }

    return Visitor(
      visitorId: data['visitor_id']?.toString() ?? '',
      societyId: data['society_id']?.toString() ?? widget.societyId ?? '',
      flatId: data['flat_id']?.toString() ?? data['flat_no']?.toString() ?? '',
      flatNo: (data['flat_no'] ?? data['flatNo'] ?? '').toString(),
      visitorType: (data['visitor_type'] ?? data['visitorType'] ?? 'GUEST').toString(),
      visitorPhone: (data['visitor_phone'] ?? data['visitorPhone'] ?? '').toString(),
      status: (data['status'] ?? 'PENDING').toString(),
      createdAt: createdAt,
      approvedAt: approvedAt,
      approvedBy: data['approved_by']?.toString() ?? data['approvedBy']?.toString(),
      guardId: data['guard_uid']?.toString() ?? data['guard_id']?.toString() ?? widget.guardId,
      photoPath: data['photo_path']?.toString(),
      photoUrl: data['photo_url']?.toString() ?? data['photoUrl']?.toString(),
      note: data['note']?.toString(),
      residentPhone: data['resident_phone']?.toString(),
      cab: data['cab'] is Map ? Map<String, dynamic>.from(data['cab'] as Map) : null,
      delivery: data['delivery'] is Map ? Map<String, dynamic>.from(data['delivery'] as Map) : null,
    );
  }

  Widget _buildVisitorCard(Map<String, dynamic> visitorData) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final visitorType = (visitorData['visitor_type'] ?? visitorData['visitorType'] ?? 'GUEST').toString();
    final flatNo = (visitorData['flat_no'] ?? visitorData['flatNo'] ?? 'N/A').toString();
    final phone = (visitorData['visitor_phone'] ?? visitorData['visitorPhone'] ?? 'N/A').toString();
    final residentPhone = (visitorData['resident_phone'] ?? '').toString().trim();
    final status = (visitorData['status'] ?? 'PENDING').toString();
    final createdAt = visitorData['createdAt'];
    final approvedAtRaw = visitorData['approvedAt'] ?? visitorData['approved_at'];
    final photoUrl = visitorData['photo_url'] ?? visitorData['photoUrl'];
    final deliveryPartner = (visitorData['delivery_partner']?.toString() ?? '').trim();
    final deliveryPartnerOther = (visitorData['delivery_partner_other']?.toString() ?? '').trim();

    DateTime? createdDateTime;
    if (createdAt != null) {
      if (createdAt is Timestamp) {
        createdDateTime = createdAt.toDate();
      } else if (createdAt is DateTime) {
        createdDateTime = createdAt;
      }
    }
    DateTime? approvedDateTime;
    if (approvedAtRaw != null) {
      if (approvedAtRaw is Timestamp) {
        approvedDateTime = approvedAtRaw.toDate();
      } else if (approvedAtRaw is DateTime) {
        approvedDateTime = approvedAtRaw;
      }
    }

    final hasDeliveryPartner = visitorType == 'DELIVERY' &&
        (deliveryPartner.isNotEmpty || deliveryPartnerOther.isNotEmpty);
    final deliveryDisplay = hasDeliveryPartner
        ? (deliveryPartner == 'Other'
            ? (deliveryPartnerOther.isNotEmpty
                ? deliveryPartnerOther
                : 'Other')
            : deliveryPartner)
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor.withOpacity(0.6)),
        boxShadow: [
          BoxShadow(
            color: cs.onSurface.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            if (!mounted) return;
            // Convert Map to Visitor object for VisitorDetailsScreen
            final visitorObj = _mapToVisitor(visitorData);
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => VisitorDetailsScreen(
                  visitor: visitorObj,
                  guardId: widget.guardId,
                ),
              ),
            );
            if (mounted) {
              _loadHistory(); // Refresh on return
            }
          },
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row: Type + Delivery Partner chip (if DELIVERY) + Status
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        visitorType,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                        ),
                      ),
                    ),
                    if (deliveryDisplay != null && deliveryDisplay.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: cs.secondary.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: cs.secondary.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.local_shipping_outlined, size: 14, color: cs.secondary),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                deliveryDisplay,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: cs.secondary,
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
                    StatusChip(status: status, compact: true),
                  ],
                ),
                const SizedBox(height: 16),

                // Visitor Info Row
                Row(
                  children: [
                    // Photo/Avatar
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: cs.primary.withOpacity(0.2),
                          width: 2,
                        ),
                      ),
                      child: ClipOval(
                        child: photoUrl != null && photoUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: photoUrl,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  color: theme.dividerColor.withOpacity(0.55),
                                  child: Center(child: Icon(Icons.person_rounded, color: cs.primary, size: 24)),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: cs.primary.withOpacity(0.1),
                                  child: Icon(Icons.person_rounded, color: cs.primary, size: 24),
                                ),
                              )
                            : Container(
                                color: cs.primary.withOpacity(0.1),
                                child: Icon(
                                  Icons.person_rounded,
                                  color: cs.primary,
                                  size: 24,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: cs.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  Icons.home_rounded,
                                  size: 14,
                                  color: cs.primary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                "Flat $flatNo",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: cs.onSurface,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: cs.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  Icons.phone_rounded,
                                  size: 14,
                                  color: cs.primary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                phone,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: cs.onSurface.withOpacity(0.7),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          if (residentPhone.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () async {
                                final cleaned = residentPhone.replaceAll(RegExp(r'[^\d+]'), '');
                                if (cleaned.isEmpty) return;
                                final uri = Uri.parse('tel:$cleaned');
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                }
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: cs.tertiary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Icon(
                                      Icons.call_rounded,
                                      size: 14,
                                      color: cs.tertiary,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    "Resident: $residentPhone",
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: cs.tertiary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.schedule_rounded,
                        size: 14,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Raised: ${createdDateTime != null ? _formatDateTime(createdDateTime) : '—'}",
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurface.withOpacity(0.7),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (approvedDateTime != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              "Approved: ${_formatDateTime(approvedDateTime)}",
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.tertiary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final dateOnly = DateTime(dateTime.year, dateTime.month, dateTime.day);
    final localTime = dateTime.toLocal();

    String dateStr;
    if (dateOnly == today) {
      dateStr = "Today";
    } else if (dateOnly == yesterday) {
      dateStr = "Yesterday";
    } else {
      dateStr = "${localTime.day}/${localTime.month}/${localTime.year}";
    }

    final timeStr = "${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}";
    return "$dateStr at $timeStr";
  }
}
