import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../ui/glass_loader.dart';
import '../services/admin_service.dart';
import '../core/app_logger.dart';
import '../core/env.dart';

/// Admin Manage Guards Screen
/// 
/// Allows admins to view and manage all guards in the society
/// Theme: Purple/Admin theme
class AdminManageGuardsScreen extends StatefulWidget {
  final String adminId;
  final String societyId;

  const AdminManageGuardsScreen({
    super.key,
    required this.adminId,
    required this.societyId,
  });

  @override
  State<AdminManageGuardsScreen> createState() => _AdminManageGuardsScreenState();
}

class _AdminManageGuardsScreenState extends State<AdminManageGuardsScreen> {
  late final AdminService _service = AdminService(
    baseUrl: Env.apiBaseUrl.isNotEmpty ? Env.apiBaseUrl : "http://192.168.29.195:8000",
  );

  List<dynamic> _guards = [];
  List<dynamic> _filteredGuards = [];
  bool _isLoading = false;
  String? _error;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadGuards();
    _searchController.addListener(_filterGuards);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterGuards() {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) {
      setState(() {
        _filteredGuards = _guards;
      });
      return;
    }

    setState(() {
      _filteredGuards = _guards.where((guard) {
        final name = (guard['guard_name'] ?? guard['name'] ?? '').toString().toLowerCase();
        final guardId = (guard['guard_id'] ?? '').toString().toLowerCase();
        final phone = (guard['phone'] ?? guard['guard_phone'] ?? '').toString().toLowerCase();
        final role = (guard['role'] ?? '').toString().toLowerCase();
        
        return name.contains(query) ||
            guardId.contains(query) ||
            phone.contains(query) ||
            role.contains(query);
      }).toList();
    });
  }

  Future<void> _loadGuards() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _service.getGuards(societyId: widget.societyId);

      if (!mounted) return;

      if (result.isSuccess && result.data != null) {
        setState(() {
          _guards = result.data!;
          _filteredGuards = _guards;
          _isLoading = false;
        });
        AppLogger.i("Loaded ${_guards.length} guards");
      } else {
        setState(() {
          _isLoading = false;
          _error = result.error ?? "Failed to load guards";
        });
        AppLogger.w("Failed to load guards: ${result.error}");
      }
    } catch (e) {
      AppLogger.e("Error loading guards", error: e);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = "Connection error. Please try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: const Text(
          "Manage Guards",
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
            onPressed: _isLoading ? null : _loadGuards,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Search Bar
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
                    onChanged: (_) => _filterGuards(),
                    decoration: InputDecoration(
                      hintText: "Search by name, ID, phone, role...",
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
              if (_filteredGuards.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        "${_filteredGuards.length} guard${_filteredGuards.length != 1 ? 's' : ''}",
                        style: TextStyle(
                          color: AppColors.text2,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

              // List
              Expanded(
                child: _buildContent(),
              ),
            ],
          ),
          GlassLoader(show: _isLoading, message: "Loading guards…"),
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
              onPressed: _loadGuards,
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

    if (_filteredGuards.isEmpty && !_isLoading) {
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
                Icons.shield_outlined,
                size: 64,
                color: AppColors.admin,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isNotEmpty ? "No guards found" : "No guards yet",
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
                  : "Guards will appear here once added",
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
      onRefresh: _loadGuards,
      color: AppColors.admin,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        itemCount: _filteredGuards.length,
        itemBuilder: (context, index) {
          return _buildGuardCard(_filteredGuards[index]);
        },
      ),
    );
  }

  Widget _buildGuardCard(Map<String, dynamic> guard) {
    final guardName = (guard['guard_name'] ?? guard['name'] ?? 'Unknown').toString();
    final guardId = (guard['guard_id'] ?? 'N/A').toString();
    final phone = (guard['phone'] ?? guard['guard_phone'] ?? 'N/A').toString();
    final role = (guard['role'] ?? 'GUARD').toString().toUpperCase();
    final active = (guard['active'] ?? 'TRUE').toString().toUpperCase() == 'TRUE';
    final isAdmin = role == 'ADMIN';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active
              ? (isAdmin ? AppColors.admin : AppColors.border).withOpacity(0.5)
              : AppColors.error.withOpacity(0.3),
          width: active ? (isAdmin ? 2 : 1) : 1.5,
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
            _showGuardDetails(guard);
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
                              color: isAdmin
                                  ? AppColors.admin.withOpacity(0.15)
                                  : AppColors.primary.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isAdmin ? Icons.admin_panel_settings_rounded : Icons.shield_rounded,
                              color: isAdmin ? AppColors.admin : AppColors.primary,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  guardName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.text,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isAdmin
                                            ? AppColors.admin.withOpacity(0.15)
                                            : AppColors.primary.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        role,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: isAdmin ? AppColors.admin : AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ],
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
                _buildDetailRow(Icons.badge_rounded, "Guard ID", guardId),
                if (phone != 'N/A') ...[
                  const SizedBox(height: 8),
                  _buildDetailRow(Icons.phone_rounded, "Phone", phone),
                ],
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

  void _showGuardDetails(Map<String, dynamic> guard) {
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
                    child: const Icon(Icons.shield_rounded, color: AppColors.admin, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    "Guard Details",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildDetailSection("Name", guard['guard_name'] ?? guard['name'] ?? 'N/A'),
              _buildDetailSection("Guard ID", guard['guard_id'] ?? 'N/A'),
              if (guard['phone'] != null || guard['guard_phone'] != null)
                _buildDetailSection("Phone", guard['phone'] ?? guard['guard_phone'] ?? 'N/A'),
              _buildDetailSection("Role", (guard['role'] ?? 'GUARD').toString().toUpperCase()),
              _buildDetailSection("Status", (guard['active'] ?? 'TRUE').toString().toUpperCase() == 'TRUE' ? 'Active' : 'Inactive'),
              if (guard['society_id'] != null)
                _buildDetailSection("Society ID", guard['society_id'] ?? 'N/A'),
              const SizedBox(height: 20),
            ],
          ),
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
