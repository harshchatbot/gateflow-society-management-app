import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../ui/app_colors.dart';
import '../core/app_logger.dart';
import '../services/firestore_service.dart';
import '../widgets/loading_skeletons.dart';

/// Admin Manage Residents Screen
/// 
/// Allows admins to view and manage all residents in the society
/// Theme: Sentinel (unified)
class AdminManageResidentsScreen extends StatefulWidget {
  final String adminId;
  final String societyId;
  final VoidCallback? onBackPressed;
  const AdminManageResidentsScreen({
    super.key,
    required this.adminId,
    required this.societyId,
    this.onBackPressed,
  });

  @override
  State<AdminManageResidentsScreen> createState() => _AdminManageResidentsScreenState();
}

/// Page size for paginated residents list. Load more fetches next [kResidentsPageSize] docs.
const int kResidentsPageSize = 30;

class _AdminManageResidentsScreenState extends State<AdminManageResidentsScreen> {
  final FirestoreService _firestore = FirestoreService();

  List<dynamic> _residents = [];
  List<dynamic> _filteredResidents = [];
  /// Cursor for "Load more" (null = no more or not loaded).
  DocumentSnapshot? _lastDoc;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadResidents();
    _searchController.addListener(_filterResidents);
  }

  @override
  void dispose() {
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

  /// One-time fetch: first page of residents (paginated). Resets _lastDoc on refresh.
  Future<void> _loadResidents() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _lastDoc = null;
    });

    try {
      final result = await _firestore.getMembersPage(
        societyId: widget.societyId,
        systemRole: 'resident',
        limit: kResidentsPageSize,
        startAfter: null,
      );

      if (!mounted) return;

      final list = result['list'] as List<dynamic>? ?? [];
      final lastDoc = result['lastDoc'] as DocumentSnapshot?;

      setState(() {
        _residents = list;
        _filteredResidents = _residents;
        _lastDoc = lastDoc;
        _isLoading = false;
      });

      AppLogger.i("Loaded ${_residents.length} residents (first page)");
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

  /// Load next page of residents. Keeps existing list and appends.
  void _loadMoreResidents() {
    if (_lastDoc == null || _isLoadingMore || _isLoading) return;
    _loadMoreResidentsAsync();
  }

  Future<void> _loadMoreResidentsAsync() async {
    if (!mounted || _lastDoc == null) return;
    setState(() => _isLoadingMore = true);

    try {
      final result = await _firestore.getMembersPage(
        societyId: widget.societyId,
        systemRole: 'resident',
        limit: kResidentsPageSize,
        startAfter: _lastDoc,
      );

      if (!mounted) return;

      final list = result['list'] as List<dynamic>? ?? [];
      final lastDoc = result['lastDoc'] as DocumentSnapshot?;

      setState(() {
        _residents = [..._residents, ...list];
        _filteredResidents = _residents;
        _lastDoc = list.length < kResidentsPageSize ? null : lastDoc;
        _isLoadingMore = false;
      });
      _filterResidents();
      AppLogger.i("Loaded more residents: +${list.length} (total ${_residents.length})");
    } catch (e, st) {
      AppLogger.e("Error loading more residents", error: e, stackTrace: st);
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }


  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
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
          "Manage Residents",
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
              child: Icon(Icons.refresh_rounded, color: theme.colorScheme.primary, size: 20),
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
                    onChanged: (_) => _filterResidents(),
                    decoration: InputDecoration(
                      hintText: "Search by name, flat, phone...",
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
              if (_filteredResidents.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        "${_filteredResidents.length} resident${_filteredResidents.length != 1 ? 's' : ''}",
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              // Content
              Expanded(child: _buildContent()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final theme = Theme.of(context);
    if (_isLoading && _residents.isEmpty) {
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
              onPressed: _loadResidents,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text("Retry"),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
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
                color: theme.colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.people_outline_rounded,
                size: 64,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isNotEmpty ? "No residents found" : "No residents yet",
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
                  : "Residents will appear here once added",
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
      onRefresh: _loadResidents,
      color: theme.colorScheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        itemCount: _filteredResidents.length + (_lastDoc != null ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _filteredResidents.length) {
            return _buildLoadMoreRow();
          }
          return _buildResidentCard(_filteredResidents[index] as Map<String, dynamic>);
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
                onPressed: _loadMoreResidents,
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

  Widget _buildResidentCard(Map<String, dynamic> resident) {
    final theme = Theme.of(context);
    final residentName = (resident['resident_name'] ?? resident['name'] ?? 'Unknown').toString();
    final flatNo = (resident['flat_no'] ?? 'N/A').toString();
    final phone = (resident['resident_phone'] ?? resident['phone'] ?? 'N/A').toString();
    final residentId = (resident['resident_id'] ?? 'N/A').toString();
    final role = (resident['role'] ?? 'RESIDENT').toString();
    final active = (resident['active'] ?? 'TRUE').toString().toUpperCase() == 'TRUE';
    final photoUrl = (resident['photoUrl'] ?? resident['photo_url'] ?? '').toString().trim();
    final hasPhoto = photoUrl.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active ? theme.dividerColor.withOpacity(0.5) : theme.colorScheme.error.withOpacity(0.3),
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
          onTap: () => _showResidentDetails(resident),
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
                                        child: Icon(Icons.person_rounded, color: theme.colorScheme.primary, size: 24),
                                      ),
                                      errorWidget: (_, __, ___) => Icon(
                                        Icons.person_rounded,
                                        color: theme.colorScheme.primary,
                                        size: 24,
                                      ),
                                    )
                                  : Icon(
                                      Icons.person_rounded,
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
                                  residentName,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  role,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface.withOpacity(0.7),
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
                            : theme.colorScheme.error.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        active ? "ACTIVE" : "INACTIVE",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: active ? AppColors.success : theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),

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

  void _showResidentDetails(Map<String, dynamic> resident) {
    final theme = Theme.of(context);
    final photoUrl = (resident['photoUrl'] ?? resident['photo_url'] ?? '').toString().trim();
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
                                  child: Icon(Icons.person_rounded, color: theme.colorScheme.primary, size: 28),
                                ),
                                errorWidget: (_, __, ___) => Icon(
                                  Icons.person_rounded,
                                  color: theme.colorScheme.primary,
                                  size: 28,
                                ),
                              )
                            : Icon(Icons.person_rounded, color: theme.colorScheme.primary, size: 28),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Resident Details",
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

  void _showFullScreenImage(String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            title: const Text("Photo", style: TextStyle(color: Colors.white)),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
                placeholder: (_, __) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                errorWidget: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: Colors.white, size: 64),
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
}
