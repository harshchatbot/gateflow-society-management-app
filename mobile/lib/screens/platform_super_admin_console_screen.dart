import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/society_requests_service.dart';
import '../ui/app_loader.dart';
import 'onboarding_choose_role_screen.dart';
import 'super_admin_society_requests_screen.dart';

class PlatformSuperAdminConsoleScreen extends StatefulWidget {
  final String adminName;

  const PlatformSuperAdminConsoleScreen({
    super.key,
    required this.adminName,
  });

  @override
  State<PlatformSuperAdminConsoleScreen> createState() =>
      _PlatformSuperAdminConsoleScreenState();
}

class _PlatformSuperAdminConsoleScreenState
    extends State<PlatformSuperAdminConsoleScreen> {
  final SocietyRequestsService _service = SocietyRequestsService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _summary = const {};
  List<Map<String, dynamic>> _recentSocieties = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _service.getDashboard();
    if (!mounted) return;
    if (!result.isSuccess) {
      setState(() {
        _loading = false;
        _error = result.error?.userMessage ?? 'Failed to load dashboard';
      });
      return;
    }

    final data = result.data ?? {};
    final summary = (data['summary'] is Map<String, dynamic>)
        ? Map<String, dynamic>.from(data['summary'] as Map)
        : <String, dynamic>{};
    final recent = (data['recent_societies'] is List)
        ? List<Map<String, dynamic>>.from(
            (data['recent_societies'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map)),
          )
        : <Map<String, dynamic>>[];

    setState(() {
      _summary = summary;
      _recentSocieties = recent;
      _loading = false;
    });
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const OnboardingChooseRoleScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = (_summary['total_societies'] ?? 0).toString();
    final active = (_summary['active_societies'] ?? 0).toString();
    final pending = (_summary['pending_requests'] ?? 0).toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform Super Admin'),
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: _loading
          ? AppLoader.fullscreen(show: true)
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'Welcome, ${widget.adminName}',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _statCard(context, 'Total Societies', total),
                          const SizedBox(width: 10),
                          _statCard(context, 'Active', active),
                          const SizedBox(width: 10),
                          _statCard(context, 'Pending', pending),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.approval_rounded),
                          title: const Text('Society Registration Requests'),
                          subtitle: const Text('Review and approve/reject requests'),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const SuperAdminSocietyRequestsScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Recent Societies',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_recentSocieties.isEmpty)
                        const Text('No societies found')
                      else
                        ..._recentSocieties.map((s) {
                          final name = (s['name'] ?? '').toString();
                          final code = (s['code'] ?? '').toString();
                          final city = (s['city'] ?? '').toString();
                          final state = (s['state'] ?? '').toString();
                          final activeFlag = s['active'] == true;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: theme.dividerColor),
                            ),
                            child: ListTile(
                              title: Text(name.isNotEmpty ? name : (s['id'] ?? '').toString()),
                              subtitle: Text(
                                'Code: $code${city.isNotEmpty || state.isNotEmpty ? " • $city${city.isNotEmpty && state.isNotEmpty ? ", " : ""}$state" : ""}',
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: activeFlag
                                      ? Colors.green.withOpacity(0.12)
                                      : Colors.red.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  activeFlag ? 'Active' : 'Inactive',
                                  style: TextStyle(
                                    color: activeFlag ? Colors.green.shade700 : Colors.red.shade700,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }

  Widget _statCard(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
