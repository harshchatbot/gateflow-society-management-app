import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:showcaseview/showcaseview.dart';
import '../ui/app_colors.dart';
import '../ui/app_loader.dart';
import '../services/admin_service.dart';
import '../services/complaint_service.dart';
import '../services/notice_service.dart';
import '../services/notification_service.dart';
import '../services/firestore_service.dart';
import '../services/resident_signup_service.dart';
import '../core/app_logger.dart';
import '../core/env.dart';
import '../core/tour_storage.dart';
import '../core/society_modules.dart';
import 'notice_board_screen.dart';
import 'sos_detail_screen.dart';
import 'sos_alerts_screen.dart';
import 'admin_manage_notices_screen.dart';
import 'admin_manage_admins_screen.dart';
import 'admin_manage_violations_screen.dart';
import 'role_select_screen.dart';
import '../widgets/admin_notification_drawer.dart';
import '../widgets/dashboard_hero.dart';
import '../widgets/dashboard_stat_card.dart';
import '../widgets/dashboard_quick_action.dart';
import '../widgets/visitors_chart.dart';

/// Admin Dashboard Screen
/// 
/// Overview screen for admins showing key metrics and quick actions
/// Theme: Purple/Admin theme
class AdminDashboardScreen extends StatefulWidget {
  final String adminId;
  final String adminName;
  final String societyId;
  final String? systemRole; // admin or super_admin
  /// Callback to navigate to tabs. Second arg optional: 1 = open Residents on Pending signups tab.
  final void Function(int index, [int? residentsSubTab])? onTabNavigate;

  const AdminDashboardScreen({
    super.key,
    required this.adminId,
    required this.adminName,
    required this.societyId,
    this.systemRole,
    this.onTabNavigate,
  });

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late final AdminService _service = AdminService(
    baseUrl: Env.apiBaseUrl,
  );

  final GlobalKey<State<StatefulWidget>> _keyResidents = GlobalKey<State<StatefulWidget>>();
  final GlobalKey<State<StatefulWidget>> _keyGuards = GlobalKey<State<StatefulWidget>>();
  final GlobalKey<State<StatefulWidget>> _keyComplaints = GlobalKey<State<StatefulWidget>>();
  final GlobalKey<State<StatefulWidget>> _keyNotices = GlobalKey<State<StatefulWidget>>();
  final GlobalKey<State<StatefulWidget>> _keySos = GlobalKey<State<StatefulWidget>>();

  Map<String, dynamic>? _stats;
  bool _isLoading = false;
  String? _error;
  /// Society-wide visitor counts last 7 days (for chart). null until loaded.
  List<int>? _visitorsByDayLast7;

  late final ComplaintService _complaintService = ComplaintService(
    baseUrl: Env.apiBaseUrl,
  );

  late final NoticeService _noticeService = NoticeService(
    baseUrl: Env.apiBaseUrl,
  );

  final ResidentSignupService _signupService = ResidentSignupService();

  int _notificationCount = 0;
  int _sosBadgeCount = 0;
  int _unreadNoticesCount = 0;
  bool _initializedUnreadNotices = false;
  final FirestoreService _firestore = FirestoreService();
  String? _photoUrl;

  StreamSubscription<QuerySnapshot>? _pendingSignupsSubscription;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadNotificationCount();
    _setupNotificationListener();
    _setupPendingSignupsListener();
    _loadAdminProfile();
    _maybeAutoRunTour();
  }

  @override
  void dispose() {
    _pendingSignupsSubscription?.cancel();
    super.dispose();
  }

  void _setupPendingSignupsListener() {
    _pendingSignupsSubscription = FirebaseFirestore.instance
        .collection('societies')
        .doc(widget.societyId)
        .collection('members')
        .where('systemRole', isEqualTo: 'resident')
        .where('active', isEqualTo: false)
        .snapshots()
        .listen((_) {
      if (mounted) _loadNotificationCount();
    });
  }

  void _maybeAutoRunTour() async {
    final seen = await TourStorage.hasSeenTourForRole(widget.systemRole ?? 'admin');
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
      final keys = <GlobalKey<State<StatefulWidget>>>[_keyResidents, _keyGuards];
      if (SocietyModules.isEnabled(SocietyModuleIds.complaints)) keys.add(_keyComplaints);
      if (SocietyModules.isEnabled(SocietyModuleIds.notices)) keys.add(_keyNotices);
      if (SocietyModules.isEnabled(SocietyModuleIds.sos)) keys.add(_keySos);
      if (keys.isEmpty) return;
      ShowCaseWidget.of(_showCaseContext!).startShowCase(keys);
    } catch (_) {
      if (mounted) TourStorage.setHasSeenTourForRole(widget.systemRole ?? 'admin');
    }
  }

  Future<void> _loadAdminProfile() async {
    try {
      final membership = await _firestore.getCurrentUserMembership();
      if (!mounted || membership == null) return;

      setState(() {
        _photoUrl = membership['photoUrl'] as String?;
      });
    } catch (e, st) {
      AppLogger.e("Error loading admin profile photo", error: e, stackTrace: st);
    }
  }

  void _setupNotificationListener() {
    // Listen for new notifications to update count
    final notificationService = NotificationService();
    notificationService.setOnNotificationReceived((data) {
      final type = (data['type'] ?? '').toString();
      if (type == 'complaint') {
        // Complaints are action-based; reload counts from backend
        _loadNotificationCount();
      } else if (type == 'notice') {
        // Informational notice: increment unread counter only
        if (mounted) {
          setState(() {
            _unreadNoticesCount += 1;
            _notificationCount += 1;
          });
        }
      } else if (type == 'sos' && SocietyModules.isEnabled(SocietyModuleIds.sos)) {
        // Simple SOS badge to highlight attention (only when module enabled)
        if (mounted) {
          setState(() {
            _sosBadgeCount = 1;
          });
        }
      }
    });
    notificationService.setOnNotificationTap((data) {
      final type = (data['type'] ?? '').toString();
      if (type == 'complaint' && SocietyModules.isEnabled(SocietyModuleIds.complaints)) {
        _navigateToTab(3);
      } else if (type == 'notice' && SocietyModules.isEnabled(SocietyModuleIds.notices)) {
        // Mark notices as read for this session and navigate to notices tab (index 4)
        if (mounted) {
          setState(() {
            _unreadNoticesCount = 0;
          });
        }
        _navigateToTab(4);
      } else if (type == 'sos' && SocietyModules.isEnabled(SocietyModuleIds.sos)) {
        final societyId = (data['society_id'] ?? widget.societyId).toString();
        final flatNo = (data['flat_no'] ?? '').toString();
        final residentName = (data['resident_name'] ?? 'Resident').toString();
        final phone = (data['resident_phone'] ?? '').toString();
        final sosId = (data['sos_id'] ?? '').toString();

        if (!mounted || sosId.isEmpty) return;

        // Clear SOS badge once user navigates to details
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

  Future<void> _loadNotificationCount() async {
    try {
      int totalCount = 0;
      
      // Count pending complaints (only if module enabled)
      if (SocietyModules.isEnabled(SocietyModuleIds.complaints)) {
        final complaintsResult = await _complaintService.getAllComplaints(societyId: widget.societyId);
        if (complaintsResult.isSuccess && complaintsResult.data != null) {
          final pendingComplaints = complaintsResult.data!.where((c) {
            final status = (c['status'] ?? '').toString().toUpperCase();
            return status == 'PENDING' || status == 'IN_PROGRESS';
          }).length;
          totalCount += pendingComplaints;
        }
      }
      
      // Count recent notices (only if module enabled)
      if (SocietyModules.isEnabled(SocietyModuleIds.notices)) {
        final noticesResult = await _noticeService.getNotices(
          societyId: widget.societyId,
          activeOnly: true,
        );
        if (!_initializedUnreadNotices && noticesResult.isSuccess && noticesResult.data != null) {
          final now = DateTime.now();
          final recentNotices = noticesResult.data!.where((n) {
            try {
              final createdAt = n['created_at']?.toString() ?? '';
              if (createdAt.isEmpty) return false;
              final created = DateTime.parse(createdAt.replaceAll("Z", "+00:00"));
              final hoursDiff = now.difference(created).inHours;
              return hoursDiff <= 24; // Notices from last 24 hours
            } catch (e) {
              return false;
            }
          }).length;
          _unreadNoticesCount = recentNotices;
          _initializedUnreadNotices = true;
        }
        totalCount += _unreadNoticesCount;
      }

      // Count pending resident signups
      final signupsResult = await _signupService.getPendingSignups(societyId: widget.societyId);
      if (signupsResult.isSuccess && signupsResult.data != null) {
        totalCount += signupsResult.data!.length;
      }

      if (mounted) {
        setState(() {
          _notificationCount = totalCount;
        });
      }
    } catch (e) {
      AppLogger.e("Error loading notification count", error: e);
    }
  }

  void _showNotificationDrawer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AdminNotificationDrawer(
        societyId: widget.societyId,
        adminId: widget.adminId,
        onNavigateToPendingSignup: () {
          Navigator.pop(context);
          widget.onTabNavigate?.call(1, 1);
        },
      ),
    ).then((_) {
      // User has seen notifications; clear unread notices and SOS badge for this session
      if (mounted) {
        setState(() {
          _unreadNoticesCount = 0;
          _sosBadgeCount = 0;
        });
      }
      _loadNotificationCount();
    });
  }

  void _navigateToTab(int index, [int? residentsSubTab]) {
    if (widget.onTabNavigate != null) {
      widget.onTabNavigate!(index, residentsSubTab);
    } else {
      // Fallback: Try to find AdminShellScreen in the widget tree
      final context = this.context;
      // Navigate using a key or context - for now show message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Navigate to tab $index"),
          backgroundColor: AppColors.admin,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _service.getStats(societyId: widget.societyId);

      if (!mounted) return;

      if (result.isSuccess && result.data != null) {
        setState(() {
          _stats = result.data!;
          _isLoading = false;
        });
        AppLogger.i("Admin dashboard stats loaded", data: _stats);
        // Load society-wide visitor chart (no guard filter)
        if (SocietyModules.isEnabled(SocietyModuleIds.visitorManagement)) {
          try {
            final counts = await _firestore.getVisitorCountsByDayLast7Days(
              societyId: widget.societyId,
            );
            if (mounted) setState(() => _visitorsByDayLast7 = counts);
          } catch (e) {
            AppLogger.w("Admin visitor chart load failed", error: e.toString());
          }
        }
      } else {
        setState(() {
          _isLoading = false;
          _error = result.error ?? "Failed to load stats";
        });
        AppLogger.w("Failed to load admin stats: ${result.error}");
      }
    } catch (e) {
      AppLogger.e("Error loading admin stats", error: e);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = "Connection error. Please try again.";
        });
      }
    }
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
        TourStorage.setHasSeenTourForRole(widget.systemRole ?? 'admin');
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
          // Background Gradient Header (purple theme)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 260,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.admin, Color(0xFF7C3AED)], // Purple gradient
                ),
              ),
            ),
          ),

          RefreshIndicator(
            onRefresh: () async {
              await _loadStats();
              await _loadAdminProfile();
            },
            color: AppColors.admin, // Purple refresh indicator
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
                children: [
                  DashboardHero(
                    userName: widget.adminName,
                    statusMessage: (_notificationCount + _sosBadgeCount) > 0
                        ? '${_notificationCount + _sosBadgeCount} item(s) need attention'
                        : 'Society overview',
                    mascotMood: (_notificationCount + _sosBadgeCount) > 0 ? SentiMood.alert : SentiMood.idle,
                    avatar: CircleAvatar(
                      backgroundColor: Colors.white24,
                      backgroundImage: (_photoUrl != null && _photoUrl!.isNotEmpty)
                          ? CachedNetworkImageProvider(_photoUrl!)
                          : null,
                      child: (_photoUrl == null || _photoUrl!.isEmpty)
                          ? const Icon(Icons.person_rounded, color: Colors.white)
                          : null,
                    ),
                    trailingActions: Stack(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.notifications_rounded, color: Colors.white),
                          onPressed: _showNotificationDrawer,
                        ),
                        Builder(
                          builder: (context) {
                            final totalBadgeCount = _notificationCount + _sosBadgeCount;
                            if (totalBadgeCount <= 0) return const SizedBox.shrink();
                            return Positioned(
                              right: 8,
                              top: 8,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: AppColors.error,
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                                child: Text(
                                  totalBadgeCount > 9 ? '9+' : totalBadgeCount.toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildPremiumSocietyCard(),
                  const SizedBox(height: 20),

                  if (_stats != null) ...[
                    const SizedBox(height: 24),
                    const Text(
                      "Today at a glance",
                      style: TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildStatsSection(),
                    if (SocietyModules.isEnabled(SocietyModuleIds.visitorManagement) && _visitorsByDayLast7 != null) ...[
                      const SizedBox(height: 16),
                      VisitorsChart(
                        countsByDay: _visitorsByDayLast7!,
                        barColor: AppColors.admin,
                      ),
                    ],
                  ],

                  const SizedBox(height: 25),
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
                  const SizedBox(height: 25),
                ],
              ),
            ),
          ),

          if (_isLoading) AppLoader.overlay(show: true, message: "Loading Stats..."),
        ],
      ),
      ),
    );
      },
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
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.societyId,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                const Text(
                  "Admin Portal Active",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
        ],
      ),
    );
  }

  /// Wraps the existing stats grid into a soft card module
  Widget _buildStatsSection() {
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
      child: _buildStatsGrid(),
    );
  }

  Widget _buildStatsGrid() {
    final stats = _stats!;
    final children = <Widget>[
      DashboardStatCard(
        label: "Residents",
        value: (stats['total_residents'] ?? 0).toString(),
        icon: Icons.people_rounded,
        color: AppColors.admin,
      ),
      DashboardStatCard(
        label: "Guards",
        value: (stats['total_guards'] ?? 0).toString(),
        icon: Icons.shield_rounded,
        color: AppColors.primary,
      ),
      DashboardStatCard(
        label: "Flats",
        value: (stats['total_flats'] ?? 0).toString(),
        icon: Icons.home_rounded,
        color: AppColors.success,
      ),
    ];
    if (SocietyModules.isEnabled(SocietyModuleIds.visitorManagement)) {
      children.addAll([
        DashboardStatCard(
          label: "Visitors Today",
          value: (stats['visitors_today'] ?? 0).toString(),
          icon: Icons.person_add_rounded,
          color: AppColors.warning,
        ),
        DashboardStatCard(
          label: "Pending",
          value: (stats['pending_approvals'] ?? 0).toString(),
          icon: Icons.hourglass_empty_rounded,
          color: AppColors.warning,
        ),
        DashboardStatCard(
          label: "Approved Today",
          value: (stats['approved_today'] ?? 0).toString(),
          icon: Icons.verified_user_rounded,
          color: AppColors.success,
        ),
      ]);
    }
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: children,
    );
  }

  Widget _buildActionGrid() {
    final children = <Widget>[
      Showcase(
        key: _keyResidents,
        title: "Approve Residents",
        description: "View and approve pending resident signups.",
        child: DashboardQuickAction(
          label: "Residents Directory",
          icon: Icons.people_rounded,
          tint: AppColors.admin,
          onTap: () => _navigateToTab(1),
        ),
      ),
      Showcase(
        key: _keyGuards,
        title: "Share Society Code / QR",
        description: "Generate Guard Join QR so guards can join your society.",
        child: DashboardQuickAction(
          label: "Security Staff",
          icon: Icons.shield_rounded,
          tint: AppColors.primary,
          onTap: () => _navigateToTab(2),
        ),
      ),
      DashboardQuickAction(
        label: "Manage Flats",
        icon: Icons.home_rounded,
        tint: AppColors.success,
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("Flats management coming soon!"),
              backgroundColor: AppColors.admin,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
            ),
          );
        },
      ),
    ];
    if (SocietyModules.isEnabled(SocietyModuleIds.complaints)) {
      children.add(
        Showcase(
          key: _keyComplaints,
          title: "Complaints",
          description: "View and resolve society complaints.",
          child: DashboardQuickAction(
            label: "Complaints",
            icon: Icons.report_problem_rounded,
            tint: AppColors.error,
            onTap: () => _navigateToTab(3),
          ),
        ),
      );
    }
    if (SocietyModules.isEnabled(SocietyModuleIds.notices)) {
      children.add(
        Showcase(
          key: _keyNotices,
          title: "Create Notice",
          description: "View notices and create new announcements.",
          child: DashboardQuickAction(
            label: "Notice Board",
            icon: Icons.notifications_rounded,
            tint: AppColors.warning,
            onTap: () => _navigateToTab(4),
          ),
        ),
      );
    }
    if (SocietyModules.isEnabled(SocietyModuleIds.violations)) {
      children.add(
        DashboardQuickAction(
          label: "Violations",
          icon: Icons.directions_car_rounded,
          tint: AppColors.warning,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdminManageViolationsScreen(
                  adminId: widget.adminId,
                  adminName: widget.adminName,
                  societyId: widget.societyId,
                  onBackPressed: () => Navigator.pop(context),
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
          key: _keySos,
          title: "SOS Alerts",
          description: "View and respond to emergency SOS from residents.",
          child: DashboardQuickAction(
            label: "SOS Alerts",
            icon: Icons.sos_rounded,
            tint: AppColors.error,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SosAlertsScreen(
                    societyId: widget.societyId,
                    role: 'admin',
                  ),
                ),
              );
            },
          ),
        ),
      );
    }
    if (widget.systemRole?.toLowerCase() == 'super_admin') {
      children.add(
        DashboardQuickAction(
          label: "Manage Admins",
          icon: Icons.admin_panel_settings_rounded,
          tint: AppColors.admin,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdminManageAdminsScreen(
                  adminId: widget.adminId,
                  societyId: widget.societyId,
                  systemRole: widget.systemRole,
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
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.3,
      children: children,
    );
  }

}
