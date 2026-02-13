import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:showcaseview/showcaseview.dart';
import '../ui/app_colors.dart';
import '../services/firestore_service.dart';
import '../services/offline_queue_service.dart';
import '../services/notice_service.dart';
import '../core/storage.dart';
import '../core/app_logger.dart';
import '../core/tour_storage.dart';
import '../core/society_modules.dart';
import '../core/env.dart';
import '../models/visitor.dart';
import 'notice_board_screen.dart';
import 'onboarding_choose_role_screen.dart';
import 'visitor_details_screen.dart';
import '../services/notification_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'sos_alerts_screen.dart';
import 'sos_detail_screen.dart';
import 'guard_residents_directory_screen.dart';
import 'guard_violations_list_screen.dart';
import '../widgets/guard_notification_drawer.dart';
import '../widgets/visitors_chart.dart';
import '../widgets/dashboard_insights_card.dart';
import '../widgets/dashboard_hero.dart';
import '../widgets/dashboard_stat_card.dart';
import '../widgets/dashboard_quick_action.dart';
import '../widgets/sentinel_illustration.dart';

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

  final GlobalKey<State<StatefulWidget>> _keyNewEntry =
      GlobalKey<State<StatefulWidget>>();
  final GlobalKey<State<StatefulWidget>> _keyVisitors =
      GlobalKey<State<StatefulWidget>>();
  final GlobalKey<State<StatefulWidget>> _keySosAlerts =
      GlobalKey<State<StatefulWidget>>();

  String _dynamicName = "";
  String? _photoUrl;
  int todayCount = 0;
  int pendingCount = 0;
  int approvedCount = 0;
  List<Visitor> _recentVisitors = [];
  int _sosBadgeCount = 0;
  int _notificationCount = 0;

  /// Visitor counts per day for last 7 days (day-6 .. today). Used for dashboard chart.
  List<int>? _visitorsByDayLast7;
  late final NoticeService _noticeService =
      NoticeService(baseUrl: Env.apiBaseUrl);
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sosRealtimeSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _visitorRealtimeSub;
  bool _sosRealtimePrimed = false;
  bool _visitorRealtimePrimed = false;
  final Set<String> _seenOpenSosIds = <String>{};
  final Map<String, String> _seenVisitorStatuses = <String, String>{};

  @override
  void initState() {
    super.initState();
    _dynamicName = widget.guardName;
    OfflineQueueService.instance.ensureInit().then((_) {
      if (!mounted) return;
      OfflineQueueService.instance.onQueueChanged = () => setState(() {});
    });
    _syncDashboard();
    _loadGuardNotificationCount();
    _setupRealtimeSignals();
    _setupNotificationListener();
    _maybeAutoRunTour();
  }

  @override
  void dispose() {
    final notificationService = NotificationService();
    notificationService.unregisterOnNotificationReceived('guard_dashboard');
    notificationService.unregisterOnNotificationTap('guard_dashboard');
    _sosRealtimeSub?.cancel();
    _visitorRealtimeSub?.cancel();
    OfflineQueueService.instance.onQueueChanged = null;
    super.dispose();
  }

  void _setupRealtimeSignals() {
    if (SocietyModules.isEnabled(SocietyModuleIds.sos)) {
      _sosRealtimeSub = _db
          .collection('societies')
          .doc(widget.societyId)
          .collection('sos_requests')
          .where('status', isEqualTo: 'OPEN')
          .snapshots()
          .listen((snapshot) {
        if (!mounted) return;
        final currentIds = snapshot.docs.map((d) => d.id).toSet();
        if (_sosRealtimePrimed) {
          final newIds = currentIds.difference(_seenOpenSosIds);
          if (newIds.isNotEmpty) {
            final first = snapshot.docs.firstWhere(
              (d) => newIds.contains(d.id),
              orElse: () => snapshot.docs.first,
            );
            final data = first.data();
            final flatNo = (data['flatNo'] ?? data['flat_no'] ?? '').toString();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'SOS alert from ${flatNo.isEmpty ? "a unit" : flatNo}'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
        _seenOpenSosIds
          ..clear()
          ..addAll(currentIds);
        _sosRealtimePrimed = true;
        _loadGuardNotificationCount();
      }, onError: (e, st) {
        AppLogger.w("SOS realtime listener failed", error: e.toString());
      });
    }

    _visitorRealtimeSub = _db
        .collection('societies')
        .doc(widget.societyId)
        .collection('visitors')
        .where('guard_uid', isEqualTo: widget.guardId)
        .limit(80)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      final Map<String, String> next = <String, String>{};
      for (final d in snapshot.docs) {
        final status = (d.data()['status'] ?? '').toString().toUpperCase();
        next[d.id] = status;
        final prev = _seenVisitorStatuses[d.id];
        final changed = prev != null && prev != status;
        final isFinal = status == 'APPROVED' || status == 'REJECTED';
        if (_visitorRealtimePrimed && changed && isFinal) {
          final flatNo = (d.data()['flat_no'] ?? '').toString();
          final label = status == 'APPROVED' ? 'approved' : 'rejected';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Visitor for ${flatNo.isEmpty ? "unit" : flatNo} was $label'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          _syncDashboard();
        }
      }
      _seenVisitorStatuses
        ..clear()
        ..addAll(next);
      _visitorRealtimePrimed = true;
    }, onError: (e, st) {
      AppLogger.w("Visitor realtime listener failed", error: e.toString());
    });
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
      if (SocietyModules.isEnabled(SocietyModuleIds.sos)) {
        keys.add(_keySosAlerts);
      }
      if (keys.isEmpty) return;
      ShowCaseWidget.of(_showCaseContext!).startShowCase(keys);
    } catch (_) {
      if (mounted) TourStorage.setHasSeenTourGuard();
    }
  }

  void _setupNotificationListener() {
    final notificationService = NotificationService();
    notificationService.registerOnNotificationReceived('guard_dashboard',
        (data) {
      final type = (data['type'] ?? '').toString();
      if (type == 'sos' && SocietyModules.isEnabled(SocietyModuleIds.sos)) {
        _loadGuardNotificationCount();
      } else if (type == 'visitor_status') {
        _syncDashboard();
        if (mounted) {
          final status = (data['status'] ?? '').toString().toUpperCase();
          final flatNo = (data['flat_no'] ?? '').toString();
          final residentName = (data['resident_name'] ?? 'Resident').toString();
          final action = status == 'APPROVED' ? 'approved' : 'rejected';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("$residentName $action visitor for $flatNo"),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else if (type == '__refresh__') {
        _loadGuardNotificationCount();
      } else if (type == 'notice' &&
          SocietyModules.isEnabled(SocietyModuleIds.notices)) {
        _loadGuardNotificationCount();
      }
    });
    notificationService.registerOnNotificationTap('guard_dashboard', (data) {
      final type = (data['type'] ?? '').toString();
      if (type == 'sos' && SocietyModules.isEnabled(SocietyModuleIds.sos)) {
        final societyId = (data['society_id'] ?? widget.societyId).toString();
        final flatNo = (data['flat_no'] ?? '').toString();
        final residentName = (data['resident_name'] ?? 'Resident').toString();
        final phone = (data['resident_phone'] ?? '').toString();
        final sosId = (data['sos_id'] ?? '').toString();

        if (!mounted || sosId.isEmpty) return;

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
        ).then((_) => _loadGuardNotificationCount());
      } else if (type == 'notice' &&
          SocietyModules.isEnabled(SocietyModuleIds.notices)) {
        _loadGuardNotificationCount();
      } else if (type == 'visitor_status') {
        _syncDashboard();
      } else if (type == '__refresh__') {
        _loadGuardNotificationCount();
      }
    });
  }

  Future<void> _loadGuardNotificationCount() async {
    int openSos = 0;
    int recentNotices = 0;

    try {
      if (SocietyModules.isEnabled(SocietyModuleIds.sos)) {
        final sosList =
            await _firestore.getSosRequests(societyId: widget.societyId);
        openSos = sosList.where((s) {
          final status = (s['status'] ?? 'OPEN').toString().toUpperCase();
          return status == 'OPEN';
        }).length;
      }

      if (SocietyModules.isEnabled(SocietyModuleIds.notices)) {
        final noticesResult = await _noticeService.getNotices(
          societyId: widget.societyId,
          activeOnly: true,
        );
        if (noticesResult.isSuccess && noticesResult.data != null) {
          final now = DateTime.now();
          recentNotices = noticesResult.data!.where((n) {
            try {
              final createdAt = n['created_at']?.toString() ?? '';
              if (createdAt.isEmpty) return false;
              final created =
                  DateTime.parse(createdAt.replaceAll("Z", "+00:00"));
              return now.difference(created).inHours <= 24;
            } catch (_) {
              return false;
            }
          }).length;
        }
      }

      if (!mounted) return;
      setState(() {
        _notificationCount = openSos + recentNotices;
        _sosBadgeCount = openSos > 0 ? 1 : 0;
      });
    } catch (e, st) {
      AppLogger.e("Guard notification count load failed",
          error: e, stackTrace: st);
    }
  }

  void _showNotificationDrawer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GuardNotificationDrawer(
        societyId: widget.societyId,
        onBadgeCountChanged: (badgeCount) {
          if (!mounted) return;
          setState(() => _notificationCount = badgeCount);
        },
      ),
    ).then((_) => _loadGuardNotificationCount());
  }

  Future<void> _syncDashboard() async {
    if (!mounted) return;

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

        return createdDate
                .isAfter(startOfDay.subtract(const Duration(seconds: 1))) &&
            createdDate.isBefore(endOfDay);
      }).map((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        // Use actual status; do not default to PENDING so badge count is accurate
        final status = (data?['status']?.toString() ?? '').toUpperCase();
        return {'status': status};
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

        recentVisitors = recentQuerySnapshot.docs
            .map((doc) {
              final data = doc.data() as Map<String, dynamic>?;
              if (data == null) return null;
              return _mapToVisitor(data, doc.id);
            })
            .whereType<Visitor>()
            .toList();
      } catch (e) {
        AppLogger.w("getRecentVisitors error", error: e.toString());
        // Fallback: try without orderBy if composite index is missing
        try {
          final recentQuerySnapshot = await visitorsRef
              .where('guard_uid', isEqualTo: widget.guardId)
              .limit(20)
              .get()
              .timeout(const Duration(seconds: 10));

          final allVisitors = recentQuerySnapshot.docs
              .map((doc) {
                final data = doc.data() as Map<String, dynamic>?;
                if (data == null) return null;
                return _mapToVisitor(data, doc.id);
              })
              .whereType<Visitor>()
              .toList();

          // Sort by createdAt descending in memory
          allVisitors.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          recentVisitors = allVisitors.take(5).toList();
        } catch (e2) {
          AppLogger.w("getRecentVisitors fallback error", error: e2.toString());
        }
      }

      // Load last-7-days counts for chart (no extra query if we already have data; lightweight)
      List<int> visitorsByDayLast7 = List.filled(7, 0);
      try {
        visitorsByDayLast7 = await _firestore.getVisitorCountsByDayLast7Days(
          societyId: widget.societyId,
          guardId: widget.guardId,
        );
      } catch (e) {
        AppLogger.w("getVisitorCountsByDayLast7Days failed",
            error: e.toString());
      }

      if (mounted) {
        setState(() {
          todayCount = todayVisitors.length;
          pendingCount = todayVisitors
              .where((v) => (v['status'] as String).toUpperCase() == 'PENDING')
              .length;
          approvedCount = todayVisitors
              .where((v) => (v['status'] as String).toUpperCase() == 'APPROVED')
              .length;
          _recentVisitors = recentVisitors;
          _visitorsByDayLast7 = visitorsByDayLast7;
        });
      }

      AppLogger.i("Guard dashboard synced", data: {
        "todayCount": todayCount,
        "pendingCount": pendingCount,
        "approvedCount": approvedCount,
      });
    } catch (e, stackTrace) {
      AppLogger.e("Dashboard Sync Error", error: e, stackTrace: stackTrace);
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
      visitorType:
          (data['visitor_type'] ?? data['visitorType'] ?? 'GUEST').toString(),
      visitorPhone:
          (data['visitor_phone'] ?? data['visitorPhone'] ?? '').toString(),
      status: (data['status'] ?? 'PENDING').toString(),
      createdAt: createdAt,
      approvedAt: approvedAt,
      approvedBy:
          data['approved_by']?.toString() ?? data['approvedBy']?.toString(),
      guardId: data['guard_uid']?.toString() ??
          data['guard_id']?.toString() ??
          widget.guardId,
      photoPath: data['photo_path']?.toString(),
      photoUrl: data['photo_url']?.toString() ?? data['photoUrl']?.toString(),
      note: data['note']?.toString(),
      residentPhone: data['resident_phone']?.toString(),
      cab: data['cab'] is Map
          ? Map<String, dynamic>.from(data['cab'] as Map)
          : null,
      delivery: data['delivery'] is Map
          ? Map<String, dynamic>.from(data['delivery'] as Map)
          : null,
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

  String? _getVisitorProviderLabel(Visitor visitor) {
    final t = visitor.visitorType.toUpperCase();
    if (t == 'CAB' && visitor.cab != null && visitor.cab!['provider'] != null) {
      final p = visitor.cab!['provider'].toString().trim();
      return p.isEmpty ? null : p;
    }
    if (t == 'DELIVERY' &&
        visitor.delivery != null &&
        visitor.delivery!['provider'] != null) {
      final p = visitor.delivery!['provider'].toString().trim();
      return p.isEmpty ? null : p;
    }
    return null;
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
    if (!mounted) return;
    if (shouldExit == true) {
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
        TourStorage.setHasSeenTourGuard();
      },
      builder: (context) {
        _showCaseContext = context;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (!didPop) {
              await _onWillPop();
            }
          },
          child: Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            body: Stack(
              children: [
                // 1) Gradient header (top only)
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
                          Theme.of(context).colorScheme.primary,
                          Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.85),
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
                  child: Container(
                      color: Theme.of(context).scaffoldBackgroundColor),
                ),
                // 3) Scrollable content on top (society card stays above white)
                RefreshIndicator(
                  onRefresh: _syncDashboard,
                  color: Theme.of(context).colorScheme.primary,
                  child: SafeArea(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
                      children: [
                        if (!OfflineQueueService.instance.isOnline) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                vertical: 10, horizontal: 14),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Theme.of(context).dividerColor),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.cloud_off_rounded,
                                    size: 20,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    OfflineQueueService.instance.pendingCount >
                                            0
                                        ? 'Offline – ${OfflineQueueService.instance.pendingCount} change(s) will sync when online'
                                        : 'Offline mode – changes will sync when online',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (OfflineQueueService.instance.pendingCount > 0 &&
                            OfflineQueueService.instance.isOnline) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 6, horizontal: 12),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${OfflineQueueService.instance.pendingCount} pending sync',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
                                  ),
                            ),
                          ),
                        ],
                        DashboardHero(
                          userName: _dynamicName,
                          statusMessage: (pendingCount + _sosBadgeCount) > 0
                              ? '${pendingCount + _sosBadgeCount} pending · Check approvals'
                              : 'All gates are secure',
                          mascotMood: _sosBadgeCount > 0
                              ? SentiMood.warning
                              : ((pendingCount + _sosBadgeCount) > 0
                                  ? SentiMood.alert
                                  : (todayCount > 0
                                      ? SentiMood.happy
                                      : SentiMood.idle)),
                          avatar: GestureDetector(
                            onTap: (_photoUrl != null && _photoUrl!.isNotEmpty)
                                ? () => _openGuardPhotoPreview(_photoUrl!)
                                : null,
                            child: CircleAvatar(
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
                          ),
                          trailingActions: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Stack(
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                        Icons.notifications_rounded,
                                        color: Colors.white),
                                    onPressed: _showNotificationDrawer,
                                  ),
                                  if (_notificationCount > 0)
                                    Positioned(
                                      right: 8,
                                      top: 8,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                          shape: BoxShape.circle,
                                        ),
                                        constraints: const BoxConstraints(
                                            minWidth: 18, minHeight: 18),
                                        child: Text(
                                          _notificationCount > 9
                                              ? '9+'
                                              : _notificationCount.toString(),
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
                                icon: const Icon(Icons.tune_rounded,
                                    color: Colors.white),
                                onPressed: () => _showSettingsSheet(context),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildPremiumSocietyCard(),
                        const SizedBox(height: 24),
                        if (SocietyModules.isEnabled(
                            SocietyModuleIds.visitorManagement)) ...[
                          Text(
                            "Today at a glance",
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _buildStatsRow(),
                          const SizedBox(height: 20),
                          if (_visitorsByDayLast7 != null)
                            VisitorsChart(
                              countsByDay: _visitorsByDayLast7!,
                              barColor: Theme.of(context).colorScheme.primary,
                            )
                          else
                            const DashboardInsightsCard(),
                          const SizedBox(height: 28),
                        ],
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
                        if (SocietyModules.isEnabled(
                            SocietyModuleIds.visitorManagement)) ...[
                          const SizedBox(height: 28),
                          _buildRecentActivitySection(),
                        ],
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
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
      shadowColor: Colors.black.withValues(alpha: 0.15),
      color: Colors.white, // IMPORTANT: solid material
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white, // solid card
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            // Icon container
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.12),
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
                          .withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            Icon(
              Icons.arrow_forward_ios_rounded,
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  /// Stats row wrapped in a soft card module
  Widget _buildStatsRow() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: DashboardStatCard(
              label: "Today",
              value: todayCount.toString(),
              icon: Icons.today_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DashboardStatCard(
              label: "Pending",
              value: pendingCount.toString(),
              icon: Icons.hourglass_empty_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DashboardStatCard(
              label: "Approved",
              value: approvedCount.toString(),
              icon: Icons.verified_user_rounded,
              color: Theme.of(context).colorScheme.primary,
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
          description:
              "Register a new visitor. Resident gets a request to approve.",
          child: DashboardQuickAction(
              label: "New Entry",
              icon: Icons.person_add_rounded,
              tint: Theme.of(context).colorScheme.primary,
              onTap: widget.onTapNewEntry),
        ),
        Showcase(
          key: _keyVisitors,
          title: "Visitor List / History",
          description: "View today's visitors and full history.",
          child: DashboardQuickAction(
              label: "Visitors",
              icon: Icons.groups_rounded,
              tint: Theme.of(context).colorScheme.primary,
              onTap: widget.onTapVisitors),
        ),
      ]);
    }
    if (SocietyModules.isEnabled(SocietyModuleIds.notices)) {
      children.add(
        DashboardQuickAction(
          label: "Notices",
          icon: Icons.notifications_rounded,
          tint: Theme.of(context).colorScheme.primary,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => NoticeBoardScreen(
                  societyId: widget.societyId,
                  themeColor: Theme.of(context).colorScheme.primary,
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
          child: DashboardQuickAction(
            label: "SOS Alerts",
            icon: Icons.sos_rounded,
            tint: Theme.of(context).colorScheme.error,
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
      DashboardQuickAction(
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
        DashboardQuickAction(
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
            Text("Recent Activity",
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                    fontSize: 16)),
            TextButton(
                onPressed: widget.onTapVisitors, child: const Text("View All")),
          ],
        ),
        const SizedBox(height: 10),
        if (_recentVisitors.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.06)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SentinelIllustration(kind: 'empty_visitors', height: 100),
                const SizedBox(height: 16),
                Text(
                  "No visitors yet today",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Add an entry when someone arrives",
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          )
        else
          ..._recentVisitors.map((visitor) {
            final displayFlat =
                visitor.flatNo.isNotEmpty ? visitor.flatNo : visitor.flatId;
            final statusColor = _getStatusColor(visitor.status);
            final provider = _getVisitorProviderLabel(visitor);
            final subtitleParts = [
              visitor.visitorPhone.isNotEmpty
                  ? visitor.visitorPhone
                  : 'No phone',
              _formatTime(visitor.createdAt),
              if (provider != null) provider,
            ];
            final subtitle = subtitleParts.join(" • ");
            final hasResidentPhone = visitor.residentPhone != null &&
                visitor.residentPhone!.trim().isNotEmpty;
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
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getVisitorTypeIcon(visitor.visitorType),
                      color: Theme.of(context).colorScheme.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "${visitor.visitorType} • Flat $displayFlat",
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                _getVisitorTypeIcon(visitor.visitorType),
                                size: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.6),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.6),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          if (hasResidentPhone) ...[
                            const SizedBox(height: 4),
                            GestureDetector(
                              onTap: () async {
                                final phone = visitor.residentPhone!;
                                final cleaned =
                                    phone.replaceAll(RegExp(r'[^\d+]'), '');
                                if (cleaned.isEmpty) return;
                                final uri = Uri.parse('tel:$cleaned');
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri,
                                      mode: LaunchMode.externalApplication);
                                }
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.call_rounded,
                                      size: 14, color: AppColors.success),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: statusColor.withValues(alpha: 0.3)),
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
          }),
      ],
    );
  }

  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Gate Settings",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 20),
            ListTile(
              leading: Icon(Icons.notifications_active,
                  color: Theme.of(context).colorScheme.primary),
              title: const Text("Alert Sounds"),
              trailing: Switch.adaptive(value: true, onChanged: (v) {}),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openGuardPhotoPreview(String imageUrl) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
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
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white,
                          size: 42,
                        ),
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
