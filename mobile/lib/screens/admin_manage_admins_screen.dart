import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../ui/app_loader.dart';
import '../services/admin_signup_service.dart';
import '../core/app_logger.dart';
import '../services/firestore_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Admin Manage Admins Screen
///
/// Allows super admins to view and manage all admins and pending admin signups
/// Theme: Purple/Admin theme
class AdminManageAdminsScreen extends StatefulWidget {
  final String adminId;
  final String societyId;
  final String? systemRole; // To check if user is super_admin

  const AdminManageAdminsScreen({
    super.key,
    required this.adminId,
    required this.societyId,
    this.systemRole,
  });

  @override
  State<AdminManageAdminsScreen> createState() =>
      _AdminManageAdminsScreenState();
}

class _AdminManageAdminsScreenState extends State<AdminManageAdminsScreen>
    with SingleTickerProviderStateMixin {
  final FirestoreService _firestore = FirestoreService();
  final AdminSignupService _signupService = AdminSignupService();

  List<dynamic> _admins = [];
  List<dynamic> _filteredAdmins = [];
  List<dynamic> _pendingSignups = [];
  bool _isLoading = false;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;
  bool _isSuperAdmin = false;

  @override
  void initState() {
    super.initState();
    _isSuperAdmin = (widget.systemRole?.toLowerCase() ?? '') == 'super_admin';
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        if (_tabController.index == 1) {
          _loadPendingSignups();
        }
      }
    });
    _loadAdmins();
    _loadPendingSignups();
    _searchController.addListener(_filterAdmins);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _filterAdmins() {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) {
      setState(() {
        _filteredAdmins = _admins;
      });
      return;
    }

    setState(() {
      _filteredAdmins = _admins.where((admin) {
        final name = (admin['name'] ?? '').toString().toLowerCase();
        final email = (admin['email'] ?? '').toString().toLowerCase();
        final phone = (admin['phone'] ?? '').toString().toLowerCase();
        final societyRole =
            (admin['societyRole'] ?? '').toString().toLowerCase();

        return name.contains(query) ||
            email.contains(query) ||
            phone.contains(query) ||
            societyRole.contains(query);
      }).toList();
    });
  }

  Future<void> _loadAdmins() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load all admins (admin and super_admin)
      final adminMembers = await _firestore.getMembers(
        societyId: widget.societyId,
        systemRole: "admin",
      );

      final superAdminMembers = await _firestore.getMembers(
        societyId: widget.societyId,
        systemRole: "super_admin",
      );

      if (!mounted) return;

      setState(() {
        _admins = [...adminMembers, ...superAdminMembers];
        _filteredAdmins = _admins;
        _isLoading = false;
      });

      AppLogger.i("Loaded ${_admins.length} admins (Firestore)");
    } catch (e, st) {
      AppLogger.e("Error loading admins (Firestore)", error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = "Failed to load admins";
      });
      _showError("Failed to load admins");
    }
  }

  Future<void> _loadPendingSignups() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final membersCol = FirebaseFirestore.instance
          .collection('societies')
          .doc(widget.societyId)
          .collection('members');

      // ✅ Keep existing admin pending logic EXACTLY the same
      final adminSnap = await membersCol
          .where('systemRole', isEqualTo: 'admin')
          .where('active', isEqualTo: false)
          .get();

      final adminList = adminSnap.docs.map((d) {
        final data = d.data();
        return {
          ...data,
          'uid': d.id,
        };
      }).toList();

      // ✅ ADD resident pending query (does not affect admin flow)
      final residentSnap = await membersCol
          .where('systemRole', isEqualTo: 'resident')
          .where('active', isEqualTo: false)
          .get();

      final residentList = residentSnap.docs.map((d) {
        final data = d.data();
        return {
          ...data,
          'uid': d.id,
        };
      }).toList();

      // ✅ Merge: admins first, then residents (no change to admin data)
      final merged = [...adminList, ...residentList];

      if (!mounted) return;
      setState(() {
        _pendingSignups = merged;
        _isLoading = false;
      });

      AppLogger.i(
        "Loaded pending signups (members)",
        data: {
          "admins": adminList.length,
          "residents": residentList.length,
          "total": merged.length,
        },
      );
    } catch (e, st) {
      AppLogger.e("Error loading pending signups (members)",
          error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = "Failed to load pending signups";
      });
    }
  }

  Future<void> _handleApproveSignup(Map<String, dynamic> signup) async {
    final uid = signup['uid'] as String?;
    if (uid == null) {
      _showError("Invalid signup request");
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Approve Admin Signup"),
        content: Text(
            "Are you sure you want to approve ${signup['name']} (${signup['email']}) as an admin?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.admin,
            ),
            child: const Text("Approve"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final result = await _signupService.approveSignup(
        societyId: widget.societyId,
        uid: uid,
        superAdminUid: widget.adminId,
      );

      if (!mounted) return;

      if (result.isSuccess) {
        _showSuccess("Admin signup approved successfully");
        _loadPendingSignups();
        _loadAdmins(); // Refresh admin list
      } else {
        _showError(result.error?.userMessage ?? "Failed to approve signup");
      }
    } catch (e, st) {
      AppLogger.e("Error approving admin signup", error: e, stackTrace: st);
      if (!mounted) return;
      _showError("An error occurred while approving signup");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleRejectSignup(Map<String, dynamic> signup) async {
    final uid = signup['uid'] as String?;
    if (uid == null) {
      _showError("Invalid signup request");
      return;
    }

    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Reject Admin Signup"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                "Are you sure you want to reject ${signup['name']} (${signup['email']})?"),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: "Reason (optional)",
                hintText: "Enter rejection reason",
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text("Reject"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final result = await _signupService.rejectSignup(
        societyId: widget.societyId,
        uid: uid,
        superAdminUid: widget.adminId,
        reason: reasonController.text.trim().isEmpty
            ? null
            : reasonController.text.trim(),
      );

      if (!mounted) return;

      if (result.isSuccess) {
        _showSuccess("Admin signup rejected");
        _loadPendingSignups();
      } else {
        _showError(result.error?.userMessage ?? "Failed to reject signup");
      }
    } catch (e, st) {
      AppLogger.e("Error rejecting admin signup", error: e, stackTrace: st);
      if (!mounted) return;
      _showError("An error occurred while rejecting signup");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Only show this screen to super admins
    if (!_isSuperAdmin) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text("Manage Admins"),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_rounded, size: 64, color: AppColors.text2),
              SizedBox(height: 16),
              Text(
                "Access Denied",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.text,
                ),
              ),
              SizedBox(height: 8),
              Text(
                "Only super admins can manage admin signups",
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.text2,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "Manage Admins",
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: AppColors.text,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.admin,
          unselectedLabelColor: AppColors.text2,
          indicatorColor: AppColors.admin,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Admins"),
                  if (_admins.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.admin.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "${_admins.length}",
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.admin,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Pending Signups"),
                  if (_pendingSignups.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "${_pendingSignups.length}",
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: [
              _buildAdminsList(),
              _buildPendingSignupsList(),
            ],
          ),
          AppLoader.overlay(
              showAfter: const Duration(milliseconds: 300),
              show: _isLoading,
              message: "Loading..."),
        ],
      ),
    );
  }

  Widget _buildAdminsList() {
    if (_error != null && _admins.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 64, color: AppColors.text2),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.text2),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadAdmins,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.admin,
              ),
              child: const Text("Retry"),
            ),
          ],
        ),
      );
    }

    if (_admins.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.admin_panel_settings_rounded,
                size: 64, color: AppColors.text2),
            SizedBox(height: 16),
            Text(
              "No admins found",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.text2,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: "Search admins...",
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _filteredAdmins.length,
            itemBuilder: (context, index) {
              final admin = _filteredAdmins[index];
              return _buildAdminCard(admin);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAdminCard(Map<String, dynamic> admin) {
    final name = admin['name'] ?? 'Unknown';
    final email = admin['email'] ?? '';
    final phone = admin['phone'] ?? '';
    final systemRole = admin['systemRole'] ?? 'admin';
    final societyRole = admin['societyRole'] ?? 'admin';
    final isSuperAdmin = systemRole.toString().toLowerCase() == 'super_admin';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSuperAdmin ? AppColors.admin : AppColors.border,
          width: isSuperAdmin ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppColors.admin.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.admin_panel_settings_rounded,
              color: AppColors.admin,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    if (isSuperAdmin)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.admin.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          "SUPER ADMIN",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: AppColors.admin,
                          ),
                        ),
                      ),
                  ],
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.text2,
                    ),
                  ),
                ],
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    phone,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.text2,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  "Role: ${societyRole.toString().toUpperCase()}",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.admin,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingSignupsList() {
    if (_error != null && _pendingSignups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 64, color: AppColors.text2),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.text2),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadPendingSignups,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.admin,
              ),
              child: const Text("Retry"),
            ),
          ],
        ),
      );
    }

    if (_pendingSignups.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pending_actions_rounded,
                size: 64, color: AppColors.text2),
            SizedBox(height: 16),
            Text(
              "No pending signups",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.text2,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPendingSignups,
      color: AppColors.admin,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _pendingSignups.length,
        itemBuilder: (context, index) {
          final signup = _pendingSignups[index];
          return _buildPendingSignupCard(signup);
        },
      ),
    );
  }

  Widget _buildPendingSignupCard(Map<String, dynamic> signup) {
    final name = signup['name'] ?? 'Unknown';
    final email = signup['email'] ?? '';
    final phone = signup['phone'] ?? '';

    final systemRole = (signup['systemRole'] ?? '')
        .toString()
        .toLowerCase(); // "admin" | "resident"
    final flatNo = (signup['flatNo'] ?? '').toString();

    // Keep existing admin label logic as-is
    final societyRole =
        (signup['societyRole'] ?? 'ADMIN').toString().toUpperCase();

    final createdAt = signup['createdAt']; // Timestamp

    // ✅ Minimal additive UI: show RESIDENT for residents, keep admin role badge unchanged
    final roleBadgeText = systemRole == 'resident'
        ? "Role: RESIDENT"
        : "Role: ${societyRole.toUpperCase()}";

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.error.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_add_rounded,
                  color: AppColors.error,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.text2,
                        ),
                      ),
                    ],
                    if (phone.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        phone,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.text2,
                        ),
                      ),
                    ],

                    // ✅ Only for residents (additive, no admin behavior change)
                    if (systemRole == 'resident' && flatNo.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        "Flat: ${flatNo.toUpperCase()}",
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.text2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              roleBadgeText,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
          ),

          if (createdAt != null) ...[
            const SizedBox(height: 8),
            Text(
              "Requested: ${_formatCreatedAt(createdAt)}",
              style: const TextStyle(fontSize: 11, color: AppColors.text2),
            ),
          ],

          const SizedBox(height: 16),

          // ✅ Buttons unchanged — existing approve/reject flows remain intact
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _handleRejectSignup(signup),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.error),
                    foregroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text("REJECT"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _handleApproveSignup(signup),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.admin,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text("APPROVE"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatCreatedAt(dynamic createdAt) {
    try {
      if (createdAt is Timestamp) {
        final date = createdAt.toDate();
        final now = DateTime.now();
        final diff = now.difference(date);

        if (diff.inDays == 0) return "Today";
        if (diff.inDays == 1) return "Yesterday";
        if (diff.inDays < 7) return "${diff.inDays} days ago";
        return "${date.day}/${date.month}/${date.year}";
      }
      return createdAt.toString();
    } catch (_) {
      return createdAt.toString();
    }
  }
}
