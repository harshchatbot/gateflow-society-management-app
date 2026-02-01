import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:showcaseview/showcaseview.dart';
import '../ui/app_colors.dart';
import '../services/firestore_service.dart';
import '../ui/app_loader.dart';
import '../core/storage.dart';
import '../core/app_logger.dart';
import '../core/tour_storage.dart';
import '../core/society_modules.dart';
import '../models/visitor.dart';
import 'notice_board_screen.dart';
import 'role_select_screen.dart';
import 'visitor_details_screen.dart';
import '../services/notification_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'sos_alerts_screen.dart';
import 'sos_detail_screen.dart';
import 'guard_residents_directory_screen.dart';
import 'guard_violations_list_screen.dart';

class GuardDashboardScreen extends StatefulWidget {
  final String guardId;
  final String guardName;
  final String societyId;
  final VoidCallback? onTapNewEntry;
  final VoidCallback? onTapVisitors;

  const GuardDashboardScreen({
    super.key,
    required this.guardId,
    required this.guardName,
    required this.societyId,
    this.onTapNewEntry,
    this.onTapVisitors,
  });

  @override
  State<GuardDashboardScreen> createState() => _GuardDashboardScreenState();
}

class _GuardDashboardScreenState extends State<GuardDashboardScreen> {
  final FirestoreService _firestore = FirestoreService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final GlobalKey<State<StatefulWidget>> _keyNewEntry = GlobalKey<State<StatefulWidget>>();
  final GlobalKey<State<StatefulWidget>> _keyVisitors = GlobalKey<State<StatefulWidget>>();
  final GlobalKey<State<StatefulWidget>> _keySosAlerts = GlobalKey<State<StatefulWidget>>();

  String _dynamicName = "";
  String? _photoUrl;
  int todayCount = 0;
  int pendingCount = 0;
  int approvedCount = 0;
  bool _isLoading = false;
  List<Visitor> _recentVisitors = [];
  int _sosBadgeCount = 0;

  @override
  void initState() {
    super.initState();
    _dynamicName = widget.guardName;
    _syncDashboard();
    _setupNotificationListener();
    _maybeAutoRunTour();
  }

  void _maybeAutoRunTour() async {
    final seen = await TourStorage.hasSeenTourGuard();
    if (mounted && !seen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) startTour();
        });
      });
    }
  }

  /// Context from inside ShowCaseWidget's builder (needed to find ShowCaseWidget).
  BuildContext? _showCaseContext;

  void startTour() {
    if (_showCaseContext == null || !mounted) return;
    try {
      final keys = <GlobalKey<State<StatefulWidget>>>[];
      if (SocietyModules.isEnabled(SocietyModuleIds.visitorManagement)) {
        keys.addAll([_keyNewEntry, _keyVisitors]);
      }
      if (SocietyModules.isEnabled(SocietyModuleIds.sos)) keys.add(_keySosAlerts);
      if (keys.isEmpty) return;
      ShowCaseWidget.of(_showCaseContext!).startShowCase(keys);
    } catch (_) {
      if (mounted) TourStorage.setHasSeenTourGuard();
    }
  }

  void _setupNotificationListener() {
    final notificationService = NotificationService();
    notificationService.setOnNotificationReceived((data) {
      final type = (data['type'] ?? '').toString();
      if (type == 'sos' && SocietyModules.isEnabled(SocietyModuleIds.sos)) {
        // Increment SOS badge when notification received
        if (mounted) {
          setState(() {
            _sosBadgeCount = 1;
          });
        }
      }
    });
    notificationService.setOnNotificationTap((data) {
      final type = (data['type'] ?? '').toString();
      if (type == 'sos' && SocietyModules.isEnabled(SocietyModuleIds.sos)) {
        final societyId = (data['society_id'] ?? widget.societyId).toString();
        final flatNo = (data['flat_no'] ?? '').toString();
        final residentName = (data['resident_name'] ?? 'Resident').toString();
        final phone = (data['resident_phone'] ?? '').toString();
        final sosId = (data['sos_id'] ?? '').toString();

        if (!mounted || sosId.isEmpty) return;
        // Clear SOS badge when user opens the SOS details
        setState(() {
          _sosBadgeCount = 0;
        });
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SosDetailScreen(
              societyId: societyId,
              sosId: sosId,
              flatNo: flatNo,
              residentName: residentName,
              residentPhone: phone.isNotEmpty ? phone : null,
            ),
          ),
        );
      }
    });
  }

  Future<void> _syncDashboard() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // 1. Get guard profile from Firestore
      final membership = await _firestore.getCurrentUserMembership();
      if (membership != null && membership['name'] != null) {
        _dynamicName = membership['name'] as String;
        _photoUrl = membership['photoUrl'] as String?;

        // Sync to storage so Profile page updates too
        Storage.saveGuardSession(
          guardId: widget.guardId,
          guardName: _dynamicName,
          societyId: widget.societyId,
        );
      }

      // 2. Get today's visitors from Firestore
      // Query by guard_uid first, then filter by date in memory to avoid composite index requirement
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final visitorsRef = _db
          .collection('societies')
          .doc(widget.societyId)
          .collection('visitors');

      QuerySnapshot querySnapshot;
      try {
        querySnapshot = await visitorsRef
            .where('guard_uid', isEqualTo: widget.guardId)
            .limit(100) // Limit to recent visitors
            .get()
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        AppLogger.w("getTodayVisitors timeout or error", error: e.toString());
        // Return empty snapshot on timeout/error
        querySnapshot = await visitorsRef
            .where('guard_uid', isEqualTo: widget.guardId)
            .limit(0)
            .get();
      }

      // Filter by today's date in memory
      final todayVisitors = querySnapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) return false;
        
        final createdAt = data['createdAt'];
        if (createdAt == null) return false;
        
        DateTime createdDate;
        if (createdAt is Timestamp) {
          createdDate = createdAt.toDate();
        } else if (createdAt is DateTime) {
          createdDate = createdAt;
        } else {
          return false;
        }
        
        return createdDate.isAfter(startOfDay.subtract(const Duration(seconds: 1))) &&
               createdDate.isBefore(endOfDay);
      }).map((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        return {
          'status': data?['status'] ?? 'PENDING',
        };
      }).toList();

      // 3. Get recent visitors (last 5, ordered by createdAt descending)
      List<Visitor> recentVisitors = [];
      try {
        final recentQuerySnapshot = await visitorsRef
            .where('guard_uid', isEqualTo: widget.guardId)
            .orderBy('createdAt', descending: true)
            .limit(5)
            .get()
            .timeout(const Duration(seconds: 10));

        recentVisitors = recentQuerySnapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>?;
          if (data == null) return null;
          return _mapToVisitor(data, doc.id);
        }).whereType<Visitor>().toList();
      } catch (e) {
        AppLogger.w("getRecentVisitors error", error: e.toString());
        // Fallback: try without orderBy if composite index is missing
        try {
          final recentQuerySnapshot = await visitorsRef
              .where('guard_uid', isEqualTo: widget.guardId)
              .limit(20)
              .get()
              .timeout(const Duration(seconds: 10));

          final allVisitors = recentQuerySnapshot.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>?;
            if (data == null) return null;
            return _mapToVisitor(data, doc.id);
          }).whereType<Visitor>().toList();

          // Sort by createdAt descending in memory
          allVisitors.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          recentVisitors = allVisitors.take(5).toList();
        } catch (e2) {
          AppLogger.w("getRecentVisitors fallback error", error: e2.toString());
        }
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          todayCount = todayVisitors.length;
          pendingCount = todayVisitors
              .where((v) => (v['status'] as String).toUpperCase() == 'PENDING')
              .length;
          approvedCount = todayVisitors
              .where((v) => (v['status'] as String).toUpperCase() == 'APPROVED')
              .length;
          _recentVisitors = recentVisitors;
        });
      }

      AppLogger.i("Guard dashboard synced", data: {
        "todayCount": todayCount,
        "pendingCount": pendingCount,
        "approvedCount": approvedCount,
      });
    } catch (e, stackTrace) {
      AppLogger.e("Dashboard Sync Error", error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Visitor _mapToVisitor(Map<String, dynamic> data, String docId) {
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
      visitorId: docId,
      societyId: data['society_id']?.toString() ?? widget.societyId,
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

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) {
      return "Just now";
    } else if (diff.inMinutes < 60) {
      return "${diff.inMinutes}m ago";
    } else if (diff.inHours < 24) {
      return "${diff.inHours}h ago";
    } else if (diff.inDays < 7) {
      return "${diff.inDays}d ago";
    } else {
      final localTime = dateTime.toLocal();
      return "${localTime.day}/${localTime.month}/${localTime.year}";
    }
  }

  IconData _getVisitorTypeIcon(String type) {
    switch (type.toUpperCase()) {
      case "DELIVERY":
        return Icons.inventory_2_outlined;
      case "CAB":
        return Icons.directions_car_outlined;
      case "GUEST":
        return Icons.person_outline;
      default:
        return Icons.person_add_outlined;
    }
  }

  Color _getStatusColor(String status) {
    final s = status.toUpperCase();
    if (s.contains("APPROV")) return AppColors.success;
    if (s.contains("REJECT")) return AppColors.error;
    if (s.contains("LEAVE")) return AppColors.warning;
    if (s.contains("PENDING")) return AppColors.warning;
    return AppColors.textMuted;
  }

  Future<void> _onWillPop() async {
    // Show confirmation dialog when back is pressed on dashboard
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit App?'),
        content: const Text('Do you want to exit the app?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    if (shouldExit == true && context.mounted) {
      // Navigate to role select instead of just popping
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RoleSelectScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ShowCaseWidget(
      enableAutoScroll: true,
      scrollDuration: const Duration(milliseconds: 400),
      onFinish: () {
        TourStorage.setHasSeenTourGuard();
      },
      builder: (context) {
        _showCaseContext = context;
        return PopScope(
        canPop: false,
        onPopInvoked: (didPop) async {
          if (!didPop) {
            await _onWillPop();
          }
        },
        child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Stack(
          children: [
          // Background Gradient Header
          Positioned(
            left: 0, right: 0, top: 0, height: 260,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, Color(0xFF1E40AF)],
                ),
              ),
            ),
          ),

          RefreshIndicator(
            onRefresh: _syncDashboard,
            color: AppColors.primary,
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 20),
                  _buildPremiumSocietyCard(),
                  const SizedBox(height: 20),

                  if (SocietyModules.isEnabled(SocietyModuleIds.visitorManagement)) ...[
                    const Text(
                      "Today at a glance",
                      style: TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildStatsRow(),
                    const SizedBox(height: 24),
                  ],
                  const Text(
                    "Your actions",
                    style: TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildActionGrid(),

                  if (SocietyModules.isEnabled(SocietyModuleIds.visitorManagement)) ...[
                    const SizedBox(height: 25),
                    _buildRecentActivitySection(),
                  ],
                ],
              ),
            ),
          ),
          
          if (_isLoading) AppLoader.overlay(show: true, message: "Syncing Data..."),
        ],
      ),
      ),
    );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        // Small profile avatar
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withOpacity(0.8),
              width: 2,
            ),
          ),
          child: CircleAvatar(
            backgroundColor: Colors.white24,
            backgroundImage: (_photoUrl != null && _photoUrl!.isNotEmpty)
                ? CachedNetworkImageProvider(_photoUrl!)
                : null,
            child: (_photoUrl == null || _photoUrl!.isEmpty)
                ? const Icon(
                    Icons.person_rounded,
                    color: Colors.white,
                  )
                : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Welcome back,",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              Text(
                _dynamicName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        // Notification Bell Icon
        Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_rounded, color: Colors.white),
              onPressed: () {
                // If SOS badge is present, navigate to SOS Alerts; otherwise visitors
                if (_sosBadgeCount > 0 && SocietyModules.isEnabled(SocietyModuleIds.sos)) {
                  setState(() => _sosBadgeCount = 0);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SosAlertsScreen(
                        societyId: widget.societyId,
                        role: 'guard',
                      ),
                    ),
                  );
                } else if (widget.onTapVisitors != null) {
                  widget.onTapVisitors!();
                }
              },
            ),
            if (pendingCount + _sosBadgeCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    pendingCount > 9 ? "9+" : pendingCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.tune_rounded, color: Colors.white),
          onPressed: () => _showSettingsSheet(context),
        ),
      ],
    );
  }

  Widget _buildPremiumSocietyCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.business_rounded, color: Colors.white),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.societyId, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                const Text("Society Management Active", style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
        ],
      ),
    );
  }

  /// Stats row wrapped in a soft card module
  Widget _buildStatsRow() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              label: "Today",
              value: todayCount.toString(),
              icon: Icons.today,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              label: "Pending",
              value: pendingCount.toString(),
              icon: Icons.hourglass_empty,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              label: "Approved",
              value: approvedCount.toString(),
              icon: Icons.verified_user_outlined,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionGrid() {
    final children = <Widget>[];
    if (SocietyModules.isEnabled(SocietyModuleIds.visitorManagement)) {
      children.addAll([
        Showcase(
          key: _keyNewEntry,
          title: "New Visitor Entry",
          description: "Register a new visitor. Resident gets a request to approve.",
          child: _QuickAction(label: "New Entry", icon: Icons.person_add_rounded, tint: AppColors.primary, onTap: widget.onTapNewEntry),
        ),
        Showcase(
          key: _keyVisitors,
          title: "Visitor List / History",
          description: "View today's visitors and full history.",
          child: _QuickAction(label: "Visitors", icon: Icons.groups_rounded, tint: AppColors.success, onTap: widget.onTapVisitors),
        ),
      ]);
    }
    if (SocietyModules.isEnabled(SocietyModuleIds.notices)) {
      children.add(
        _QuickAction(
          label: "Notices",
          icon: Icons.notifications_rounded,
          tint: AppColors.warning,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => NoticeBoardScreen(
                  societyId: widget.societyId,
                  themeColor: AppColors.primary,
                ),
              ),
            );
          },
        ),
      );
    }
    if (SocietyModules.isEnabled(SocietyModuleIds.sos)) {
      children.add(
        Showcase(
          key: _keySosAlerts,
          title: "SOS Alerts",
          description: "View and respond to emergency SOS from residents.",
          child: _QuickAction(
            label: "SOS Alerts",
            icon: Icons.sos_rounded,
            tint: AppColors.error,
            onTap: () {
              if (mounted) {
                setState(() {
                  _sosBadgeCount = 0;
                });
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SosAlertsScreen(
                    societyId: widget.societyId,
                    role: 'guard',
                  ),
                ),
              );
            },
          ),
        ),
        );
    }
    children.add(
      _QuickAction(
        label: "Residents",
        icon: Icons.people_rounded,
        tint: AppColors.admin,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GuardResidentsDirectoryScreen(
                societyId: widget.societyId,
              ),
            ),
          );
          },
      ),
    );
    if (SocietyModules.isEnabled(SocietyModuleIds.violations)) {
      children.add(
        _QuickAction(
          label: "Violations",
          icon: Icons.directions_car_rounded,
          tint: AppColors.warning,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GuardViolationsListScreen(
                  guardId: widget.guardId,
                  societyId: widget.societyId,
                ),
              ),
            );
          },
        ),
      );
    }
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: children,
    );
  }

  Widget _buildRecentActivitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Recent Activity", style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w900, fontSize: 16)),
            TextButton(onPressed: widget.onTapVisitors, child: const Text("View All")),
          ],
        ),
        const SizedBox(height: 10),
        if (_recentVisitors.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Center(
              child: Text(
                "No recent visitors",
                style: TextStyle(
                  color: AppColors.text2,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
        else
          ..._recentVisitors.map((visitor) {
            final displayFlat = visitor.flatNo.isNotEmpty ? visitor.flatNo : visitor.flatId;
            final statusColor = _getStatusColor(visitor.status);
            final subtitle = "${visitor.visitorPhone.isNotEmpty ? visitor.visitorPhone : 'No phone'} • ${_formatTime(visitor.createdAt)}";
            final hasResidentPhone = visitor.residentPhone != null && visitor.residentPhone!.trim().isNotEmpty;
            return InkWell(
              onTap: () {
                if (!mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VisitorDetailsScreen(
                      visitor: visitor,
                      guardId: widget.guardId,
                    ),
                  ),
                ).then((_) {
                  // Refresh dashboard after returning from details
                  if (mounted) {
                    _syncDashboard();
                  }
                });
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getVisitorTypeIcon(visitor.visitorType),
                      color: AppColors.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "${visitor.visitorType} • Flat $displayFlat",
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.text2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (hasResidentPhone) ...[
                            const SizedBox(height: 4),
                            GestureDetector(
                              onTap: () async {
                                final phone = visitor.residentPhone!;
                                final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
                                if (cleaned.isEmpty) return;
                                final uri = Uri.parse('tel:$cleaned');
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                }
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.call_rounded, size: 14, color: AppColors.success),
                                  const SizedBox(width: 4),
                                  Text(
                                    "Resident: ${visitor.residentPhone}",
                                    style: const TextStyle(
                                      fontSize: 11,
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: statusColor.withOpacity(0.3)),
                      ),
                      child: Text(
                        visitor.status,
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
          }).toList(),
      ],
    );
  }

  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Gate Settings", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.notifications_active, color: AppColors.primary),
              title: const Text("Alert Sounds"),
              trailing: Switch.adaptive(value: true, onChanged: (v) {}),
            ),
          ],
        ),
      ),
    );
  }
}

// --- HELPER COMPONENTS ---

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w900, fontSize: 18)),
          Text(label, style: const TextStyle(color: AppColors.text2, fontWeight: FontWeight.bold, fontSize: 11)),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color tint;
  final VoidCallback? onTap;
  const _QuickAction({required this.label, required this.icon, required this.tint, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: tint, size: 28),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final IconData icon;
  const _ActivityTile({required this.title, required this.subtitle, required this.badge, required this.badgeColor, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.text2)),
            ]),
          ),
          Text(badge, style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }
}