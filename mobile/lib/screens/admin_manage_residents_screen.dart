import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../ui/glass_loader.dart';
import '../services/admin_service.dart';
import '../services/resident_signup_service.dart';
import '../core/app_logger.dart';
import '../core/env.dart';
import '../services/firestore_service.dart';


/// Admin Manage Residents Screen
/// 
/// Allows admins to view and manage all residents in the society
/// Theme: Purple/Admin theme
class AdminManageResidentsScreen extends StatefulWidget {
  final String adminId;
  final String societyId;

  const AdminManageResidentsScreen({
    super.key,
    required this.adminId,
    required this.societyId,
  });

  @override
  State<AdminManageResidentsScreen> createState() => _AdminManageResidentsScreenState();
}

class _AdminManageResidentsScreenState extends State<AdminManageResidentsScreen> with SingleTickerProviderStateMixin {
  final FirestoreService _firestore = FirestoreService();
  final ResidentSignupService _signupService = ResidentSignupService(); // keep (approval flow)

  List<dynamic> _residents = [];
  List<dynamic> _filteredResidents = [];
  List<dynamic> _pendingSignups = [];
  bool _isLoading = false;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;
  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _currentTabIndex = _tabController.index;
        });
        if (_tabController.index == 1) {
          _loadPendingSignups();
        }
      }
    });
    _loadResidents();
    _loadPendingSignups();
    _searchController.addListener(_filterResidents);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _filterResidents() {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) {
      setState(() {
        _filteredResidents = _residents;
      });
      return;
    }

    setState(() {
      _filteredResidents = _residents.where((resident) {
        final name = (resident['resident_name'] ?? resident['name'] ?? '').toString().toLowerCase();
        final flatNo = (resident['flat_no'] ?? '').toString().toLowerCase();
        final phone = (resident['resident_phone'] ?? resident['phone'] ?? '').toString().toLowerCase();
        final residentId = (resident['resident_id'] ?? '').toString().toLowerCase();
        
        return name.contains(query) ||
            flatNo.contains(query) ||
            phone.contains(query) ||
            residentId.contains(query);
      }).toList();
    });
  }

    Future<void> _loadResidents() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // ✅ Firestore source of truth (no backend)
      final members = await _firestore.getMembers(
        societyId: widget.societyId,
        systemRole: "resident",
      );

      if (!mounted) return;

      setState(() {
        _residents = members;
        _filteredResidents = _residents;
        _isLoading = false;
      });

      AppLogger.i("Loaded ${_residents.length} residents (Firestore)");
    } catch (e, st) {
      AppLogger.e("Error loading residents (Firestore)", error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = "Failed to load residents";
      });
      _showError("Failed to load residents");
    }
  }


  Future<void> _loadPendingSignups() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _signupService.getPendingSignups(
        societyId: widget.societyId,
      );

      if (!mounted) return;

      if (result.isSuccess && result.data != null) {
        setState(() {
          _pendingSignups = result.data!;
          _isLoading = false;
        });
        AppLogger.i("Loaded ${_pendingSignups.length} pending signups");
      } else {
        setState(() {
          _isLoading = false;
          _error = (result.error?.toString()) ?? "Failed to load pending signups";

        });
        AppLogger.w("Failed to load pending signups: ${result.error}");
      }
    } catch (e) {
      AppLogger.e("Error loading pending signups", error: e);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = "Connection error. Please try again.";
        });
      }
    }
  }

  Future<void> _handleApproveSignup(String signupId) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final result = await _signupService.approveSignup(
        societyId: widget.societyId,
        signupId: signupId,
        adminUid: widget.adminId,
      );

      if (!mounted) return;

      if (result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  "Signup approved successfully",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
        _loadPendingSignups();
        _loadResidents(); // Refresh residents list
      } else {
        setState(() => _isLoading = false);
        _showError(result.error?.userMessage ?? "Failed to approve signup");
      }
    } catch (e) {
      AppLogger.e("Error approving signup", error: e);
      if (mounted) {
        setState(() => _isLoading = false);
        _showError("An error occurred. Please try again.");
      }
    }
  }

  Future<void> _handleRejectSignup(String signupId) async {
    if (!mounted) return;
    
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Reject Signup Request"),
        content: const Text("Are you sure you want to reject this signup request?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
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
        signupId: signupId,
        adminUid: widget.adminId,
      );

      if (!mounted) return;

      if (result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.cancel, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  "Signup rejected",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
        _loadPendingSignups();
      } else {
        setState(() => _isLoading = false);
        _showError(result.error?.userMessage ?? "Failed to reject signup");
      }
    } catch (e) {
      AppLogger.e("Error rejecting signup", error: e);
      if (mounted) {
        setState(() => _isLoading = false);
        _showError("An error occurred. Please try again.");
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: const Text(
          "Manage Residents",
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
                color: AppColors.admin.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.refresh_rounded, color: AppColors.admin, size: 20),
            ),
            onPressed: _isLoading ? null : _loadResidents,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Tabs
              Container(
                color: AppColors.bg,
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: AppColors.admin,
                  labelColor: AppColors.admin,
                  unselectedLabelColor: AppColors.text2,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Residents"),
                          if (_residents.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.admin.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                "${_residents.length}",
                                style: TextStyle(
                                  color: AppColors.admin,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Pending Signups"),
                          if (_pendingSignups.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.error.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                "${_pendingSignups.length}",
                                style: TextStyle(
                                  color: AppColors.error,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Search Bar (only for residents tab)
              if (_currentTabIndex == 0)
                Container(
                  padding: const EdgeInsets.all(16),
                  color: AppColors.bg,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => _filterResidents(),
                      decoration: InputDecoration(
                        hintText: "Search by name, flat, phone...",
                        hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
                        prefixIcon: Container(
                          margin: const EdgeInsets.all(12),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.admin.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.search_rounded, color: AppColors.admin, size: 20),
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, color: AppColors.textMuted, size: 20),
                                onPressed: () {
                                  _searchController.clear();
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                ),

              // Results Count
              if (_currentTabIndex == 0 && _filteredResidents.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        "${_filteredResidents.length} resident${_filteredResidents.length != 1 ? 's' : ''}",
                        style: TextStyle(
                          color: AppColors.text2,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

              // Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildContent(),
                    _buildPendingSignupsContent(),
                  ],
                ),
              ),
            ],
          ),
          GlassLoader(show: _isLoading, message: _currentTabIndex == 0 ? "Loading residents…" : "Loading signups…"),
        ],
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
              onPressed: _loadResidents,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text("Retry"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.admin,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
    }

    if (_filteredResidents.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.admin.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.people_outline_rounded,
                size: 64,
                color: AppColors.admin,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isNotEmpty ? "No residents found" : "No residents yet",
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchController.text.isNotEmpty
                  ? "Try a different search term"
                  : "Residents will appear here once added",
              style: TextStyle(
                fontSize: 14,
                color: AppColors.text2,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadResidents,
      color: AppColors.admin,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        itemCount: _filteredResidents.length,
        itemBuilder: (context, index) {
          return _buildResidentCard(_filteredResidents[index]);
        },
      ),
    );
  }

  Widget _buildResidentCard(Map<String, dynamic> resident) {
    final residentName = (resident['resident_name'] ?? resident['name'] ?? 'Unknown').toString();
    final flatNo = (resident['flat_no'] ?? 'N/A').toString();
    final phone = (resident['resident_phone'] ?? resident['phone'] ?? 'N/A').toString();
    final residentId = (resident['resident_id'] ?? 'N/A').toString();
    final role = (resident['role'] ?? 'RESIDENT').toString();
    final active = (resident['active'] ?? 'TRUE').toString().toUpperCase() == 'TRUE';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active ? AppColors.border.withOpacity(0.5) : AppColors.error.withOpacity(0.3),
          width: active ? 1 : 1.5,
        ),
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
          onTap: () {
            // TODO: Navigate to resident details/edit screen
            _showResidentDetails(resident);
          },
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row: Name + Status
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.admin.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.person_rounded,
                              color: AppColors.admin,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  residentName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.text,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  role,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.text2,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.success.withOpacity(0.15)
                            : AppColors.error.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        active ? "ACTIVE" : "INACTIVE",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: active ? AppColors.success : AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // Details
                _buildDetailRow(Icons.home_rounded, "Flat", flatNo),
                const SizedBox(height: 8),
                _buildDetailRow(Icons.phone_rounded, "Phone", phone),
                const SizedBox(height: 8),
                _buildDetailRow(Icons.badge_rounded, "ID", residentId),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.admin.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: AppColors.admin),
        ),
        const SizedBox(width: 10),
        Text(
          "$label: ",
          style: TextStyle(
            fontSize: 13,
            color: AppColors.text2,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  void _showResidentDetails(Map<String, dynamic> resident) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: AppColors.surface,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.admin.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.person_rounded, color: AppColors.admin, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    "Resident Details",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildDetailSection("Name", resident['resident_name'] ?? resident['name'] ?? 'N/A'),
              _buildDetailSection("Flat No", resident['flat_no'] ?? 'N/A'),
              _buildDetailSection("Phone", resident['resident_phone'] ?? resident['phone'] ?? 'N/A'),
              _buildDetailSection("Resident ID", resident['resident_id'] ?? 'N/A'),
              _buildDetailSection("Role", resident['role'] ?? 'RESIDENT'),
              _buildDetailSection("Status", (resident['active'] ?? 'TRUE').toString().toUpperCase() == 'TRUE' ? 'Active' : 'Inactive'),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingSignupsContent() {
    if (_pendingSignups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  size: 64,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "No pending signups",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "All signup requests are processed",
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.text2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPendingSignups,
      color: AppColors.admin,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        itemCount: _pendingSignups.length,
        itemBuilder: (context, index) {
          return _buildSignupCard(_pendingSignups[index]);
        },
      ),
    );
  }

  Widget _buildSignupCard(Map<String, dynamic> signup) {
    final name = (signup['name'] ?? signup['residentName'] ?? 'Unknown').toString();
    final email = (signup['email'] ?? 'N/A').toString();
    final phone = (signup['phone'] ?? signup['mobile'] ?? 'N/A').toString();
    final flatNo = (signup['flatNo'] ?? signup['flat_no'] ?? 'N/A').toString();

    final signupId = (signup['signup_id'] ?? signup['uid'] ?? signup['id'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.error.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.person_add_rounded, color: AppColors.error, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.text2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    "PENDING",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDetailRow(Icons.home_rounded, "Flat", flatNo),
            const SizedBox(height: 8),
            _buildDetailRow(Icons.phone_rounded, "Phone", phone),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isLoading || signupId.isEmpty ? null : () => _handleRejectSignup(signupId),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text(
                      "Reject",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: AppColors.error, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      foregroundColor: AppColors.error,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading || signupId.isEmpty ? null : () => _handleApproveSignup(signupId),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text(
                      "Approve",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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


  Widget _buildDetailSection(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.text2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
