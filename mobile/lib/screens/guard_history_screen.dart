import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../ui/app_colors.dart';
import '../ui/app_loader.dart';
import '../services/firestore_service.dart';
import '../core/app_logger.dart';
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

class _GuardHistoryScreenState extends State<GuardHistoryScreen> {
  final FirestoreService _firestore = FirestoreService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _visitors = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      AppLogger.i("Loading guard history", data: {"guardId": widget.guardId});
      
      // Get societyId from membership if not provided
      String? societyId = widget.societyId;
      if (societyId == null || societyId.isEmpty) {
        final membership = await _firestore.getCurrentUserMembership();
        societyId = membership?['societyId'] as String?;
      }

      if (societyId == null || societyId.isEmpty) {
        throw Exception("Society ID not found");
      }

      // Query Firestore for visitors created by this guard
      // Query by guard_uid first, then filter by status in memory to avoid composite index
      final visitorsRef = _db
          .collection('societies')
          .doc(societyId)
          .collection('visitors');

      QuerySnapshot querySnapshot;
      try {
        querySnapshot = await visitorsRef
            .where('guard_uid', isEqualTo: widget.guardId)
            .orderBy('createdAt', descending: true)
            .limit(100)
            .get()
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        AppLogger.w("getHistory timeout or error", error: e.toString());
        // Return empty snapshot on error
        querySnapshot = await visitorsRef
            .where('guard_uid', isEqualTo: widget.guardId)
            .limit(0)
            .get();
      }

      // Filter out PENDING in memory and convert to list
      final allVisitors = querySnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) return null;
        
        final status = (data['status'] ?? 'PENDING').toString().toUpperCase();
        if (status == 'PENDING') return null;
        
        return {
          'visitor_id': doc.id,
          ...data,
        };
      }).where((v) => v != null).cast<Map<String, dynamic>>().toList();

      // Sort by createdAt descending (newest first)
      allVisitors.sort((a, b) {
        final aCreated = a['createdAt'];
        final bCreated = b['createdAt'];
        
        DateTime aTime = DateTime(1970);
        DateTime bTime = DateTime(1970);
        
        if (aCreated is Timestamp) {
          aTime = aCreated.toDate();
        } else if (aCreated is DateTime) {
          aTime = aCreated;
        }
        
        if (bCreated is Timestamp) {
          bTime = bCreated.toDate();
        } else if (bCreated is DateTime) {
          bTime = bCreated;
        }
        
        return bTime.compareTo(aTime);
      });

      if (mounted) {
        setState(() {
          _visitors = allVisitors;
          _isLoading = false;
          _error = null;
        });
        AppLogger.i("Loaded ${_visitors.length} history visitors", data: {
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

  @override
  Widget build(BuildContext context) {
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
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.text),
            onPressed: () {
              // If we're in a tab navigation (IndexedStack), switch to dashboard
              if (widget.onBackPressed != null) {
                widget.onBackPressed!();
              } else if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
        title: const Text(
          "Visitor History",
          style: TextStyle(
            color: AppColors.text,
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
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.refresh_rounded, color: AppColors.primary, size: 20),
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
                      color: AppColors.error.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.error_outline, size: 64, color: AppColors.error),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.text2,
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
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
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
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.history_rounded,
                      size: 64,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "No History Yet",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Completed visitor entries will appear here",
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.text2,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            RefreshIndicator(
              onRefresh: _loadHistory,
              color: AppColors.primary,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                itemCount: _visitors.length,
                itemBuilder: (context, index) {
                  return _buildVisitorCard(_visitors[index]);
                },
              ),
            ),
          AppLoader.overlay(show: _isLoading, message: "Loading history…"),
        ],
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
    );
  }

  Widget _buildVisitorCard(Map<String, dynamic> visitorData) {
    final visitorType = (visitorData['visitor_type'] ?? visitorData['visitorType'] ?? 'GUEST').toString();
    final flatNo = (visitorData['flat_no'] ?? visitorData['flatNo'] ?? 'N/A').toString();
    final phone = (visitorData['visitor_phone'] ?? visitorData['visitorPhone'] ?? 'N/A').toString();
    final residentPhone = (visitorData['resident_phone'] ?? '').toString().trim();
    final status = (visitorData['status'] ?? 'PENDING').toString();
    final createdAt = visitorData['createdAt'];
    final photoUrl = visitorData['photo_url'] ?? visitorData['photoUrl'];
    
    // Parse createdAt to DateTime for display
    DateTime? createdDateTime;
    if (createdAt != null) {
      if (createdAt is Timestamp) {
        createdDateTime = createdAt.toDate();
      } else if (createdAt is DateTime) {
        createdDateTime = createdAt;
      }
    }
    final displayTime = createdDateTime != null 
        ? _formatTime(createdDateTime)
        : 'Recently';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
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
                // Header Row: Type + Status
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        visitorType,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
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
                          color: AppColors.primary.withOpacity(0.2),
                          width: 2,
                        ),
                      ),
                      child: ClipOval(
                        child: photoUrl != null && photoUrl.isNotEmpty
                            ? Image.network(
                                photoUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: AppColors.primarySoft,
                                    child: const Icon(
                                      Icons.person_rounded,
                                      color: AppColors.primary,
                                      size: 24,
                                    ),
                                  );
                                },
                              )
                            : Container(
                                color: AppColors.primarySoft,
                                child: const Icon(
                                  Icons.person_rounded,
                                  color: AppColors.primary,
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
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(
                                  Icons.home_rounded,
                                  size: 14,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                "Flat $flatNo",
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.text,
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
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(
                                  Icons.phone_rounded,
                                  size: 14,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                phone,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.text2,
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
                                      color: AppColors.success.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Icon(
                                      Icons.call_rounded,
                                      size: 14,
                                      color: AppColors.success,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    "Resident: $residentPhone",
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.success,
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
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.access_time_rounded,
                        size: 14,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      displayTime,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.text2,
                        fontWeight: FontWeight.w600,
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

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) return "Just now";
    if (difference.inMinutes < 60) return "${difference.inMinutes}m ago";
    if (difference.inHours < 24) return "${difference.inHours}h ago";
    if (difference.inDays < 7) return "${difference.inDays}d ago";
    
    // Format: DD/MM/YYYY HH:MM
    return "${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";
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
