import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../ui/app_colors.dart';
import '../ui/app_loader.dart';
import '../services/firestore_service.dart';
import '../core/app_logger.dart';
import '../core/society_modules.dart';
import '../widgets/module_disabled_placeholder.dart';
import 'guard_report_violation_screen.dart';

/// Guard Violations List Screen
///
/// Shows only violations reported by this guard. Violations are private.
class GuardViolationsListScreen extends StatefulWidget {
  final String guardId;
  final String societyId;
  final VoidCallback? onBackPressed;

  const GuardViolationsListScreen({
    super.key,
    required this.guardId,
    required this.societyId,
    this.onBackPressed,
  });

  @override
  State<GuardViolationsListScreen> createState() =>
      _GuardViolationsListScreenState();
}

class _GuardViolationsListScreenState extends State<GuardViolationsListScreen> {
  final FirestoreService _firestore = FirestoreService();

  List<Map<String, dynamic>> _violations = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadViolations();
  }

  Future<void> _loadViolations() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    // Use current auth uid so Firestore rules can allow the query (guard may only read own reports)
    final guardUid = FirebaseAuth.instance.currentUser?.uid ?? widget.guardId;

    try {
      final list = await _firestore.getViolationsByGuard(
        societyId: widget.societyId,
        guardUid: guardUid,
      );

      if (!mounted) return;
      setState(() {
        _violations = list;
        _isLoading = false;
      });
      AppLogger.i('Loaded ${list.length} violations for guard');
    } catch (e) {
      AppLogger.e('Error loading violations', error: e);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load. Please try again.';
        });
      }
    }
  }

  String _violationTypeLabel(String type) {
    switch (type.toUpperCase()) {
      case 'PARKING':
        return 'Parking';
      case 'FIRE_LANE':
        return 'Fire lane';
      default:
        return 'Other';
    }
  }

  IconData _violationTypeIcon(String type) {
    switch (type.toUpperCase()) {
      case 'PARKING':
        return Icons.directions_car_rounded;
      case 'FIRE_LANE':
        return Icons.local_fire_department_rounded;
      default:
        return Icons.warning_rounded;
    }
  }

  void _openReportScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GuardReportViolationScreen(
          guardId: widget.guardId,
          societyId: widget.societyId,
          onBackPressed: () => Navigator.pop(context),
        ),
      ),
    );
    _loadViolations();
  }

  @override
  Widget build(BuildContext context) {
    if (!SocietyModules.isEnabled(SocietyModuleIds.violations)) {
      return ModuleDisabledPlaceholder(onBack: widget.onBackPressed);
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.text),
          onPressed: () {
            if (widget.onBackPressed != null) {
              widget.onBackPressed!();
            } else if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
        title: const Text(
          'My Violation Reports',
          style: TextStyle(
              color: AppColors.text, fontWeight: FontWeight.w900, fontSize: 20),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.refresh_rounded,
                  color: AppColors.primary, size: 20),
            ),
            onPressed: _isLoading ? null : _loadViolations,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock_rounded,
                        color: AppColors.primary, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Violations are private. You see only your own reports. No names are publicised.',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.text2,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildContent()),
            ],
          ),
          AppLoader.overlay(
              showAfter: const Duration(milliseconds: 300),
              show: _isLoading,
              message: 'Loading…'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openReportScreen,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Report violation'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  Widget _buildContent() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(_error!,
                style: const TextStyle(color: AppColors.text2, fontSize: 16),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadViolations,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
    }

    if (_violations.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.directions_car_outlined,
                size: 64, color: AppColors.textMuted),
            const SizedBox(height: 16),
            const Text(
              'No violation reports yet',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap "Report violation" to add one.',
              style: TextStyle(fontSize: 14, color: AppColors.text2),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _openReportScreen,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Report violation'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadViolations,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: _violations.length,
        itemBuilder: (context, index) {
          final v = _violations[index];
          return _buildViolationCard(v);
        },
      ),
    );
  }

  Widget _buildViolationCard(Map<String, dynamic> v) {
    final flatNo = v['flat_no']?.toString() ?? '–';
    final type = v['violation_type']?.toString() ?? 'OTHER';
    final status = (v['status'] ?? 'OPEN').toString().toUpperCase();
    final createdAt = v['created_at']?.toString();
    final note = v['note']?.toString();
    final photoUrl = v['photo_url']?.toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_violationTypeIcon(type),
                  color: AppColors.warning, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Flat $flatNo',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.text)),
                  Text(_violationTypeLabel(type),
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.text2)),
                  if (createdAt != null && createdAt.isNotEmpty)
                    Text(
                        createdAt.length >= 10
                            ? createdAt.substring(0, 10)
                            : createdAt,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textMuted)),
                  if (note != null && note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(note,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.text2)),
                    ),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: status == 'RESOLVED'
                          ? AppColors.success.withValues(alpha: 0.15)
                          : AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: status == 'RESOLVED'
                              ? AppColors.success
                              : AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),
            if (photoUrl != null && photoUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: photoUrl,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                      width: 48, height: 48, color: Colors.grey.shade300),
                  errorWidget: (context, url, error) =>
                      const SizedBox(width: 48, height: 48),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
