import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:showcaseview/showcaseview.dart';
import '../ui/app_loader.dart';
import '../services/admin_service.dart';
import '../services/complaint_service.dart';
import '../services/notice_service.dart';
import '../services/notification_service.dart';
import '../services/firestore_service.dart';
import '../services/firebase_visitor_service.dart';
import '../services/resident_signup_service.dart';
import '../core/app_logger.dart';
import '../core/env.dart';
import '../core/tour_storage.dart';
import '../core/society_modules.dart';
import 'sos_detail_screen.dart';
import 'sos_alerts_screen.dart';
import 'admin_join_requests_screen.dart';
import 'admin_manage_admins_screen.dart';
import 'admin_manage_violations_screen.dart';
import 'onboarding_choose_role_screen.dart';
import '../widgets/admin_notification_drawer.dart';
import '../widgets/dashboard_hero.dart';
import '../widgets/dashboard_stat_card.dart';
import '../widgets/dashboard_quick_action.dart';
import '../utils/error_messages.dart';
import '../widgets/visitors_chart.dart';
import '../widgets/dashboard_insights_card.dart';
import '../widgets/error_retry_widget.dart';
import '../services/admin_notification_aggregator.dart';

/// Admin Dashboard Screen
///
/// Overview screen for admins showing key metrics and quick actions
/// Theme: Unified primary (blue/indigo); no role-specific colors.
class AdminDashboardScreen extends StatefulWidget {
  final String adminId;
  final String adminName;
  final String societyId;
  final String systemRole; // admin or super_admin
  /// Callback to navigate to tabs. Second arg optional: 1 = open Residents on Pending signups tab.
  final void Function(int index, [int? residentsSubTab])? onTabNavigate;

  const AdminDashboardScreen({
    super.key,
    required this.adminId,
    required this.adminName,
    required this.societyId,
    required this.systemRole,
    this.onTabNavigate,
  });

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late final AdminService _service = AdminService(
    baseUrl: Env.apiBaseUrl,
  );

  final GlobalKey<State<StatefulWidget>> _keyResidents =
      GlobalKey<State<StatefulWidget>>();
  final GlobalKey<State<StatefulWidget>> _keyGuards =
      GlobalKey<State<StatefulWidget>>();
  final GlobalKey<State<StatefulWidget>> _keyComplaints =
      GlobalKey<State<StatefulWidget>>();
  final GlobalKey<State<StatefulWidget>> _keyNotices =
      GlobalKey<State<StatefulWidget>>();
  final GlobalKey<State<StatefulWidget>> _keySos =
      GlobalKey<State<StatefulWidget>>();

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
  final FirebaseVisitorService _visitorService = FirebaseVisitorService();
  String? _photoUrl;

  /// Admin Insights Lite: today's visitor counts. null = loading.
  bool _insightsLoading = true;
  int? _countTotalToday;
  int? _countPendingToday;
  int? _countCabToday;
  int? _countDeliveryToday;

  StreamSubscription<QuerySnapshot>? _pendingSignupsSubscription;

  final GlobalKey _drawerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadInsightsCounts();
    _loadNotificationCount();
    _setupNotificationListener();
    _setupPendingSignupsListener();
    _loadAdminProfile();
    _maybeAutoRunTour();
    _preloadBellCount();
  }

  Future<void> _preloadBellCount() async {
    try {
      final counts = await AdminNotificationAggregator.load(
        societyId: widget.societyId,
        firestore: _firestore,
        complaintService: _complaintService,
        noticeService: _noticeService,
        signupService: _signupService,
      );

      if (!mounted) return;
      setState(() {
        _notificationCount = counts.total;
        _sosBadgeCount = counts.openSos > 0 ? 1 : 0;
      });
    } catch (_) {
      // fail silently; bell can update later
    }
  }

  Future<void> _loadInsightsCounts() async {
    if (!SocietyModules.isEnabled(SocietyModuleIds.visitorManagement)) {
      if (mounted) setState(() => _insightsLoading = false);
      return;
    }
    try {
      final results = await Future.wait([
        _visitorService.getVisitorCountToday(widget.societyId),
        _visitorService.getPendingVisitorCountToday(widget.societyId),
        _visitorService.getCabVisitorCountToday(widget.societyId),
        _visitorService.getDeliveryVisitorCountToday(widget.societyId),
      ]);
      if (mounted) {
        setState(() {
          _countTotalToday = results[0];
          _countPendingToday = results[1];
          _countCabToday = results[2];
          _countDeliveryToday = results[3];
          _insightsLoading = false;
        });
      }
    } catch (e) {
      AppLogger.e('Admin insights counts failed', error: e);
      if (mounted) {
        setState(() {
          _insightsLoading = false;
          _countTotalToday = 0;
          _countPendingToday = 0;
          _countCabToday = 0;
          _countDeliveryToday = 0;
        });
      }
    }
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
    final seen =
        await TourStorage.hasSeenTourForRole(widget.systemRole ?? 'admin');
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
      final keys = <GlobalKey<State<StatefulWidget>>>[
        _keyResidents,
        _keyGuards
      ];
      if (SocietyModules.isEnabled(SocietyModuleIds.complaints))
        keys.add(_keyComplaints);
      if (SocietyModules.isEnabled(SocietyModuleIds.notices))
        keys.add(_keyNotices);
      if (SocietyModules.isEnabled(SocietyModuleIds.sos)) keys.add(_keySos);
      if (keys.isEmpty) return;
      ShowCaseWidget.of(_showCaseContext!).startShowCase(keys);
    } catch (_) {
      if (mounted)
        TourStorage.setHasSeenTourForRole(widget.systemRole ?? 'admin');
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
      AppLogger.e("Error loading admin profile photo",
          error: e, stackTrace: st);
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
      } else if (type == 'sos' &&
          SocietyModules.isEnabled(SocietyModuleIds.sos)) {
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
      if (type == 'complaint' &&
          SocietyModules.isEnabled(SocietyModuleIds.complaints)) {
        _navigateToTab(3);
      } else if (type == 'notice' &&
          SocietyModules.isEnabled(SocietyModuleIds.notices)) {
        // Mark notices as read for this session and navigate to notices tab (index 4)
        if (mounted) {
          setState(() {
            _unreadNoticesCount = 0;
          });
        }
        _navigateToTab(4);
      } else if (type == 'sos' &&
          SocietyModules.isEnabled(SocietyModuleIds.sos)) {
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
      int openSosCount = 0;

      // Count pending complaints (only if module enabled)
      if (SocietyModules.isEnabled(SocietyModuleIds.complaints)) {
        final complaintsResult = await _complaintService.getAllComplaints(
            societyId: widget.societyId);
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
        if (!_initializedUnreadNotices &&
            noticesResult.isSuccess &&
            noticesResult.data != null) {
          final now = DateTime.now();
          final recentNotices = noticesResult.data!.where((n) {
            try {
              final createdAt = n['created_at']?.toString() ?? '';
              if (createdAt.isEmpty) return false;
              final created =
                  DateTime.parse(createdAt.replaceAll("Z", "+00:00"));
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

      // Count pending residents: Join Requests (Find Society) + society-code signups
      try {
        final joinRequests =
            await _firestore.getResidentJoinRequestsForAdmin(widget.societyId);
        totalCount += joinRequests.length;
      } catch (_) {}
      final signupsResult =
          await _signupService.getPendingSignups(societyId: widget.societyId);
      if (signupsResult.isSuccess && signupsResult.data != null) {
        totalCount += signupsResult.data!.length;
      }

      // Count open SOS (only if module enabled)
      if (SocietyModules.isEnabled(SocietyModuleIds.sos)) {
        final sosList = await _firestore.getSosRequests(societyId: widget.societyId);
        openSosCount = sosList.where((s) {
          final status = (s['status'] ?? 'OPEN').toString().toUpperCase();
          return status == 'OPEN';
        }).length;
        totalCount += openSosCount;
      }

      if (mounted) {
        setState(() {
          _notificationCount = totalCount;
          _sosBadgeCount = openSosCount > 0 ? 1 : 0;
        });
      }
    } catch (e) {
      AppLogger.e("Error loading notification count", error: e);
    }
  }

  Future<void> _refreshBellOnly() async {
    final state = _drawerKey.currentState;
    if (state == null) return;
    await (state as dynamic).refresh();
  }

  void _showNotificationDrawer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => AdminNotificationDrawer(
        key: _drawerKey,
        societyId: widget.societyId,
        adminId: widget.adminId,
        // inside AdminDashboardScreen
        onNotificationTap: (notification) async {
          if (!mounted) return;

          // 1) close drawer first
          Navigator.pop(context);

          final type = notification['type']?.toString();

          // JOIN REQUESTS
          if (type == 'resident_signup' || type == 'admin_signup') {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AdminJoinRequestsScreen(
                  societyId: widget.societyId,
                ),
              ),
            );

            // 2) refresh bell ONLY after coming back
            await _refreshBellOnly();
            return;
          }

          // COMPLAINTS TAB
          if (type == 'complaint') {
            _navigateToTab(3);
            await _refreshBellOnly(); // optional if tab actions can change counts
            return;
          }

          // NOTICES TAB
          if (type == 'notice') {
            _navigateToTab(4);
            await _refreshBellOnly(); // optional
            return;
          }

          // SOS DETAILS
          if (type == 'sos') {
            final sosId = notification['id']?.toString() ?? '';
            if (sosId.isEmpty) return;

            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SosDetailScreen(
                  societyId: widget.societyId,
                  sosId: sosId,
                  flatNo: notification['flat_no']?.toString() ?? '',
                  residentName:
                      notification['resident_name']?.toString() ?? 'Resident',
                  residentPhone: null,
                ),
              ),
            );

            await _refreshBellOnly(); // refresh after returning
            return;
          }
        },

        onBadgeCountChanged: (count) {
          if (!mounted) return;
          setState(() => _notificationCount = count);
        },
      ),
    );
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
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          _error = userFriendlyMessageFromError(
              result.error ?? "Failed to load stats");
        });
        AppLogger.w("Failed to load admin stats: ${result.error}");
      }
    } catch (e) {
      AppLogger.e("Error loading admin stats", error: e);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = userFriendlyMessageFromError(e);
        });
      }
    }
  }

  /// Updates nameLower on public_societies so resident search by name works after a rename.
  Future<void> _syncPublicSocietySearchName() async {
    try {
      await _firestore.updatePublicSocietyNameLower(widget.societyId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Society search name synced. Residents can now find this society by name.'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e, st) {
      AppLogger.e('Sync public society nameLower failed',
          error: e, stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is Exception
              ? e.toString().replaceFirst('Exception: ', '')
              : 'Sync failed'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
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
        MaterialPageRoute(builder: (_) => const OnboardingChooseRoleScreen()),
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
        final theme = Theme.of(context);
        return PopScope(
          canPop: false,
          onPopInvoked: (didPop) async {
            if (!didPop) {
              await _onWillPop();
            }
          },
          child: Scaffold(
            backgroundColor: theme.scaffoldBackgroundColor,
            body: Stack(
              children: [
                // 1) Gradient header (top only)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 260,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.primary.withOpacity(0.85),
                        ],
                      ),
                    ),
                  ),
                ),
                // 2) White content area behind list so nothing scrolls “under” it
                Positioned(
                  left: 0,
                  right: 0,
                  top: 260,
                  bottom: 0,
                  child: Container(color: theme.scaffoldBackgroundColor),
                ),
                // 3) Scrollable content on top (society card stays above white)
                RefreshIndicator(
                  onRefresh: () async {
                    await _loadStats();
                    await _loadInsightsCounts();
                    await _loadAdminProfile();
                  },
                  color: theme.colorScheme.primary,
                  child: SafeArea(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 134),
                      children: [
                        DashboardHero(
                          userName: widget.adminName,
                          statusMessage: _notificationCount > 0
                              ? '${_notificationCount} item(s) need attention'
                              : 'Society overview',
                          mascotMood: _sosBadgeCount > 0
                              ? SentiMood.warning
                              : (_notificationCount > 0
                                  ? SentiMood.alert
                                  : SentiMood.idle),
                          avatar: CircleAvatar(
                            backgroundColor: Colors.white24,
                            backgroundImage:
                                (_photoUrl != null && _photoUrl!.isNotEmpty)
                                    ? CachedNetworkImageProvider(_photoUrl!)
                                    : null,
                            child: (_photoUrl == null || _photoUrl!.isEmpty)
                                ? const Icon(Icons.person_rounded,
                                    color: Colors.white)
                                : null,
                          ),
                          trailingActions: Stack(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.notifications_rounded,
                                    color: Colors.white),
                                onPressed: _showNotificationDrawer,
                              ),
                              Builder(
                                builder: (context) {
                                  final totalBadgeCount = _notificationCount;
                                  if (totalBadgeCount <= 0)
                                    return const SizedBox.shrink();
                                  return Positioned(
                                    right: 8,
                                    top: 8,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.error,
                                        shape: BoxShape.circle,
                                      ),
                                      constraints: const BoxConstraints(
                                          minWidth: 18, minHeight: 18),
                                      child: Text(
                                        totalBadgeCount > 9
                                            ? '9+'
                                            : totalBadgeCount.toString(),
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
                        const SizedBox(height: 24),
                        if (SocietyModules.isEnabled(
                            SocietyModuleIds.visitorManagement))
                          _buildInsightsStrip(),
                        if (SocietyModules.isEnabled(
                            SocietyModuleIds.visitorManagement))
                          const SizedBox(height: 24),
                        if (_error != null) ...[
                          Center(
                            child: SingleChildScrollView(
                              child: ErrorRetryWidget(
                                errorMessage: _error!,
                                onRetry: _loadStats,
                                retryLabel: errorActionLabelFromError(_error),
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                        ] else if (_stats != null) ...[
                          Text(
                            "Today at a glance",
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _buildStatsSection(),
                          if (SocietyModules.isEnabled(
                              SocietyModuleIds.visitorManagement)) ...[
                            const SizedBox(height: 20),
                            if (_visitorsByDayLast7 != null)
                              VisitorsChart(
                                countsByDay: _visitorsByDayLast7!,
                                barColor: Theme.of(context).colorScheme.primary,
                              )
                            else
                              const DashboardInsightsCard(),
                          ],
                          const SizedBox(height: 28),
                        ],
                        const SizedBox(height: 28),
                        Text(
                          "Your actions",
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _buildActionGrid(),
                        const SizedBox(height: 46),
                      ],
                    ),
                  ),
                ),

                if (_isLoading)
                  AppLoader.overlay(show: true, message: "Loading Stats..."),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPremiumSocietyCard() {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(24),
      shadowColor: Colors.black.withOpacity(0.15),
      color: Colors.white, // IMPORTANT: solid material
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white, // solid card
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
          ),
        ),
        child: Row(
          children: [
            // Icon container
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.business_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),

            const SizedBox(width: 15),

            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.societyId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Society Management Active",
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.6),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  /// Admin Insights Lite: consolidated count summary (single aggregate load, fade-in when ready).
  Widget _buildInsightsStrip() {
    final theme = Theme.of(context);
    final total = _countTotalToday ?? 0;
    final pending = _countPendingToday ?? 0;
    final cab = _countCabToday ?? 0;
    final delivery = _countDeliveryToday ?? 0;

    return AnimatedOpacity(
      opacity: _insightsLoading ? 0 : 1,
      duration: const Duration(milliseconds: 200),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today: $total visitors — $pending pending',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'CAB: $cab   Delivery: $delivery',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  /// Wraps the existing stats grid into a soft card module
  Widget _buildStatsSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).dividerColor),
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
        color: Theme.of(context).colorScheme.primary,
      ),
      DashboardStatCard(
        label: "Guards",
        value: (stats['total_guards'] ?? 0).toString(),
        icon: Icons.shield_rounded,
        color: Theme.of(context).colorScheme.primary,
      ),
      DashboardStatCard(
        label: "Flats",
        value: (stats['total_flats'] ?? 0).toString(),
        icon: Icons.home_rounded,
        color: Theme.of(context).colorScheme.primary,
      ),
    ];
    if (SocietyModules.isEnabled(SocietyModuleIds.visitorManagement)) {
      children.addAll([
        DashboardStatCard(
          label: "Visitors Today",
          value: (stats['visitors_today'] ?? 0).toString(),
          icon: Icons.person_add_rounded,
          color: Theme.of(context).colorScheme.primary,
        ),
        DashboardStatCard(
          label: "Pending",
          value: (stats['pending_approvals'] ?? 0).toString(),
          icon: Icons.hourglass_empty_rounded,
          color: Theme.of(context).colorScheme.primary,
        ),
        DashboardStatCard(
          label: "Approved Today",
          value: (stats['approved_today'] ?? 0).toString(),
          icon: Icons.verified_user_rounded,
          color: Theme.of(context).colorScheme.primary,
        ),
      ]);
    }
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.24,
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
          tint: Theme.of(context).colorScheme.primary,
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
          tint: Theme.of(context).colorScheme.primary,
          onTap: () => _navigateToTab(2),
        ),
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
            tint: Theme.of(context).colorScheme.error,
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
            tint: Theme.of(context).colorScheme.primary,
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
          tint: Theme.of(context).colorScheme.primary,
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
            tint: Theme.of(context).colorScheme.error,
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
    // Resident join requests (admin-only)
    if ((widget.systemRole ?? '').toLowerCase() == 'admin') {
      children.add(
        DashboardQuickAction(
          label: "Join Requests",
          icon: Icons.how_to_reg_rounded,
          tint: Theme.of(context).colorScheme.primary,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdminJoinRequestsScreen(
                  societyId: widget.societyId,
                ),
              ),
            );
          },
        ),
      );
      // Sync society name for resident search (fixes search after renaming society)
      children.add(
        DashboardQuickAction(
          label: "Sync search name",
          icon: Icons.search_rounded,
          tint: Theme.of(context).colorScheme.primary,
          onTap: _syncPublicSocietySearchName,
        ),
      );
    }

    if ((widget.systemRole ?? '').toLowerCase() == 'super_admin') {
      // Super_admin can approve join requests and sync search name for their society
      children.add(
        DashboardQuickAction(
          label: "Join Requests",
          icon: Icons.how_to_reg_rounded,
          tint: Theme.of(context).colorScheme.primary,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdminJoinRequestsScreen(
                  societyId: widget.societyId,
                ),
              ),
            );
          },
        ),
      );
      children.add(
        DashboardQuickAction(
          label: "Sync search name",
          icon: Icons.search_rounded,
          tint: Theme.of(context).colorScheme.primary,
          onTap: _syncPublicSocietySearchName,
        ),
      );
      children.add(
        DashboardQuickAction(
          label: "Manage Admins",
          icon: Icons.admin_panel_settings_rounded,
          tint: Theme.of(context).colorScheme.primary,
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
