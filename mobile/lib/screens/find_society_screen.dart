import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/app_logger.dart';
import '../core/storage.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_service.dart';
import '../ui/app_loader.dart';
import 'admin_pending_approval_screen.dart';
import 'resident_pending_approval_screen.dart';

/// Directory-based join (Search Society -> request access).
/// Used after Phone OTP when membership is null.
/// mode:
///  - 'resident' (default): requires unit + owner/tenant, submits resident join request
///  - 'admin': society only, submits admin join request (approval by super_admin)
class FindSocietyScreen extends StatefulWidget {
  final String mode; // 'resident' | 'admin'
  const FindSocietyScreen({super.key, this.mode = 'resident'});

  bool get isAdminMode => mode.trim().toLowerCase() == 'admin';

  @override
  State<FindSocietyScreen> createState() => _FindSocietyScreenState();
}

class _FindSocietyScreenState extends State<FindSocietyScreen> {
  final FirestoreService _firestore = FirestoreService();

  String? _selectedSocietyId;

  // Resident-only
  String? _selectedUnitId;
  String? _residencyType; // OWNER | TENANT
  List<Map<String, dynamic>> _units = [];
  bool _loadingUnits = false;

  // Shared
  List<Map<String, dynamic>> _societies = [];
  final TextEditingController _searchController = TextEditingController();
  bool _loadingSocieties = false;
  bool _submitting = false;

  Timer? _searchDebounce;

  bool get _isAdmin => widget.isAdminMode;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _resetSelection({bool keepSearchText = true}) {
    setState(() {
      _selectedSocietyId = null;
      _societies = keepSearchText ? _societies : [];
      // resident-only resets
      _selectedUnitId = null;
      _residencyType = null;
      _units = [];
      _loadingUnits = false;
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();

    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _loadingSocieties = false;
        _societies = [];
        _selectedSocietyId = null;
        _units = [];
        _selectedUnitId = null;
        _residencyType = null;
      });
      return;
    }

    setState(() {
      _loadingSocieties = true;
      _societies = [];
      _selectedSocietyId = null;
      _units = [];
      _selectedUnitId = null;
      _residencyType = null;
    });

    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final list = await _firestore.searchPublicSocietiesByPrefix(trimmed);
        if (!mounted) return;
        setState(() {
          _societies = list;
          _loadingSocieties = false;
        });
      } catch (e, st) {
        AppLogger.e('FindSociety: search failed', error: e, stackTrace: st);
        if (!mounted) return;
        setState(() => _loadingSocieties = false);
      }
    });
  }

  Future<void> _loadUnits(String societyId) async {
    if (_isAdmin) return; // admin doesn't need units

    setState(() {
      _loadingUnits = true;
      _units = [];
      _selectedUnitId = null;
      _residencyType = null;
    });

    try {
      final list = await _firestore.getPublicSocietyUnits(societyId);
      if (!mounted) return;
      setState(() {
        _units = list;
        _loadingUnits = false;
      });
    } catch (e, st) {
      AppLogger.e('FindSociety: loadUnits failed', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() => _loadingUnits = false);
    }
  }

  Map<String, dynamic> _getSelectedSociety() {
    return _societies.firstWhere(
      (s) => s['id'] == _selectedSocietyId,
      orElse: () => <String, dynamic>{},
    );
  }

  Map<String, dynamic> _getSelectedUnit() {
    return _units.firstWhere(
      (u) => u['id'] == _selectedUnitId,
      orElse: () => <String, dynamic>{},
    );
  }

  Future<void> _submitRequest() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('You are not logged in. Please login again.', isError: true);
      return;
    }

    if (_selectedSocietyId == null) {
      _snack('Please select a society.', isError: true);
      return;
    }

    final society = _getSelectedSociety();
    final societyId = society['id'] as String?;
    final societyName = (society['name'] as String?) ?? '';
    final cityId = (society['cityId'] as String?) ?? '';

    if (societyId == null || societyId.isEmpty) {
      _snack('Invalid society selected.', isError: true);
      return;
    }

    // Resident validations
    if (!_isAdmin) {
      if (_selectedUnitId == null) {
        _snack('Please select your unit.', isError: true);
        return;
      }
      if (_residencyType == null ||
          (_residencyType != 'OWNER' && _residencyType != 'TENANT')) {
        _snack('Please select Owner or Tenant.', isError: true);
        return;
      }
    }

    final phoneRaw = user.phoneNumber ?? '';
    final normalizedPhone = FirebaseAuthService.normalizePhoneForIndia(
      phoneRaw.isNotEmpty ? phoneRaw : '',
    );

    setState(() => _submitting = true);
    try {
      final uid = user.uid;
      final displayName = user.displayName ?? (_isAdmin ? 'Admin' : 'Resident');

      if (_isAdmin) {
        // ✅ ADMIN: Create admin join request (approval by super_admin)
        await _firestore.createAdminJoinRequest(
          societyId: societyId,
          societyName: societyName,
          cityId: cityId,
          name: displayName,
          phoneE164: normalizedPhone,
        );

        // Remember which society this admin requested to join.
        await Storage.setAdminJoinSocietyId(societyId);

        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => AdminPendingApprovalScreen(
              adminId: uid,
              societyId: societyId,
              adminName: 'Admin',
            ),
          ),
        );
        return;
      }

      // ✅ RESIDENT: existing behavior (units + owner/tenant)
      final unit = _getSelectedUnit();
      final unitLabel = (unit['label'] as String?) ?? '';

      await _firestore.createResidentJoinRequest(
        societyId: societyId,
        societyName: societyName,
        cityId: cityId,
        unitLabel: unitLabel,
        residencyType: _residencyType!,
        name: displayName,
        phoneE164: normalizedPhone,
      );

      await Storage.saveResidentJoinSocietyId(societyId);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResidentPendingApprovalScreen(
            residentId: uid,
            societyId: societyId,
            residentName: 'Resident',
          ),
        ),
      );
    } catch (e, st) {
      AppLogger.e('FindSociety: submit failed', error: e, stackTrace: st);
      if (!mounted) return;
      _snack('Failed to submit request. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  // ---------------- UI helpers ----------------

  BoxDecoration _premiumCardDecoration(BuildContext context) {
    final theme = Theme.of(context);
    return BoxDecoration(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: theme.dividerColor.withOpacity(0.35),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 18,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  InputDecoration _premiumFieldDecoration({
    required BuildContext context,
    required String hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    String? labelText,
  }) {
    final theme = Theme.of(context);
    return InputDecoration(
      hintText: hintText,
      labelText: labelText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: theme.colorScheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.4)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.4)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: theme.colorScheme.primary.withOpacity(0.55),
          width: 1.5,
        ),
      ),
    );
  }

  String get _title => _isAdmin ? 'Find a society' : 'Find your society';

  String get _subtitle => _isAdmin
      ? 'Search your society and request Admin access. Super Admin will approve.'
      : 'Search your society and select your unit to request access.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded,
              color: theme.colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _title,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    _subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _buildSocietySection(),
                  const SizedBox(height: 14),

                  // ✅ Resident-only sections
                  if (!_isAdmin) ...[
                    _buildUnitDropdown(),
                    const SizedBox(height: 18),
                  ],

                  _buildConfirmSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSocietySection() {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          decoration: _premiumFieldDecoration(
            context: context,
            hintText: 'Enter your society name',
            prefixIcon: Icon(
              Icons.search_rounded,
              color: theme.colorScheme.onSurface.withOpacity(0.65),
            ),
            suffixIcon: _loadingSocieties
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : (_searchController.text.trim().isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close_rounded,
                            color: theme.colorScheme.onSurface.withOpacity(0.6)),
                        onPressed: () {
                          _searchController.clear();
                          _resetSelection(keepSearchText: false);
                        },
                      )
                    : null),
          ),
          onChanged: _onSearchChanged,
        ),
        const SizedBox(height: 12),
        if (_searchController.text.trim().isEmpty && _societies.isEmpty)
          Text(
            'Start typing to search your society.',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
              fontWeight: FontWeight.w600,
            ),
          )
        else if (_societies.isEmpty)
          Text(
            _loadingSocieties
                ? 'Searching...'
                : 'No societies found. Ask your society to update search name in app.',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
              fontWeight: FontWeight.w600,
            ),
          )
        else
          Container(
            decoration: _premiumCardDecoration(context),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: _societies.map((s) {
                final id = s['id'] as String;
                final selected = id == _selectedSocietyId;
                final name = s['name'] as String? ?? id;
                final cityName = s['cityName'] as String? ?? '';

                return Material(
                  color: selected
                      ? theme.colorScheme.primary.withOpacity(0.08)
                      : theme.colorScheme.surface,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedSocietyId = id;

                        // reset resident-only selection
                        _selectedUnitId = null;
                        _residencyType = null;
                        _units = [];
                      });
                      _loadUnits(id); // no-op for admin
                    },
                    child: ListTile(
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.apartment_rounded,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      title: Text(
                        name,
                        style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.w900 : FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      subtitle: cityName.isNotEmpty
                          ? Text(
                              cityName,
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.7),
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : null,
                      trailing: selected
                          ? Icon(
                              Icons.check_circle_rounded,
                              color: theme.colorScheme.primary,
                            )
                          : Icon(
                              Icons.chevron_right_rounded,
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.35),
                            ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildUnitDropdown() {
    final theme = Theme.of(context);

    if (_selectedSocietyId == null) {
      return Text(
        'Select a society to choose your unit.',
        style: TextStyle(
          color: theme.colorScheme.onSurface.withOpacity(0.7),
          fontWeight: FontWeight.w600,
        ),
      );
    }
    if (_loadingUnits) {
      return Center(child: AppLoader.inline());
    }
    if (_units.isEmpty) {
      return Text(
        'No units configured for this society.',
        style: TextStyle(
          color: theme.colorScheme.onSurface.withOpacity(0.7),
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return DropdownButtonFormField<String>(
      value: _selectedUnitId,
      decoration: _premiumFieldDecoration(
        context: context,
        hintText: '',
        labelText: 'Unit / flat',
      ),
      items: _units
          .map(
            (u) => DropdownMenuItem<String>(
              value: u['id'] as String,
              child: Text(u['label'] as String? ?? u['id'] as String),
            ),
          )
          .toList(),
      onChanged: (value) {
        setState(() {
          _selectedUnitId = value;
          _residencyType = null;
        });
      },
    );
  }

  Widget _buildConfirmSection() {
    if (_selectedSocietyId == null) return const SizedBox.shrink();

    // resident: wait until unit picked
    if (!_isAdmin && _selectedUnitId == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final society = _getSelectedSociety();
    final societyName =
        (society['name'] as String?) ?? _selectedSocietyId ?? '';

    final unitLabel = !_isAdmin
        ? (( _getSelectedUnit()['label'] as String?) ?? _selectedUnitId ?? '')
        : '';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _premiumCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isAdmin ? 'Confirm society' : 'Confirm your details',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          _buildConfirmRow(Icons.apartment_rounded, 'Society', societyName),

          if (!_isAdmin) ...[
            const SizedBox(height: 10),
            _buildConfirmRow(Icons.home_rounded, 'Unit', unitLabel),
            const SizedBox(height: 18),
            Text(
              'Are you the owner or tenant of this unit?',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildResidencyChip(
                    label: 'Owner',
                    value: 'OWNER',
                    icon: Icons.person_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildResidencyChip(
                    label: 'Tenant',
                    value: 'TENANT',
                    icon: Icons.badge_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
          ] else ...[
            Text(
              'Your request will be sent to the Super Admin for approval.',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 18),
          ],

          SizedBox(
            height: 52,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_isAdmin
                      ? !_submitting
                      : (_residencyType != null && !_submitting))
                  ? _submitRequest
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                disabledBackgroundColor:
                    theme.colorScheme.onSurface.withOpacity(0.10),
                disabledForegroundColor:
                    theme.colorScheme.onSurface.withOpacity(0.45),
              ),
              child: _submitting
                  ? AppLoader.inline(size: 22)
                  : Text(
                      _isAdmin ? 'Request Admin Access' : 'Send Join Request',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmRow(IconData icon, String label, String value) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withOpacity(0.65),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResidencyChip({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final selected = _residencyType == value;

    final bg = selected
        ? theme.colorScheme.primary.withOpacity(0.12)
        : theme.colorScheme.onSurface.withOpacity(0.05);

    final fg = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withOpacity(0.72);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => setState(() => _residencyType = value),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
