import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:showcaseview/showcaseview.dart';
import '../ui/app_colors.dart';
import '../ui/app_loader.dart';
import '../services/resident_service.dart' as resident;
import '../services/notification_service.dart';
import '../core/app_logger.dart';
import '../core/env.dart';
import '../core/tour_storage.dart';
import '../core/society_modules.dart';
import 'resident_complaint_screen.dart';
import 'resident_complaints_list_screen.dart';
import 'resident_violations_screen.dart';
import 'resident_approvals_screen.dart';
import 'resident_history_screen.dart';
import 'notice_board_screen.dart';
import 'role_select_screen.dart';
import '../widgets/resident_notification_drawer.dart';
import '../widgets/dashboard_hero.dart';
import '../widgets/dashboard_stat_card.dart';
import '../widgets/dashboard_quick_action.dart';
import '../services/firestore_service.dart';

/// Resident Dashboard Screen
///
/// Purpose: Overview screen for residents showing:
/// - Welcome message with resident info
/// - Quick stats (pending approvals count)
/// - Quick action cards to navigate to Approvals/History
///
/// Theme: Green/Success theme (matching resident login)
class ResidentDashboardScreen extends StatefulWidget {
  final String residentId;
  final String residentName;
  final String societyId;
  final String flatNo;
  final VoidCallback? onNavigateToApprovals;
  final VoidCallback? onNavigateToHistory;
  final VoidCallback? onNavigateToComplaints;
  final VoidCallback? onNavigateToNotices;

  const ResidentDashboardScreen({
    super.key,
    required this.residentId,
    required this.residentName,
    required this.societyId,
    required this.flatNo,
    this.onNavigateToApprovals,
    this.onNavigateToHistory,
    this.onNavigateToComplaints,
    this.onNavigateToNotices,
  });

  @override
  State<ResidentDashboardScreen> createState() => _ResidentDashboardScreenState();
}

class _ResidentDashboardScreenState extends State<ResidentDashboardScreen> {
  final FirestoreService _firestore = FirestoreService();
  late final resident.ResidentService _service = resident.ResidentService(
    baseUrl: Env.apiBaseUrl,
  );

  final GlobalKey<State<StatefulWidget>> _keyApprovals = GlobalKey<State<StatefulWidget>>();
  final GlobalKey<State<StatefulWidget>> _keyComplaints = GlobalKey<State<StatefulWidget>>();
  final GlobalKey<State<StatefulWidget>> _keySos = GlobalKey<State<StatefulWidget>>();

  int _pendingCount = 0;
  int _approvedCount = 0;
  int _rejectedCount = 0;
  int _notificationCount = 0;
  int _unreadNoticesCount = 0;
  bool _initializedUnreadNotices = false;
  bool _isLoading = false;
  String? _photoUrl;
  String? _phone;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _loadResidentProfilePhoto();
    _setupNotificationListener();
    _maybeAutoRunTour();
  }

  void _maybeAutoRunTour() async {
    final seen = await TourStorage.hasSeenTourResident();
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
      if (SocietyModules.isEnabled(SocietyModuleIds.visitorManagement)) keys.add(_keyApprovals);
      if (SocietyModules.isEnabled(SocietyModuleIds.complaints)) keys.add(_keyComplaints);
      if (SocietyModules.isEnabled(SocietyModuleIds.sos)) keys.add(_keySos);
      if (keys.isEmpty) return;
      ShowCaseWidget.of(_showCaseContext!).startShowCase(keys);
    } catch (_) {
      if (mounted) TourStorage.setHasSeenTourResident();
    }
  }

  Future<void> _loadResidentProfilePhoto() async {
    try {
      final membership = await _firestore.getCurrentUserMembership();
      if (!mounted || membership == null) return;

      setState(() {
        _photoUrl = membership['photoUrl'] as String?;
        _phone = membership['phone'] as String?;
      });
    } catch (e, st) {
      AppLogger.e("Error loading resident profile photo (dashboard)", error: e, stackTrace: st);
    }
  }

  void _setupNotificationListener() {
    // Listen for new notifications to update count
    final notificationService = NotificationService();
    notificationService.setOnNotificationReceived((data) {
      final type = (data['type'] ?? '').toString();
      if (type == 'visitor') {
        // Visitor approvals are action-based; reload stats/pending count
        _loadDashboardData();
      } else if (type == 'notice') {
        // Informational notice: increment unread counter only
        if (!mounted) return;
        setState(() {
          _unreadNoticesCount += 1;
          _notificationCount = _pendingCount + _unreadNoticesCount;
        });
      }
    });
    notificationService.setOnNotificationTap((data) {
      final type = (data['type'] ?? '').toString();
      if (type == 'visitor') {
        // Open approvals screen/tab (handled via shell/tab; for now just refresh)
        _loadDashboardData();
      } else if (type == 'notice') {
        // Mark notices as read for this session and open notice board
        if (mounted) {
          setState(() {
            _unreadNoticesCount = 0;
            _notificationCount = _pendingCount;
          });
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NoticeBoardScreen(
              societyId: widget.societyId,
              themeColor: AppColors.success,
            ),
          ),
        );
      } else if (type == 'complaint') {
        // For complaints, open complaints tab/screen in future; for now just log
        AppLogger.i("Complaint notification tapped (resident)", data: data);
      }
    });
  }

  // ✅ Helper: Load notices from Firestore and return as List<Map<String,dynamic>>
  Future<List<Map<String, dynamic>>> _loadNoticesList() async {
    try {
      final raw = await _firestore.getNotices(
        societyId: widget.societyId,
        activeOnly: true,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          AppLogger.w("getNotices timeout");
          return <Map<String, dynamic>>[]; // Return correct type
        },
      );

      return raw.map<Map<String, dynamic>>((n) {
        return Map<String, dynamic>.from(n as Map);
      }).toList();
    } catch (e, st) {
      AppLogger.e("Error loading notices (Firestore)", error: e, stackTrace: st);
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // Load pending approvals with timeout
      resident.ApiResult<List<dynamic>>? approvalsResult;
      try {
        approvalsResult = await _service
            .getApprovals(
              societyId: widget.societyId,
              flatNo: widget.flatNo,
            )
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                AppLogger.w("getApprovals timeout");
                return resident.ApiResult.failure("Request timeout");
              },
            );
      } catch (e) {
        AppLogger.e("Error loading approvals", error: e);
        approvalsResult = resident.ApiResult.failure("Failed to load approvals");
      }

      // Load history for stats with timeout
      resident.ApiResult<List<dynamic>>? historyResult;
      try {
        historyResult = await _service
            .getHistory(
              societyId: widget.societyId,
              flatNo: widget.flatNo,
              limit: 100,
            )
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                AppLogger.w("getHistory timeout");
                return resident.ApiResult.failure("Request timeout");
              },
            );
      } catch (e) {
        AppLogger.e("Error loading history", error: e);
        historyResult = resident.ApiResult.failure("Failed to load history");
      }

      if (!mounted) return;

      if (approvalsResult != null &&
          approvalsResult.isSuccess &&
          approvalsResult.data != null) {
        _pendingCount = approvalsResult.data!.length;
      }

      if (historyResult != null && historyResult.isSuccess && historyResult.data != null) {
        final history = historyResult.data!;
        _approvedCount = history.where((item) {
          final status = item['status']?.toString().toUpperCase() ?? '';
          return status == 'APPROVED';
        }).length;
        _rejectedCount = history.where((item) {
          final status = item['status']?.toString().toUpperCase() ?? '';
          return status == 'REJECTED';
        }).length;
      }

      // ✅ Count recent notices (created in last 24 hours) only once to seed unread count
      if (!_initializedUnreadNotices) {
        try {
          final noticesList = await _loadNoticesList();
          final now = DateTime.now();

          final recentNotices = noticesList.where((n) {
            try {
              final createdAtStr = (n['created_at'] ?? n['createdAt'])?.toString() ?? '';
              if (createdAtStr.isEmpty) return false;
              final created = DateTime.parse(createdAtStr.replaceAll("Z", "+00:00"));
              final hoursDiff = now.difference(created).inHours;
              return hoursDiff <= 24;
            } catch (_) {
              return false;
            }
          }).length;

          _unreadNoticesCount = recentNotices;
          _initializedUnreadNotices = true;
        } catch (e) {
          AppLogger.e("Error counting notices", error: e);
        }
      }

      // Total notification count = pending approvals + unread informational notices
      _notificationCount = _pendingCount + _unreadNoticesCount;

      if (mounted) {
        setState(() => _isLoading = false);
      }

      AppLogger.i("Resident dashboard loaded", data: {
        "pending": _pendingCount,
        "approved": _approvedCount,
        "rejected": _rejectedCount,
        "unread_notices": _unreadNoticesCount,
      });
    } catch (e) {
      AppLogger.e("Error loading dashboard data", error: e);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _onWillPop() async {
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
      return false; // Don't pop, we already navigated
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return ShowCaseWidget(
      enableAutoScroll: true,
      scrollDuration: const Duration(milliseconds: 400),
      onFinish: () {
        TourStorage.setHasSeenTourResident();
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
          // Green Gradient Header Background
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 260,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.success,
                    AppColors.success.withOpacity(0.7),
                  ],
                ),
              ),
            ),
          ),

          RefreshIndicator(
            onRefresh: _loadDashboardData,
            color: AppColors.success,
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
                children: [
                  DashboardHero(
                    userName: widget.residentName,
                    statusMessage: _pendingCount > 0
                        ? '$_pendingCount approval(s) pending'
                        : "You're all set",
                    mascotMood: _pendingCount > 0 ? SentiMood.alert : SentiMood.happy,
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
                          onPressed: () {
                            if (mounted) {
                              setState(() {
                                _unreadNoticesCount = 0;
                                _notificationCount = _pendingCount;
                              });
                            }
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (context) => ResidentNotificationDrawer(
                                societyId: widget.societyId,
                                residentId: widget.residentId,
                                flatNo: widget.flatNo,
                              ),
                            ).then((_) {
                              _loadDashboardData();
                            });
                          },
                        ),
                        if (_notificationCount > 0)
                          Positioned(
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
                                _notificationCount > 9 ? '9+' : _notificationCount.toString(),
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
                  ),
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
                ],
              ),
            ),
          ),

          if (_isLoading) AppLoader.overlay(show: true, message: "Loading Dashboard…"),
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
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.apartment_rounded, color: Colors.white),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.societyId,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "Flat ${widget.flatNo}",
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
        ],
      ),
    );
  }

  /// Horizontal strip of rounded category chips similar to NoBrokerHood
  /// Stats row wrapped in a subtle card, to feel more like a module
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
            child: DashboardStatCard(
              label: "Pending",
              value: _pendingCount.toString(),
              icon: Icons.pending_actions_rounded,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DashboardStatCard(
              label: "Approved",
              value: _approvedCount.toString(),
              icon: Icons.check_circle_rounded,
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DashboardStatCard(
              label: "Rejected",
              value: _rejectedCount.toString(),
              icon: Icons.cancel_rounded,
              color: AppColors.error,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionGrid() {
    final children = <Widget>[];
    if (SocietyModules.isEnabled(SocietyModuleIds.visitorManagement)) {
      children.add(
        Showcase(
          key: _keyApprovals,
          title: "Approve / Reject Visitors",
          description: "Open here to see pending visitor requests and approve or reject.",
          child: DashboardQuickAction(
            label: "Pending Approvals",
            icon: Icons.verified_user_rounded,
            tint: AppColors.warning,
            onTap: () {
              if (widget.onNavigateToApprovals != null) {
                widget.onNavigateToApprovals!();
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ResidentApprovalsScreen(
                      residentId: widget.residentId,
                      societyId: widget.societyId,
                      flatNo: widget.flatNo,
                    ),
                  ),
                );
              }
            },
          ),
        ),
      );
      children.add(
        DashboardQuickAction(
          label: "View History",
          icon: Icons.history_rounded,
          tint: AppColors.success,
          onTap: () {
            if (widget.onNavigateToHistory != null) {
              widget.onNavigateToHistory!();
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ResidentHistoryScreen(
                    residentId: widget.residentId,
                    societyId: widget.societyId,
                    flatNo: widget.flatNo,
                  ),
                ),
              );
            }
          },
        ),
      );
    }
    if (SocietyModules.isEnabled(SocietyModuleIds.complaints)) {
      children.add(
        DashboardQuickAction(
          label: "Raise Complaint",
          icon: Icons.report_problem_rounded,
          tint: AppColors.error,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ResidentComplaintScreen(
                  residentId: widget.residentId,
                  residentName: widget.residentName,
                  societyId: widget.societyId,
                  flatNo: widget.flatNo,
                ),
              ),
            );
          },
        ),
      );
      children.add(
        Showcase(
          key: _keyComplaints,
          title: "Complaints",
          description: "View and manage your complaints here.",
          child: DashboardQuickAction(
            label: "My Complaints",
            icon: Icons.inbox_rounded,
            tint: AppColors.primary,
            onTap: () {
              if (widget.onNavigateToComplaints != null) {
                widget.onNavigateToComplaints!();
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ResidentComplaintsListScreen(
                      residentId: widget.residentId,
                      societyId: widget.societyId,
                      flatNo: widget.flatNo,
                    ),
                  ),
                );
              }
            },
          ),
        ),
      );
    }
    if (SocietyModules.isEnabled(SocietyModuleIds.notices)) {
      children.add(
        DashboardQuickAction(
          label: "Notice Board",
          icon: Icons.notifications_rounded,
          tint: AppColors.warning,
          onTap: () {
            if (widget.onNavigateToNotices != null) {
              widget.onNavigateToNotices!();
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => NoticeBoardScreen(
                    societyId: widget.societyId,
                    themeColor: AppColors.success,
                  ),
                ),
              );
            }
          },
        ),
      );
    }
    if (SocietyModules.isEnabled(SocietyModuleIds.violations)) {
      children.add(
        DashboardQuickAction(
          label: "My Violations",
          icon: Icons.directions_car_rounded,
          tint: AppColors.warning,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ResidentViolationsScreen(
                  residentId: widget.residentId,
                  societyId: widget.societyId,
                  flatNo: widget.flatNo,
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
          title: "Emergency SOS",
          description: "Send an instant alert to security and admin in case of emergency.",
          child: DashboardQuickAction(
            label: "Emergency SOS",
            icon: Icons.sos_rounded,
            tint: AppColors.error,
            onTap: _showSosConfirmDialog,
          ),
        ),
      );
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

  /// Show confirmation dialog before sending SOS
  void _showSosConfirmDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Emergency SOS'),
        content: const Text(
          'This will send an emergency alert to your society\'s security/admin team '
          'with your flat details. Use only in case of real emergency.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _sendSos();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Send SOS'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendSos() async {
    try {
      final sosId = await _firestore.createSosRequest(
        societyId: widget.societyId,
        residentId: widget.residentId,
        residentName: widget.residentName,
        flatNo: widget.flatNo,
        phone: _phone,
      );

      // Best-effort: also trigger FastAPI backend to send FCM to staff
      try {
        await _service.sendSosAlert(
          societyId: widget.societyId,
          flatNo: widget.flatNo,
          residentName: widget.residentName,
          residentPhone: _phone,
          sosId: sosId,
        );
      } catch (_) {
        // Ignore backend SOS errors here; Firestore record is already created
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('SOS sent to security team'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      AppLogger.e("Error sending SOS", error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to send SOS. Please try again or call security.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }
}

