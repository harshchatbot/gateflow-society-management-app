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

  List<Map<String, dynamic>> _societies = [];
  List<Map<String, dynamic>> _units = [];

  String _searchQuery = '';
  bool _loadingSocieties = false;
  bool _loadingUnits = false;
  bool _submitting = false;

  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    // Initial state: wait for user to type a query.
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
    });
    _searchDebounce?.cancel();

    final trimmed = value.trim();
    if (trimmed.length < 2) {
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
        const SnackBar(
          content: Text('Please select society and unit'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are not logged in. Please login again.'),
          backgroundColor: AppColors.error,
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
        const SnackBar(
          content: Text('Invalid society selected.'),
          backgroundColor: AppColors.error,
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
        const SnackBar(
          content: Text('Failed to submit request. Please try again.'),
          backgroundColor: AppColors.error,
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
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Find your society',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: AppColors.text,
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
                    AppColors.primary.withOpacity(0.12),
                    AppColors.bg,
                    AppColors.bg,
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
                      color: AppColors.text2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildSocietySection(),
                  const SizedBox(height: 16),
                  _buildUnitDropdown(),
                  const SizedBox(height: 28),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submitJoinRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSocietySection() {
    if (_loadingSocieties) {
      return Center(child: AppLoader.inline());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          decoration: InputDecoration(
            hintText: 'Enter your society name',
            prefixIcon: const Icon(Icons.search_rounded),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
          onChanged: _onSearchChanged,
        ),
        const SizedBox(height: 12),
        if (_searchQuery.trim().length < 2 && _societies.isEmpty)
          Text(
            'Start typing to search your society.',
            style: TextStyle(color: AppColors.text2),
          )
        else if (_societies.isEmpty)
          Text(
            'No societies found.',
            style: TextStyle(color: AppColors.text2),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: _societies.map((s) {
                final id = s['id'] as String;
                final selected = id == _selectedSocietyId;
                final name = s['name'] as String? ?? id;
                final cityName = s['cityName'] as String? ?? '';
                return ListTile(
                  leading: const Icon(Icons.apartment_rounded,
                      color: AppColors.primary),
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
                            color: AppColors.text2,
                          ),
                        )
                      : null,
                  trailing: selected
                      ? const Icon(Icons.check_circle_rounded,
                          color: AppColors.primary)
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedSocietyId = id;
                      _selectedUnitId = null;
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
        style: TextStyle(color: AppColors.text2),
      );
    }
    if (_loadingUnits) {
      return Center(child: AppLoader.inline());
    }
    if (_units.isEmpty) {
      return Text(
        'No units configured for this society.',
        style: TextStyle(color: AppColors.text2),
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
        setState(() => _selectedUnitId = value);
      },
    );
  }
}

