import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../ui/app_loader.dart';
import '../services/notice_service.dart';
import '../core/app_logger.dart';
import '../core/env.dart';
import '../core/society_modules.dart';
import '../widgets/module_disabled_placeholder.dart';
import 'admin_manage_notices_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


/// Notice Board Screen
/// 
/// Redesigned with modern card style, filter chips, and bell icon
/// Theme: Adapts to role (blue/green/purple)
class NoticeBoardScreen extends StatefulWidget {
  final String societyId;
  final Color themeColor; // Role-specific theme color
  final String? adminId; // Optional: if provided, shows manage button
  final String? adminName; // Optional: for admin context
  final bool useScaffold; // Whether to wrap in Scaffold (true for standalone, false for tab)
  final VoidCallback? onBackPressed; // Callback for back button when in tab navigation

  const NoticeBoardScreen({
    super.key,
    required this.societyId,
    this.themeColor = AppColors.primary, // Default to blue
    this.adminId,
    this.adminName,
    this.useScaffold = true, // Default to true for backward compatibility
    this.onBackPressed,
  });

  @override
  State<NoticeBoardScreen> createState() => _NoticeBoardScreenState();
}

class _NoticeBoardScreenState extends State<NoticeBoardScreen> {
  late final NoticeService _service = NoticeService(
    baseUrl: Env.apiBaseUrl,
  );

  List<dynamic> _notices = [];
  bool _isLoading = false;
  String? _error;
  String? _selectedFilter; // null = All, or specific notice_type

  @override
  void initState() {
    super.initState();
    _loadNotices();
  }

  Future<void> _loadNotices() async {
  if (!mounted) return;
  setState(() {
    _isLoading = true;
    _error = null;
  });

  try {
    AppLogger.i("Loading notices", data: {
      "societyId": widget.societyId,
      "activeOnly": true,
      "source": "api_first",
    });

    // 1) Try API first
    final result = await _service.getNotices(
      societyId: widget.societyId,
      activeOnly: true,
    );

    if (!mounted) return;

    List<dynamic> noticesList = [];

    if (result.isSuccess && result.data != null) {
      noticesList = result.data!;
      AppLogger.i("Notices fetched (API)", data: {
        "count": noticesList.length,
        "societyId": widget.societyId,
      });
    } else {
      AppLogger.w("Notices API failed, trying Firestore fallback", error: result.error, data: {
        "societyId": widget.societyId,
      });
    }

    // 2) If API returned empty -> Firestore fallback for demo
    if (noticesList.isEmpty) {
      AppLogger.w("API returned 0 notices, using Firestore fallback", data: {
        "societyId": widget.societyId,
      });

      // Try to get active notices - handle both 'status' and 'is_active' field names
      Query query = FirebaseFirestore.instance
          .collection('societies')
          .doc(widget.societyId)
          .collection('notices');

      // Try status field first (new format)
      Query activeQuery = query.where('status', isEqualTo: 'active');
      
      QuerySnapshot snap;
      try {
        snap = await activeQuery.orderBy('createdAt', descending: true).get();
      } catch (e) {
        // If orderBy fails (missing index), try without orderBy
        AppLogger.w("OrderBy failed, trying without orderBy", error: e);
        try {
          snap = await activeQuery.get();
        } catch (e2) {
          // If status field doesn't work, try is_active field (old format)
          AppLogger.w("Status field query failed, trying is_active field", error: e2);
          snap = await query.where('is_active', isEqualTo: true).get();
        }
      }

      // Normalize Firestore docs into the exact shape UI expects
      noticesList = snap.docs.map((d) {
        final m = d.data() as Map<String, dynamic>;

        // Check if notice is active (handle both status and is_active fields)
        final status = (m["status"] ?? "").toString().toLowerCase();
        final isActive = m["is_active"] == true || status == "active";
        
        // Skip inactive notices
        if (!isActive) {
          return null;
        }

        // Check expiry date if present
        if (m["expiryAt"] != null) {
          try {
            Timestamp? expiryTimestamp;
            if (m["expiryAt"] is Timestamp) {
              expiryTimestamp = m["expiryAt"] as Timestamp;
            } else if (m["expiry_date"] != null) {
              // Try parsing expiry_date string
              final expiryDate = DateTime.parse(m["expiry_date"].toString());
              expiryTimestamp = Timestamp.fromDate(expiryDate);
            }
            
            if (expiryTimestamp != null) {
              final now = Timestamp.now();
              if (expiryTimestamp.compareTo(now) < 0) {
                // Notice has expired
                return null;
              }
            }
          } catch (e) {
            AppLogger.w("Error checking expiry date", error: e);
            // Continue if expiry check fails
          }
        }

        // Ensure fields used by UI exist
        String createdAtStr = "";
        if (m["createdAt"] is Timestamp) {
          createdAtStr = (m["createdAt"] as Timestamp).toDate().toUtc().toIso8601String();
        } else if (m["created_at"] != null) {
          createdAtStr = m["created_at"].toString();
        } else {
          createdAtStr = DateTime.now().toUtc().toIso8601String();
        }

        return <String, dynamic>{
          "notice_id": (m["notice_id"] ?? m["id"] ?? d.id).toString(),
          "title": (m["title"] ?? "Untitled").toString(),
          "content": (m["content"] ?? m["message"] ?? "").toString(),
          "notice_type": (m["noticeType"] ?? m["notice_type"] ?? "GENERAL").toString().toUpperCase(),
          "created_at": createdAtStr,
          "created_by_name": (m["createdByName"] ?? m["created_by_name"] ?? "Society Admin").toString(),
          "status": (m["status"] ?? "active").toString(),
        };
      }).where((notice) => notice != null).cast<Map<String, dynamic>>().toList();

      // Sort newest first (already sorted by Firestore query, but ensure consistency)
      noticesList.sort((a, b) {
        final da = (a["created_at"] ?? "").toString();
        final db = (b["created_at"] ?? "").toString();
        if (da.isEmpty || db.isEmpty) return 0;
        try {
          final dateA = DateTime.parse(da.replaceAll("Z", "+00:00"));
          final dateB = DateTime.parse(db.replaceAll("Z", "+00:00"));
          return dateB.compareTo(dateA);
        } catch (e) {
          return db.compareTo(da); // Fallback to string comparison
        }
      });

      AppLogger.i("Notices fetched (Firestore fallback)", data: {
        "count": noticesList.length,
        "societyId": widget.societyId,
      });
    }

    // 3) Update UI state
    AppLogger.i("Notices loaded successfully", data: {
      "count": noticesList.length,
      "societyId": widget.societyId,
      "sample_notices": noticesList.take(3).map((n) => {
            "notice_id": n['notice_id']?.toString() ?? 'N/A',
            "title": n['title']?.toString() ?? 'N/A',
            "notice_type": n['notice_type']?.toString() ?? 'N/A',
            "status": n['status']?.toString() ?? n['is_active']?.toString() ?? 'N/A',
          }).toList(),
    });

    if (!mounted) return;
    setState(() {
      _notices = noticesList;
      _isLoading = false;
    });
  } catch (e, stackTrace) {
    AppLogger.e("Error loading notices", error: e, stackTrace: stackTrace, data: {
      "societyId": widget.societyId,
    });
    if (mounted) {
      setState(() {
        _isLoading = false;
        _error = "Connection error. Please try again.";
      });
    }
  }
}


  List<dynamic> get _filteredNotices {
    if (_selectedFilter == null) return _notices;
    return _notices.where((notice) {
      final type = (notice['notice_type'] ?? '').toString().toUpperCase();
      return type == _selectedFilter;
    }).toList();
  }

  bool _isNewNotice(Map<String, dynamic> notice) {
    try {
      final createdAt = notice['created_at']?.toString() ?? '';
      if (createdAt.isEmpty) return false;
      final created = DateTime.parse(createdAt.replaceAll("Z", "+00:00"));
      final now = DateTime.now();
      final daysDiff = now.difference(created).inDays;
      return daysDiff <= 2; // Show "NEW" for notices created in last 2 days
    } catch (e) {
      return false;
    }
  }

  Widget _buildScreen() {
    return Container(
      color: AppColors.surface, // Use AppColors instead of hardcoded
      child: Stack(
        children: [
          Column(
            children: [
              // Header Section with SafeArea
              SafeArea(
                bottom: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  color: Colors.white,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Back button (only when in tab navigation with callback)
                      if (widget.onBackPressed != null && !widget.useScaffold)
                        IconButton(
                          icon: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: widget.themeColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.arrow_back_rounded,
                              color: widget.themeColor,
                              size: 20,
                            ),
                          ),
                          onPressed: () {
                            if (widget.onBackPressed != null) {
                              widget.onBackPressed!();
                            }
                          },
                          tooltip: "Back",
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Notices",
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: AppColors.text,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Society announcements & updates",
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.text2,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Action buttons (Refresh + Manage for admins)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Refresh button (for all users)
                          IconButton(
                            icon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: widget.themeColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.refresh_rounded,
                                color: widget.themeColor,
                                size: 20,
                              ),
                            ),
                            onPressed: _isLoading ? null : _loadNotices,
                            tooltip: "Refresh",
                          ),
                          // Manage button (for admins only)
                          if (widget.adminId != null)
                            IconButton(
                              icon: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: widget.themeColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(Icons.edit_note_rounded, color: widget.themeColor, size: 20),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => AdminManageNoticesScreen(
                                      adminId: widget.adminId!,
                                      adminName: widget.adminName ?? "Admin",
                                      societyId: widget.societyId,
                                    ),
                                  ),
                                ).then((_) {
                                  // Refresh notices when returning from manage screen
                                  _loadNotices();
                                });
                              },
                              tooltip: "Manage Notices",
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Filter Chips
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                color: Colors.white,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip(
                        label: "All",
                        icon: Icons.notifications_rounded,
                        isSelected: _selectedFilter == null,
                        onTap: () => setState(() => _selectedFilter = null),
                      ),
                      const SizedBox(width: 12),
                      _buildFilterChip(
                        label: "Announcement",
                        icon: Icons.campaign_rounded,
                        filterValue: "GENERAL",
                        isSelected: _selectedFilter == "GENERAL",
                        onTap: () => setState(() => _selectedFilter = "GENERAL"),
                      ),
                      const SizedBox(width: 12),
                      _buildFilterChip(
                        label: "Event",
                        icon: Icons.celebration_rounded,
                        filterValue: "SCHEDULE",
                        isSelected: _selectedFilter == "SCHEDULE",
                        onTap: () => setState(() => _selectedFilter = "SCHEDULE"),
                      ),
                      const SizedBox(width: 12),
                      _buildFilterChip(
                        label: "Alert",
                        icon: Icons.warning_rounded,
                        filterValue: "EMERGENCY",
                        isSelected: _selectedFilter == "EMERGENCY",
                        onTap: () => setState(() => _selectedFilter = "EMERGENCY"),
                      ),
                      const SizedBox(width: 12),
                      _buildFilterChip(
                        label: "Maintenance",
                        icon: Icons.build_rounded,
                        filterValue: "MAINTENANCE",
                        isSelected: _selectedFilter == "MAINTENANCE",
                        onTap: () => setState(() => _selectedFilter = "MAINTENANCE"),
                      ),
                      const SizedBox(width: 12),
                      _buildFilterChip(
                        label: "Policy",
                        icon: Icons.policy_rounded,
                        filterValue: "POLICY",
                        isSelected: _selectedFilter == "POLICY",
                        onTap: () => setState(() => _selectedFilter = "POLICY"),
                      ),
                    ],
                  ),
                ),
              ),

              // Notices List
              Expanded(
                child: _buildContent(),
              ),
            ],
          ),
          AppLoader.overlay(show: _isLoading, message: "Loading notices…"),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!SocietyModules.isEnabled(SocietyModuleIds.notices)) {
      return ModuleDisabledPlaceholder(onBack: widget.onBackPressed);
    }
    final content = _buildScreen();

    // If useScaffold is false (used as tab), return content directly (back button is in header)
    // If useScaffold is true (standalone), wrap in Scaffold with AppBar
    if (!widget.useScaffold) {
      // When used as tab, wrap in PopScope for system back button handling
      if (widget.onBackPressed != null) {
        return PopScope(
          canPop: false,
          onPopInvoked: (didPop) {
            if (!didPop) {
              if (widget.onBackPressed != null) {
                widget.onBackPressed!();
              }
            }
          },
          child: content,
        );
      }
      // If no back callback, return content directly (for backward compatibility)
      return content;
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
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.text),
            onPressed: () {
              // If we're in a tab navigation, switch to dashboard
              if (widget.onBackPressed != null) {
                widget.onBackPressed!();
              } else if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
        ),
        body: content,
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required IconData icon,
    String? filterValue,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    Color chipColor;
    Color iconColor;
    
    if (isSelected) {
      chipColor = widget.themeColor;
      iconColor = Colors.white;
    } else {
      // Different colors for different filters
      if (label == "Event") {
        chipColor = const Color(0xFFE8F5E9); // Light green
        iconColor = const Color(0xFF4CAF50); // Green
      } else if (label == "Alert") {
        chipColor = const Color(0xFFFFF3E0); // Light orange
        iconColor = const Color(0xFFFF9800); // Orange
      } else if (label == "Maintenance") {
        chipColor = const Color(0xFFE3F2FD); // Light blue
        iconColor = const Color(0xFF2196F3); // Blue
      } else if (label == "Policy") {
        chipColor = const Color(0xFFF3E5F5); // Light purple
        iconColor = const Color(0xFF9C27B0); // Purple
      } else {
        chipColor = AppColors.surface; // Use AppColors instead of hardcoded
        iconColor = AppColors.text2;
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: chipColor,
          borderRadius: BorderRadius.circular(20),
          border: isSelected ? Border.all(color: widget.themeColor, width: 2) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : iconColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_error != null) {
      return Center(
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
              onPressed: _loadNotices,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text("Retry"),
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.themeColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
    }

    if (_filteredNotices.isEmpty && !_isLoading) {
      return RefreshIndicator(
        onRefresh: _loadNotices,
        color: widget.themeColor,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: widget.themeColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.notifications_none_rounded,
                      size: 64,
                      color: widget.themeColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _selectedFilter == null ? "No notices" : "No ${_selectedFilter!.toLowerCase()} notices",
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "New notices from the society will appear here",
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.text2,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _loadNotices,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text("Refresh"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.themeColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadNotices,
      color: widget.themeColor,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        itemCount: _filteredNotices.length,
        itemBuilder: (context, index) {
          return _buildNoticeCard(_filteredNotices[index]);
        },
      ),
    );
  }

  Widget _buildNoticeCard(Map<String, dynamic> notice) {
    final title = (notice['title'] ?? 'Untitled').toString();
    final content = (notice['content'] ?? '').toString();
    final noticeType = (notice['notice_type'] ?? 'GENERAL').toString().toUpperCase();
    final createdAt = notice['created_at']?.toString() ?? '';
    final isNew = _isNewNotice(notice);

    // Determine icon and colors based on notice type
    IconData icon;
    Color iconBgColor;
    Color categoryColor;
    String categoryLabel;

    switch (noticeType) {
      case "EMERGENCY":
        icon = Icons.warning_rounded;
        iconBgColor = const Color(0xFFFFF3E0); // Light orange
        categoryColor = const Color(0xFFFF9800); // Orange
        categoryLabel = "Alert";
        break;
      case "SCHEDULE":
        icon = Icons.celebration_rounded;
        iconBgColor = const Color(0xFFE8F5E9); // Light green
        categoryColor = const Color(0xFF4CAF50); // Green
        categoryLabel = "Event";
        break;
      case "MAINTENANCE":
        icon = Icons.build_rounded;
        iconBgColor = const Color(0xFFE3F2FD); // Light blue
        categoryColor = const Color(0xFF2196F3); // Blue
        categoryLabel = "Maintenance";
        break;
      case "POLICY":
        icon = Icons.description_rounded;
        iconBgColor = const Color(0xFFF3E5F5); // Light purple
        categoryColor = const Color(0xFF9C27B0); // Purple
        categoryLabel = "Policy";
        break;
      default: // GENERAL
        icon = Icons.campaign_rounded;
        iconBgColor = const Color(0xFFF5F5F5); // Light grey
        categoryColor = AppColors.text2;
        categoryLabel = "Announcement";
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showNoticeDetails(notice),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon Circle
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 28, color: categoryColor),
                ),
                const SizedBox(width: 16),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title Row with NEW tag
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: AppColors.text,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isNew) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.error,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                "NEW",
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Description
                      Text(
                        content,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.text2,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                      // Footer: Category and Date
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: categoryColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              categoryLabel,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: categoryColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Row(
                            children: [
                              Icon(
                                Icons.access_time_rounded,
                                size: 14,
                                color: AppColors.text2,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatDateTime(createdAt),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.text2,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showNoticeDetails(Map<String, dynamic> notice) {
    final title = (notice['title'] ?? 'Untitled').toString();
    final content = (notice['content'] ?? '').toString();
    final noticeType = (notice['notice_type'] ?? 'GENERAL').toString().toUpperCase();
    final createdAt = notice['created_at']?.toString() ?? '';
    final adminName = (notice['created_by_name'] ?? notice['admin_name'] ?? 'Society Admin').toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border.withOpacity(0.3)),
                ),
                child: Text(
                  content,
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.text,
                    fontWeight: FontWeight.w500,
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.person_rounded, size: 16, color: AppColors.text2),
                  const SizedBox(width: 6),
                  Text(
                    adminName,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.text2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.access_time_rounded, size: 16, color: AppColors.text2),
                  const SizedBox(width: 6),
                  Text(
                    _formatDateTime(createdAt),
                    style: TextStyle(
                      fontSize: 14,
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
    );
  }

  String _formatDateTime(String dateTimeStr) {
    if (dateTimeStr.isEmpty) return "Unknown";
    try {
      // Handle both ISO8601 with Z and without
      String normalized = dateTimeStr;
      if (normalized.contains("Z") && !normalized.contains("+") && !normalized.contains("-", 10)) {
        normalized = normalized.replaceAll("Z", "+00:00");
      }
      
      final dt = DateTime.parse(normalized).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final dateOnly = DateTime(dt.year, dt.month, dt.day);

      if (dateOnly == today) {
        // Show time if today
        final hour = dt.hour;
        final minute = dt.minute.toString().padLeft(2, '0');
        final period = hour >= 12 ? 'PM' : 'AM';
        final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
        return "Today, $displayHour:$minute $period";
      } else if (dateOnly == yesterday) {
        return "Yesterday";
      } else {
        // Show date for older notices
        final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return "${dt.day} ${months[dt.month - 1]} ${dt.year}";
      }
    } catch (e) {
      AppLogger.e("Error formatting date time", error: e, data: {"dateTimeStr": dateTimeStr});
      return dateTimeStr.length > 10 ? dateTimeStr.substring(0, 10) : dateTimeStr;
    }
  }
}
