import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/app_logger.dart';
import '../core/storage.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_service.dart';
import '../ui/app_loader.dart';
import 'resident_pending_approval_screen.dart';

/// Resident onboarding: directory-based join (Search Society -> Unit).
/// Shown after Phone OTP when resident has no active membership.
class FindSocietyScreen extends StatefulWidget {
  const FindSocietyScreen({super.key});

  @override
  State<FindSocietyScreen> createState() => _FindSocietyScreenState();
}

class _FindSocietyScreenState extends State<FindSocietyScreen> {
  final FirestoreService _firestore = FirestoreService();

  String? _selectedSocietyId;
  String? _selectedUnitId;

  /// OWNER or TENANT; null until user selects in confirm step.
  String? _residencyType;

  List<Map<String, dynamic>> _societies = [];
  List<Map<String, dynamic>> _units = [];

  final TextEditingController _searchController = TextEditingController();
  bool _loadingSocieties = false;
  bool _loadingUnits = false;
  bool _submitting = false;

  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
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
      });
      return;
    }

    setState(() {
      _loadingSocieties = true;
      _societies = [];
      _selectedSocietyId = null;
      _units = [];
      _selectedUnitId = null;
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
    setState(() {
      _loadingUnits = true;
      _units = [];
      _selectedUnitId = null;
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

  Future<void> _submitJoinRequest() async {
    if (_selectedSocietyId == null || _selectedUnitId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select society and unit'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    if (_residencyType == null ||
        (_residencyType != 'OWNER' && _residencyType != 'TENANT')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select Owner or Tenant'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('You are not logged in. Please login again.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    final society = _societies.firstWhere(
      (s) => s['id'] == _selectedSocietyId,
      orElse: () => {},
    );
    final unit = _units.firstWhere(
      (u) => u['id'] == _selectedUnitId,
      orElse: () => {},
    );

    final societyId = society['id'] as String?;
    final societyName = (society['name'] as String?) ?? '';
    final cityId = (society['cityId'] as String?) ?? '';
    final unitLabel = (unit['label'] as String?) ?? '';

    if (societyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Invalid society selected.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    final phoneRaw = user.phoneNumber ?? '';
    final normalizedPhone = FirebaseAuthService.normalizePhoneForIndia(
      phoneRaw.isNotEmpty ? phoneRaw : '',
    );

    setState(() => _submitting = true);
    try {
      final displayName = user.displayName ?? 'Resident';
      await _firestore.createResidentJoinRequest(
        societyId: societyId,
        societyName: societyName,
        cityId: cityId,
        unitLabel: unitLabel,
        residencyType: _residencyType!,
        name: displayName,
        phoneE164: normalizedPhone,
      );

      // Remember which society this resident requested to join.
      await Storage.saveResidentJoinSocietyId(societyId);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResidentPendingApprovalScreen(
            email: user.email ?? 'Phone login',
          ),
        ),
      );
    } catch (e, st) {
      AppLogger.e(
        'FindSociety: submitJoinRequest failed',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to submit request. Please try again.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
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
        borderSide: BorderSide(color: theme.colorScheme.primary.withOpacity(0.55), width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: theme.colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Find your society',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
      body: Stack(
        children: [
          // Calm neutral wash (MyGate-like “premium grey” feel)
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
                    'Search your society and select your unit to request access.',
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _buildSocietySection(),
                  const SizedBox(height: 14),
                  _buildUnitDropdown(),
                  const SizedBox(height: 18),
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
                : null,
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
                : 'No societies found. If your society was recently added or renamed, ask an admin to use "Sync search name" in the app.',
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
                        _selectedUnitId = null;
                        _residencyType = null;
                        _units = [];
                      });
                      _loadUnits(id);
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
                          fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      subtitle: cityName.isNotEmpty
                          ? Text(
                              cityName,
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSurface.withOpacity(0.7),
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
                              color: theme.colorScheme.onSurface.withOpacity(0.35),
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

  /// Shown only after society and unit are selected: summary + Owner/Tenant + Send button.
  Widget _buildConfirmSection() {
    if (_selectedSocietyId == null || _selectedUnitId == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    final society = _societies.firstWhere(
      (s) => s['id'] == _selectedSocietyId,
      orElse: () => <String, dynamic>{},
    );
    final unit = _units.firstWhere(
      (u) => u['id'] == _selectedUnitId,
      orElse: () => <String, dynamic>{},
    );

    final societyName = (society['name'] as String?) ?? _selectedSocietyId ?? '';
    final unitLabel = (unit['label'] as String?) ?? _selectedUnitId ?? '';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _premiumCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Confirm your details',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),

          _buildConfirmRow(Icons.apartment_rounded, 'Society', societyName),
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
          SizedBox(
            height: 52,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_residencyType != null && !_submitting) ? _submitJoinRequest : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                disabledBackgroundColor: theme.colorScheme.onSurface.withOpacity(0.10),
                disabledForegroundColor: theme.colorScheme.onSurface.withOpacity(0.45),
              ),
              child: _submitting
                  ? AppLoader.inline(size: 22)
                  : const Text(
                      'Send Join Request',
                      style: TextStyle(
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
