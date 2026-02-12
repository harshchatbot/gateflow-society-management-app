import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../core/app_logger.dart';
import '../services/resident_service.dart';
import '../core/env.dart';
import '../ui/app_loader.dart';
import '../services/favorite_visitors_service.dart';

/// Notification Settings Screen
///
/// Allows residents to manage their notification preferences.
/// Theme: Green/Success theme (matching resident login and dashboard)
class ResidentNotificationSettingsScreen extends StatefulWidget {
  final String residentId;
  final String societyId;
  final String flatNo;

  const ResidentNotificationSettingsScreen({
    super.key,
    required this.residentId,
    required this.societyId,
    required this.flatNo,
  });

  @override
  State<ResidentNotificationSettingsScreen> createState() =>
      _ResidentNotificationSettingsScreenState();
}

class _ResidentNotificationSettingsScreenState
    extends State<ResidentNotificationSettingsScreen> {
  final _residentService = ResidentService(baseUrl: Env.apiBaseUrl);
  bool _pushNotifications = true;
  bool _emailNotifications = false;
  bool _smsNotifications = true;
  bool _isLoading = false;

  final FavoriteVisitorsService _favoritesService =
      FavoriteVisitorsService.instance;
  bool _autoApproveFavorites = false;
  bool _favoritesLoading = false;
  List<Map<String, dynamic>> _favoriteVisitors = <Map<String, dynamic>>[];
  bool _preapprovalsLoading = false;
  List<Map<String, dynamic>> _preapprovals = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _loadAutoApproveFlag();
    _loadFavoriteVisitors();
    _loadPreapprovals();
  }

  Future<void> _loadAutoApproveFlag() async {
    final enabled = await _favoritesService.getAutoApproveEnabled(
      widget.societyId,
      widget.residentId,
      unitId: widget.flatNo,
    );
    if (!mounted) return;
    setState(() => _autoApproveFavorites = enabled);
  }

  Future<void> _loadFavoriteVisitors() async {
    setState(() => _favoritesLoading = true);
    final list = await _favoritesService.getFavoriteVisitorsForUnit(
      societyId: widget.societyId,
      unitId: widget.flatNo,
      limit: 200,
    );
    if (!mounted) return;
    setState(() {
      _favoriteVisitors = list;
      _favoritesLoading = false;
    });
  }

  Future<void> _toggleFavoritePreApproval({
    required String visitorKey,
    required bool enabled,
  }) async {
    await _favoritesService.updateFavoriteSettings(
      societyId: widget.societyId,
      unitId: widget.flatNo,
      visitorKey: visitorKey,
      isPreApproved: enabled,
    );
    await _loadFavoriteVisitors();
  }

  Future<void> _setAutoApproveEnabledImmediate(bool enabled) async {
    setState(() => _autoApproveFavorites = enabled);
    try {
      await _favoritesService.setAutoApproveEnabled(
        widget.societyId,
        widget.residentId,
        enabled,
        unitId: widget.flatNo,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Auto-approve favourites enabled'
                : 'Auto-approve favourites disabled',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _autoApproveFavorites = !enabled);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update setting: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _loadPreapprovals() async {
    setState(() => _preapprovalsLoading = true);
    final list = await _favoritesService.getPreapprovalsForUnit(
      societyId: widget.societyId,
      unitId: widget.flatNo,
      limit: 200,
    );
    if (!mounted) return;
    setState(() {
      _preapprovals = list;
      _preapprovalsLoading = false;
    });
  }

  String _fmtDateTime(DateTime? dt) {
    if (dt == null) return '—';
    final d = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  String _fmtDays(List<int> days) {
    if (days.isEmpty) return 'All days';
    const labels = {1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun'};
    return days.map((d) => labels[d] ?? d.toString()).join(', ');
  }

  String _fmtMins(int? mins) {
    if (mins == null) return '—';
    final h = mins ~/ 60;
    final m = mins % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _favoriteNameByKey(String key) {
    for (final f in _favoriteVisitors) {
      if ((f['visitorKey'] ?? '').toString() == key) {
        return (f['name'] ?? 'Visitor').toString();
      }
    }
    return key;
  }

  Future<void> _deletePreapproval(String id) async {
    await _favoritesService.deletePreapproval(
      societyId: widget.societyId,
      unitId: widget.flatNo,
      preapprovalId: id,
    );
    await _loadPreapprovals();
  }

  Future<void> _openAddPreapprovalDialog() async {
    if (_favoriteVisitors.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add favourite visitors first.')),
      );
      return;
    }

    String selectedVisitorKey =
        (_favoriteVisitors.first['visitorKey'] ?? '').toString();
    DateTime validFrom = DateTime.now();
    DateTime validTo = DateTime.now().add(const Duration(days: 30));
    final Set<int> days = <int>{};
    bool useTimeWindow = false;
    TimeOfDay timeFrom = const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay timeTo = const TimeOfDay(hour: 20, minute: 0);
    bool notifyResident = true;
    final maxEntriesController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            Future<void> pickDateTime({
              required bool isFrom,
            }) async {
              final base = isFrom ? validFrom : validTo;
              final date = await showDatePicker(
                context: context,
                initialDate: base,
                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                lastDate: DateTime.now().add(const Duration(days: 3650)),
              );
              if (date == null) return;
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(base),
              );
              if (time == null) return;
              final dt = DateTime(
                date.year,
                date.month,
                date.day,
                time.hour,
                time.minute,
              );
              setLocal(() {
                if (isFrom) {
                  validFrom = dt;
                  if (!validTo.isAfter(validFrom)) {
                    validTo = validFrom.add(const Duration(hours: 1));
                  }
                } else {
                  validTo = dt;
                }
              });
            }

            return AlertDialog(
              title: const Text('Add Scheduled Pre-Approval'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedVisitorKey,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Favourite visitor',
                      ),
                      items: _favoriteVisitors.map((fav) {
                        final key = (fav['visitorKey'] ?? '').toString();
                        final name = (fav['name'] ?? 'Visitor').toString();
                        final phone = (fav['phone'] ?? '').toString();
                        return DropdownMenuItem<String>(
                          value: key,
                          child: Text(phone.isEmpty ? name : '$name • $phone'),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setLocal(() => selectedVisitorKey = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Valid from'),
                      subtitle: Text(_fmtDateTime(validFrom)),
                      trailing: const Icon(Icons.calendar_month_rounded),
                      onTap: () => pickDateTime(isFrom: true),
                    ),
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Valid to'),
                      subtitle: Text(_fmtDateTime(validTo)),
                      trailing: const Icon(Icons.event_available_rounded),
                      onTap: () => pickDateTime(isFrom: false),
                    ),
                    const SizedBox(height: 8),
                    const Text('Days of week (optional)'),
                    Wrap(
                      spacing: 6,
                      children: List<Widget>.generate(7, (i) {
                        final day = i + 1;
                        const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                        return FilterChip(
                          label: Text(labels[i]),
                          selected: days.contains(day),
                          onSelected: (selected) {
                            setLocal(() {
                              if (selected) {
                                days.add(day);
                              } else {
                                days.remove(day);
                              }
                            });
                          },
                        );
                      }),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Limit by time window'),
                      value: useTimeWindow,
                      onChanged: (v) => setLocal(() => useTimeWindow = v),
                    ),
                    if (useTimeWindow)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: timeFrom,
                                );
                                if (picked != null) setLocal(() => timeFrom = picked);
                              },
                              child: Text('From ${timeFrom.format(context)}'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: timeTo,
                                );
                                if (picked != null) setLocal(() => timeTo = picked);
                              },
                              child: Text('To ${timeTo.format(context)}'),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: maxEntriesController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Max entries (optional)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Notify resident on auto-entry'),
                      value: notifyResident,
                      onChanged: (v) => setLocal(() => notifyResident = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (!validTo.isAfter(validFrom)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Valid to must be after valid from'),
                        ),
                      );
                      return;
                    }
                    final maxEntries = int.tryParse(maxEntriesController.text.trim());
                    final fromMins =
                        useTimeWindow ? (timeFrom.hour * 60 + timeFrom.minute) : null;
                    final toMins =
                        useTimeWindow ? (timeTo.hour * 60 + timeTo.minute) : null;
                    await _favoritesService.upsertPreapproval(
                      societyId: widget.societyId,
                      unitId: widget.flatNo,
                      visitorKey: selectedVisitorKey,
                      validFrom: validFrom,
                      validTo: validTo,
                      daysOfWeek: days.toList()..sort(),
                      timeFromMins: fromMins,
                      timeToMins: toMins,
                      maxEntries: maxEntries,
                      notifyResidentOnEntry: notifyResident,
                    );
                    if (!mounted) return;
                    Navigator.of(context).pop();
                    await _loadPreapprovals();
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleSave() async {
    setState(() => _isLoading = true);

    try {
      // TODO: Implement notification preferences save to backend
      // For MVP, we can save FCM token if push notifications are enabled
      if (_pushNotifications) {
        // In a real implementation, you would get the FCM token here
        // and call: await _residentService.saveFcmToken(...)
        AppLogger.i("Notification preferences saved (MVP placeholder)");
      }
      await _favoritesService.setAutoApproveEnabled(
        widget.societyId,
        widget.residentId,
        _autoApproveFavorites,
        unitId: widget.flatNo,
      );

      await Future.delayed(
          const Duration(milliseconds: 500)); // Simulate API call

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                "Notification preferences saved",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      AppLogger.e("Error saving notification preferences", error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              "Failed to save preferences. Please try again.",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.text),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
        title: const Text(
          "Notification Settings",
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: AppColors.border,
          ),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              20 + MediaQuery.of(context).padding.bottom + 90,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Section
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.notifications_active_rounded,
                        color: AppColors.success,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Notification Preferences",
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: AppColors.text,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            "Choose how you want to receive notifications",
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.text2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // Push Notifications Card
                _buildNotificationCard(
                  icon: Icons.notifications_rounded,
                  title: "Push Notifications",
                  subtitle: "Receive notifications on your device",
                  value: _pushNotifications,
                  onChanged: (value) {
                    setState(() => _pushNotifications = value);
                  },
                  iconColor: AppColors.success,
                ),
                const SizedBox(height: 12),

                // Email Notifications Card
                _buildNotificationCard(
                  icon: Icons.email_rounded,
                  title: "Email Notifications",
                  subtitle: "Receive notifications via email",
                  value: _emailNotifications,
                  onChanged: (value) {
                    setState(() => _emailNotifications = value);
                  },
                  iconColor: AppColors.primary,
                ),
                const SizedBox(height: 12),

                // SMS Notifications Card
                _buildNotificationCard(
                  icon: Icons.sms_rounded,
                  title: "SMS Notifications",
                  subtitle: "Receive notifications via SMS",
                  value: _smsNotifications,
                  onChanged: (value) {
                    setState(() => _smsNotifications = value);
                  },
                  iconColor: AppColors.warning,
                ),

                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.bolt_rounded, color: AppColors.warning),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Quick Entry (Daily Help)",
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("Auto-approve favourite visitors"),
                        subtitle: const Text(
                          "When enabled, pre-approved favourites can enter without manual approval.",
                        ),
                        value: _autoApproveFavorites,
                        onChanged: _setAutoApproveEnabledImmediate,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Favourite Visitors",
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Mark specific favourites as pre-approved daily help.",
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.text2,
                            ),
                      ),
                      const SizedBox(height: 10),
                      if (_favoritesLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_favoriteVisitors.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text("No favourites saved yet."),
                        )
                      else
                        ..._favoriteVisitors.map((fav) {
                          final key = (fav['visitorKey'] ?? '').toString();
                          final name = (fav['name'] ?? 'Visitor').toString();
                          final phone = (fav['phone'] ?? '').toString();
                          final enabled = fav['isPreApproved'] == true;
                          return SwitchListTile.adaptive(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: enabled,
                            onChanged: (v) => _toggleFavoritePreApproval(
                              visitorKey: key,
                              enabled: v,
                            ),
                            title: Text(name),
                            subtitle: Text(
                              phone.isEmpty ? "No phone saved" : phone,
                            ),
                            secondary: Icon(
                              Icons.star_rounded,
                              color: AppColors.warning,
                            ),
                          );
                        }),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              "Scheduled Pre-Approvals",
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _openAddPreapprovalDialog,
                            icon: const Icon(Icons.add_circle_outline_rounded),
                            label: const Text('Add'),
                          ),
                        ],
                      ),
                      Text(
                        "Create time-bound passes for favourites.",
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.text2,
                            ),
                      ),
                      const SizedBox(height: 8),
                      if (_preapprovalsLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_preapprovals.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text("No schedules configured."),
                        )
                      else
                        ..._preapprovals.map((item) {
                          final id = (item['id'] ?? '').toString();
                          final key = (item['visitorKey'] ?? '').toString();
                          final validFrom = item['validFrom'] as DateTime?;
                          final validTo = item['validTo'] as DateTime?;
                          final days = (item['daysOfWeek'] as List?)?.cast<int>() ?? <int>[];
                          final fromMins = item['timeFromMins'] as int?;
                          final toMins = item['timeToMins'] as int?;
                          final maxEntries = item['maxEntries'] as int?;
                          final usedEntries = (item['usedEntries'] as int?) ?? 0;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.schedule_rounded),
                            title: Text(_favoriteNameByKey(key)),
                            subtitle: Text(
                              '${_fmtDateTime(validFrom)} → ${_fmtDateTime(validTo)}\n'
                              '${_fmtDays(days)}'
                              '${fromMins != null && toMins != null ? ' • ${_fmtMins(fromMins)}-${_fmtMins(toMins)}' : ''}'
                              '${maxEntries != null ? ' • $usedEntries/$maxEntries used' : ''}',
                            ),
                            isThreeLine: true,
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline_rounded),
                              color: AppColors.error,
                              onPressed: () => _deletePreapproval(id),
                            ),
                          );
                        }),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Save Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _handleSave,
                    icon: _isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: AppLoader.inline(size: 20),
                          )
                        : const Icon(Icons.save_rounded, size: 22),
                    label: Text(
                      _isLoading ? "Saving..." : "Save Preferences",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isLoading) AppLoader.overlay(showAfter: const Duration(milliseconds: 300), show: true),
        ],
      ),
    );
  }

  Widget _buildNotificationCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: value ? iconColor.withOpacity(0.3) : AppColors.border,
          width: value ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: value
                ? iconColor.withOpacity(0.08)
                : Colors.black.withOpacity(0.03),
            blurRadius: value ? 15 : 10,
            offset: Offset(0, value ? 4 : 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon Container
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),

          // Text Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.text2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Switch
          Transform.scale(
            scale: 1.1,
            child: Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeColor: iconColor,
            ),
          ),
        ],
      ),
    );
  }
}
