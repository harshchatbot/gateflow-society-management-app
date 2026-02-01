import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../ui/app_colors.dart';
import '../ui/app_loader.dart';
import '../services/firestore_service.dart';
import '../core/app_logger.dart';
import '../core/society_modules.dart';
import '../widgets/module_disabled_placeholder.dart';

/// Admin Manage Violations Screen
///
/// Full control: list all violations, update status, publish anonymous monthly summary.
/// Violations are private – no names in summaries.
class AdminManageViolationsScreen extends StatefulWidget {
  final String adminId;
  final String adminName;
  final String societyId;
  final VoidCallback? onBackPressed;

  const AdminManageViolationsScreen({
    super.key,
    required this.adminId,
    required this.adminName,
    required this.societyId,
    this.onBackPressed,
  });

  @override
  State<AdminManageViolationsScreen> createState() => _AdminManageViolationsScreenState();
}

class _AdminManageViolationsScreenState extends State<AdminManageViolationsScreen> {
  final FirestoreService _firestore = FirestoreService();

  List<Map<String, dynamic>> _violations = [];
  List<Map<String, dynamic>> _filteredViolations = [];
  bool _isLoading = false;
  String? _error;
  String _statusFilter = 'ALL'; // ALL, OPEN, RESOLVED

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

    try {
      final list = await _firestore.getAllViolations(
        societyId: widget.societyId,
        status: _statusFilter == 'ALL' ? null : _statusFilter,
      );

      if (!mounted) return;
      setState(() {
        _violations = list;
        _filteredViolations = list;
        _isLoading = false;
      });
      AppLogger.i('Loaded ${list.length} violations');
    } catch (e) {
      AppLogger.e('Error loading violations', error: e);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load violations. Please try again.';
        });
      }
    }
  }

  void _onStatusFilterChanged(String value) {
    setState(() => _statusFilter = value);
    _loadViolations();
  }

  Future<void> _updateStatus(String violationId, String status) async {
    try {
      await _firestore.updateViolationStatus(
        societyId: widget.societyId,
        violationId: violationId,
        status: status,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Violation marked as $status'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _loadViolations();
    } catch (e) {
      AppLogger.e('Error updating violation status', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _publishMonthlySummary() async {
    final now = DateTime.now();
    int year = now.year;
    int month = now.month;

    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) {
        int y = year;
        int m = month;
        return AlertDialog(
          title: const Text('Publish monthly summary'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Select month for anonymous summary (no names):'),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      DropdownButton<int>(
                        value: m,
                        items: List.generate(12, (i) => i + 1).map((mo) => DropdownMenuItem(value: mo, child: Text(_monthName(mo)))).toList(),
                        onChanged: (v) => setState(() => m = v ?? m),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<int>(
                        value: y,
                        items: [now.year, now.year - 1].map((yr) => DropdownMenuItem(value: yr, child: Text('$yr'))).toList(),
                        onChanged: (v) => setState(() => y = v ?? y),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, DateTime(y, m)),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    if (picked == null || !mounted) return;

    year = picked.year;
    month = picked.month;

    setState(() => _isLoading = true);
    try {
      final stats = await _firestore.getViolationStatsForMonth(
        societyId: widget.societyId,
        year: year,
        month: month,
      );

      if (!mounted) return;

      final total = stats['total'] as int? ?? 0;
      final parking = stats['parking'] as int? ?? 0;
      final fireLane = stats['fireLane'] as int? ?? 0;
      final other = stats['other'] as int? ?? 0;
      final reducedPercent = stats['repeatedViolationsReducedPercent'] as num? ?? 0;

      final monthLabel = _monthName(month);
      final content = StringBuffer();
      content.writeln('In $monthLabel $year:');
      content.writeln('• $parking parking violation${parking != 1 ? 's' : ''}');
      content.writeln('• $fireLane fire-lane case${fireLane != 1 ? 's' : ''}');
      if (other > 0) content.writeln('• $other other');
      if (reducedPercent > 0) content.writeln('• Repeated violations reduced by ${reducedPercent.toStringAsFixed(0)}%');
      if (total == 0) content.writeln('• No violations reported this month.');

      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Publish summary as notice?'),
          content: SingleChildScrollView(
            child: Text(
              content.toString().trim(),
              style: const TextStyle(fontSize: 16, height: 1.4),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Publish'),
            ),
          ],
        ),
      );

      if (confirm != true || !mounted) {
        setState(() => _isLoading = false);
        return;
      }

      final title = 'Parking & violations summary – $monthLabel $year';
      final expiryAt = Timestamp.fromDate(DateTime(year, month).add(const Duration(days: 365)));
      await _firestore.createNotice(
        societyId: widget.societyId,
        title: title,
        content: content.toString().trim(),
        noticeType: 'announcement',
        priority: 'normal',
        createdByUid: widget.adminId,
        createdByName: widget.adminName,
        targetRole: 'all',
        expiryAt: expiryAt,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Monthly summary published to Notice Board'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      AppLogger.e('Error publishing monthly summary', error: e);
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to publish: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  static String _monthName(int month) {
    const names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return names[month - 1];
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
          'Manage Violations',
          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w900, fontSize: 20),
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
              // Privacy note
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.adminSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.admin.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_rounded, color: AppColors.admin, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Violations are private. Society sees only anonymous summaries when you publish.',
                        style: TextStyle(fontSize: 12, color: AppColors.text2, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              // Filters
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    _buildFilterChip('ALL', 'All'),
                    const SizedBox(width: 8),
                    _buildFilterChip('OPEN', 'Open'),
                    const SizedBox(width: 8),
                    _buildFilterChip('RESOLVED', 'Resolved'),
                  ],
                ),
              ),
              // List
              Expanded(
                child: _buildContent(),
              ),
            ],
          ),
          AppLoader.overlay(show: _isLoading, message: 'Loading violations…'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _publishMonthlySummary,
        icon: const Icon(Icons.assignment_rounded),
        label: const Text('Publish monthly summary'),
        backgroundColor: AppColors.admin,
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _statusFilter == value;
    return GestureDetector(
      onTap: () => _onStatusFilterChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.admin.withOpacity(0.15) : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppColors.admin : AppColors.border, width: isSelected ? 2 : 1),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: isSelected ? AppColors.admin : AppColors.text2),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: AppColors.text2, fontSize: 16), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadViolations,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.admin, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ],
        ),
      );
    }

    if (_filteredViolations.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.directions_car_outlined, size: 64, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              _statusFilter == 'ALL' ? 'No violations this month' : 'No $_statusFilter violations',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text),
            ),
            const SizedBox(height: 8),
            Text(
              'Guards can report violations from their dashboard.',
              style: TextStyle(fontSize: 14, color: AppColors.text2),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadViolations,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: _filteredViolations.length,
        itemBuilder: (context, index) {
          final v = _filteredViolations[index];
          return _buildViolationCard(v);
        },
      ),
    );
  }

  Widget _buildViolationCard(Map<String, dynamic> v) {
    final id = v['violation_id']?.toString() ?? '';
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
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showViolationDetails(v),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_violationTypeIcon(type), color: AppColors.warning, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Flat $flatNo', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.text)),
                    const SizedBox(height: 2),
                    Text(_violationTypeLabel(type), style: TextStyle(fontSize: 13, color: AppColors.text2)),
                    if (createdAt != null && createdAt.isNotEmpty)
                      Text(createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    if (note != null && note.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(note, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.text2)),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: status == 'RESOLVED' ? AppColors.success.withOpacity(0.15) : AppColors.warning.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: status == 'RESOLVED' ? AppColors.success : AppColors.warning)),
                        ),
                      ],
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
                    placeholder: (context, url) => Container(width: 48, height: 48, color: Colors.grey.shade300),
                    errorWidget: (context, url, error) => const SizedBox(width: 48, height: 48),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showViolationDetails(Map<String, dynamic> v) {
    final id = v['violation_id']?.toString() ?? '';
    final status = (v['status'] ?? 'OPEN').toString().toUpperCase();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Flat ${v['flat_no']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(_violationTypeLabel(v['violation_type']?.toString() ?? 'OTHER'), style: TextStyle(fontSize: 14, color: AppColors.text2)),
              if (v['note'] != null && (v['note'] as String).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(v['note'] as String, style: TextStyle(fontSize: 14, color: AppColors.text2)),
                ),
              const SizedBox(height: 16),
              if (status == 'OPEN')
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _updateStatus(id, 'RESOLVED');
                    },
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text('Mark as Resolved'),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ),
              if (status == 'RESOLVED')
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _updateStatus(id, 'OPEN');
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reopen'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.warning, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
