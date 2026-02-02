import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/app_logger.dart';
import '../core/storage.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_service.dart';
import '../ui/app_colors.dart';
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
        final list =
            await _firestore.searchPublicSocietiesByPrefix(trimmed);
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
    if (_residencyType == null || (_residencyType != 'OWNER' && _residencyType != 'TENANT')) {
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
    final normalizedPhone =
        FirebaseAuthService.normalizePhoneForIndia(phoneRaw.isNotEmpty ? phoneRaw : '');

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
      AppLogger.e('FindSociety: submitJoinRequest failed',
          error: e, stackTrace: st);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Find your society',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.primary.withOpacity(0.12),
                    Theme.of(context).scaffoldBackgroundColor,
                    Theme.of(context).scaffoldBackgroundColor,
                  ],
                ),
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
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildSocietySection(),
                  const SizedBox(height: 16),
                  _buildUnitDropdown(),
                  const SizedBox(height: 24),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Enter your society name',
            prefixIcon: const Icon(Icons.search_rounded),
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
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
          onChanged: _onSearchChanged,
        ),
        const SizedBox(height: 12),
        if (_searchController.text.trim().isEmpty && _societies.isEmpty)
          Text(
            'Start typing to search your society.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
          )
        else if (_societies.isEmpty)
          Text(
            _loadingSocieties
                ? 'Searching...'
                : 'No societies found. If your society was recently added or renamed, ask an admin to use "Sync search name" in the app.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              children: _societies.map((s) {
                final id = s['id'] as String;
                final selected = id == _selectedSocietyId;
                final name = s['name'] as String? ?? id;
                final cityName = s['cityName'] as String? ?? '';
                return ListTile(
                  leading: Icon(Icons.apartment_rounded,
                      color: Theme.of(context).colorScheme.primary),
                  title: Text(
                    name,
                    style: TextStyle(
                      fontWeight:
                          selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  subtitle: cityName.isNotEmpty
                      ? Text(
                          cityName,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          ),
                        )
                      : null,
                  trailing: selected
                      ? Icon(Icons.check_circle_rounded,
                          color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedSocietyId = id;
                      _selectedUnitId = null;
                      _residencyType = null;
                      _units = [];
                    });
                    _loadUnits(id);
                  },
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildUnitDropdown() {
    if (_selectedSocietyId == null) {
      return Text(
        'Select a society to choose your unit.',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
      );
    }
    if (_loadingUnits) {
      return Center(child: AppLoader.inline());
    }
    if (_units.isEmpty) {
      return Text(
        'No units configured for this society.',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
      );
    }
    return DropdownButtonFormField<String>(
      value: _selectedUnitId,
      decoration: InputDecoration(
        labelText: 'Unit / flat',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        filled: true,
        fillColor: Colors.white,
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Confirm your details',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          _buildConfirmRow(Icons.apartment_rounded, 'Society', societyName),
          const SizedBox(height: 10),
          _buildConfirmRow(Icons.home_rounded, 'Unit', unitLabel),
          const SizedBox(height: 20),
          Text(
            'Are you the owner or tenant of this unit?',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
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
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_residencyType != null && !_submitting)
                  ? _submitJoinRequest
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
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
    final selected = _residencyType == value;
    return Material(
      color: selected ? Theme.of(context).colorScheme.primary.withOpacity(0.12) : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => setState(() => _residencyType = value),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

