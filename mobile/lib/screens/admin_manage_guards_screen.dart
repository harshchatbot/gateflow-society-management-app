import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/firestore_service.dart';
import '../core/app_logger.dart';
import '../widgets/loading_skeletons.dart';

/// Admin Manage Guards Screen
///
/// Allows admins to view and manage all guards in the society
/// Theme: Sentinel (unified)
class AdminManageGuardsScreen extends StatefulWidget {
  final String adminId;
  final String societyId;
  final VoidCallback? onBackPressed;

  const AdminManageGuardsScreen({
    super.key,
    required this.adminId,
    required this.societyId,
    this.onBackPressed,
  });

  @override
  State<AdminManageGuardsScreen> createState() => _AdminManageGuardsScreenState();
}

/// Page size for paginated guards list. Load more fetches next [kGuardsPageSize] docs.
const int kGuardsPageSize = 30;

class _AdminManageGuardsScreenState extends State<AdminManageGuardsScreen> {
  final FirestoreService _firestore = FirestoreService();

  List<dynamic> _guards = [];
  List<dynamic> _filteredGuards = [];
  /// Cursor for "Load more" (null = no more or not loaded).
  DocumentSnapshot? _lastDoc;
  bool _isLoading = false;
  bool _isLoadingMore = false;
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

  /// One-time fetch: first page of guards (paginated). Resets _lastDoc on refresh.
  Future<void> _loadGuards() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _lastDoc = null;
    });

    try {
      final result = await _firestore.getMembersPage(
        societyId: widget.societyId,
        systemRole: 'guard',
        limit: kGuardsPageSize,
        startAfter: null,
      );

      if (!mounted) return;

      final list = result['list'] as List<dynamic>? ?? [];
      final lastDoc = result['lastDoc'] as DocumentSnapshot?;

      final mapped = list.map((m) {
        final data = m as Map<String, dynamic>;
        return {
          'guard_id': data['uid'] ?? data['id'],
          'guard_name': data['name'] ?? 'Guard',
          'phone': data['phone'],
          'role': (data['systemRole'] ?? 'GUARD').toString().toUpperCase(),
          'active': data['active'] ?? true,
          'society_id': widget.societyId,
          'photoUrl': data['photoUrl'],
          'photo_url': data['photo_url'],
        };
      }).toList();

      setState(() {
        _guards = mapped;
        _filteredGuards = _guards;
        _lastDoc = lastDoc;
        _isLoading = false;
      });
      AppLogger.i("Loaded ${_guards.length} guards (first page)");
    } catch (e) {
      AppLogger.e("Error loading guards", error: e);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = "Failed to load guards. Please try again.";
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              "Failed to load guards. Please try again.",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(24),
            action: SnackBarAction(
              label: "Retry",
              textColor: Theme.of(context).colorScheme.onError,
              onPressed: _loadGuards,
            ),
          ),
        );
      }
    }
  }

  void _loadMoreGuards() {
    if (_lastDoc == null || _isLoadingMore || _isLoading) return;
    _loadMoreGuardsAsync();
  }

  Future<void> _loadMoreGuardsAsync() async {
    if (!mounted || _lastDoc == null) return;
    setState(() => _isLoadingMore = true);

    try {
      final result = await _firestore.getMembersPage(
        societyId: widget.societyId,
        systemRole: 'guard',
        limit: kGuardsPageSize,
        startAfter: _lastDoc,
      );

      if (!mounted) return;

      final list = result['list'] as List<dynamic>? ?? [];
      final lastDoc = result['lastDoc'] as DocumentSnapshot?;

      final mapped = list.map((m) {
        final data = m as Map<String, dynamic>;
        return {
          'guard_id': data['uid'] ?? data['id'],
          'guard_name': data['name'] ?? 'Guard',
          'phone': data['phone'],
          'role': (data['systemRole'] ?? 'GUARD').toString().toUpperCase(),
          'active': data['active'] ?? true,
          'society_id': widget.societyId,
          'photoUrl': data['photoUrl'],
          'photo_url': data['photo_url'],
        };
      }).toList();

      setState(() {
        _guards = [..._guards, ...mapped];
        _filteredGuards = _guards;
        _lastDoc = mapped.length < kGuardsPageSize ? null : lastDoc;
        _isLoadingMore = false;
      });
      _filterGuards();
      AppLogger.i("Loaded more guards: +${mapped.length} (total ${_guards.length})");
    } catch (e) {
      AppLogger.e("Error loading more guards", error: e);
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: theme.colorScheme.onSurface),
          onPressed: () {
            if (widget.onBackPressed != null) {
              widget.onBackPressed!();
            } else if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
        title: Text(
          "Manage Guards",
          style: TextStyle(
            color: theme.colorScheme.onSurface,
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
                color: theme.colorScheme.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.pin_rounded, color: theme.colorScheme.primary, size: 20),
            ),
            onPressed: () {
              _showGuardJoinCode(context);
            },
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.refresh_rounded, color: theme.colorScheme.primary, size: 20),
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
                color: theme.scaffoldBackgroundColor,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.dividerColor),
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
                      hintStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 14),
                      prefixIcon: Container(
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.search_rounded, color: theme.colorScheme.primary, size: 20),
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear_rounded, color: theme.colorScheme.onSurface.withOpacity(0.6), size: 20),
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
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
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
        ],
      ),
    );
  }

  Widget _buildContent() {
    final theme = Theme.of(context);
    if (_isLoading && _guards.isEmpty) {
      return const HistorySkeletonList();
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
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
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
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
                color: theme.colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.shield_outlined,
                size: 64,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isNotEmpty ? "No guards found" : "No guards yet",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchController.text.isNotEmpty
                  ? "Try a different search term"
                  : "Guards will appear here once added",
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurface.withOpacity(0.7),
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
      color: theme.colorScheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        itemCount: _filteredGuards.length + (_lastDoc != null ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _filteredGuards.length) {
            return _buildLoadMoreRow();
          }
          return _buildGuardCard(_filteredGuards[index] as Map<String, dynamic>);
        },
      ),
    );
  }

  Widget _buildLoadMoreRow() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Center(
        child: _isLoadingMore
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : TextButton.icon(
                onPressed: _loadMoreGuards,
                icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                label: const Text("Load more"),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
      ),
    );
  }

  Widget _buildGuardCard(Map<String, dynamic> guard) {
    final theme = Theme.of(context);
    final guardName = (guard['guard_name'] ?? guard['name'] ?? 'Unknown').toString();
    final guardId = (guard['guard_id'] ?? guard['uid'] ?? guard['id'] ?? 'N/A').toString();
    final phone = (guard['phone'] ?? guard['guard_phone'] ?? 'N/A').toString();
    final role = (guard['role'] ?? 'GUARD').toString().toUpperCase();
    final active = (guard['active'] ?? 'TRUE').toString().toUpperCase() == 'TRUE';
    final isAdmin = role == 'ADMIN';
    final photoUrl = (guard['photoUrl'] ?? guard['photo_url'] ?? '').toString().trim();
    final hasPhoto = photoUrl.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active
              ? (isAdmin ? theme.colorScheme.primary : theme.dividerColor).withOpacity(0.5)
              : theme.colorScheme.error.withOpacity(0.3),
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
          onTap: () => _showGuardDetails(guard),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                              color: theme.colorScheme.primary.withOpacity(0.15),
                              shape: BoxShape.circle,
                              border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
                            ),
                            child: ClipOval(
                              child: hasPhoto
                                  ? CachedNetworkImage(
                                      imageUrl: photoUrl,
                                      fit: BoxFit.cover,
                                      width: 48,
                                      height: 48,
                                      placeholder: (_, __) => Center(
                                        child: Icon(
                                          isAdmin ? Icons.admin_panel_settings_rounded : Icons.shield_rounded,
                                          color: theme.colorScheme.primary,
                                          size: 24,
                                        ),
                                      ),
                                      errorWidget: (_, __, ___) => Icon(
                                        isAdmin ? Icons.admin_panel_settings_rounded : Icons.shield_rounded,
                                        color: theme.colorScheme.primary,
                                        size: 24,
                                      ),
                                    )
                                  : Icon(
                                      isAdmin ? Icons.admin_panel_settings_rounded : Icons.shield_rounded,
                                      color: theme.colorScheme.primary,
                                      size: 24,
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  guardName,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        role,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: theme.colorScheme.primary,
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
                            ? Colors.green.withOpacity(0.15)
                            : theme.colorScheme.error.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        active ? "ACTIVE" : "INACTIVE",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: active ? Colors.green.shade700 : theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),

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
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 10),
        Text(
          "$label: ",
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurface.withOpacity(0.7),
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  void _showGuardDetails(Map<String, dynamic> guard) {
    final theme = Theme.of(context);
    final photoUrl = (guard['photoUrl'] ?? guard['photo_url'] ?? '').toString().trim();
    final hasPhoto = photoUrl.isNotEmpty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: theme.colorScheme.surface,
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
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  GestureDetector(
                    onTap: hasPhoto
                        ? () {
                            Navigator.of(context).pop();
                            _showFullScreenImage(photoUrl);
                          }
                        : null,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: hasPhoto
                            ? CachedNetworkImage(
                                imageUrl: photoUrl,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Center(
                                  child: Icon(Icons.shield_rounded, color: theme.colorScheme.primary, size: 28),
                                ),
                                errorWidget: (_, __, ___) => Icon(
                                  Icons.shield_rounded,
                                  color: theme.colorScheme.primary,
                                  size: 28,
                                ),
                              )
                            : Icon(Icons.shield_rounded, color: theme.colorScheme.primary, size: 28),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Guard Details",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: theme.colorScheme.onSurface,
                      ),
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

  void _showFullScreenImage(String imageUrl) {
    final theme = Theme.of(context);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: theme.colorScheme.surface,
          appBar: AppBar(
            backgroundColor: theme.colorScheme.surface,
            iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
            title: Text("Photo", style: TextStyle(color: theme.colorScheme.onSurface)),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
                placeholder: (_, __) => Center(
                  child: CircularProgressIndicator(color: theme.colorScheme.primary),
                ),
                errorWidget: (_, __, ___) => Icon(
                  Icons.broken_image_rounded,
                  color: theme.colorScheme.onSurface,
                  size: 64,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailSection(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withOpacity(0.7),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showGuardJoinCode(BuildContext context) async {
    final theme = Theme.of(context);
    final expiry = DateTime.now().add(const Duration(hours: 24));
    final code = await _firestore.createGuardJoinCode(widget.societyId);
    if (!context.mounted) return;
    if (code == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Failed to generate code. Please try again."),
          backgroundColor: theme.colorScheme.error,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final sheetTheme = Theme.of(ctx);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: sheetTheme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  "Guard Join Code",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: sheetTheme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Ask the guard to enter this 6-digit code in the Guard app within 24 hours.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: sheetTheme.colorScheme.onSurface.withOpacity(0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
                  decoration: BoxDecoration(
                    color: sheetTheme.colorScheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: sheetTheme.colorScheme.primary.withOpacity(0.3)),
                  ),
                  child: Text(
                    code,
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 12,
                      color: sheetTheme.colorScheme.primary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "Valid until: ${expiry.toLocal()}",
                  style: TextStyle(
                    color: sheetTheme.colorScheme.onSurface.withOpacity(0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: sheetTheme.dividerColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          "Close",
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: sheetTheme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: code));
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text("Code copied to clipboard"),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: sheetTheme.colorScheme.primary,
                          foregroundColor: sheetTheme.colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text(
                          "Copy",
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
