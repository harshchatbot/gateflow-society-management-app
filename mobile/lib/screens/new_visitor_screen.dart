import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_logger.dart';
import '../core/app_error.dart';
import '../core/storage.dart';
import '../models/visitor.dart';
import '../services/firebase_visitor_service.dart';
import '../services/firestore_service.dart';

import 'guard_login_screen.dart';

// UI system
import '../ui/app_colors.dart';
import '../ui/app_loader.dart';
import '../ui/app_icons.dart';
import '../ui/sentinel_theme.dart';
import '../core/society_modules.dart';
import '../widgets/module_disabled_placeholder.dart';

/// Config for a chip group (e.g. Cab Provider, Delivery Partner). Add entries to _chipGroups to extend.
class ChipGroupConfig {
  final String title;
  final String visitorType;
  final String storageKey;
  final String field;
  final List<String> options;
  final String defaultValue;
  final IconData icon;

  const ChipGroupConfig({
    required this.title,
    required this.visitorType,
    required this.storageKey,
    required this.field,
    required this.options,
    required this.defaultValue,
    required this.icon,
  });
}

class NewVisitorScreen extends StatefulWidget {
  final String guardId;
  final String guardName;
  final String societyId;
  final VoidCallback? onBackPressed;

  const NewVisitorScreen({
    super.key,
    required this.guardId,
    required this.guardName,
    required this.societyId,
    this.onBackPressed,
  });

  @override
  State<NewVisitorScreen> createState() => _NewVisitorScreenState();
}

class _NewVisitorScreenState extends State<NewVisitorScreen> {
  final _formKey = GlobalKey<FormState>();

  // Chip groups: add a config entry to support a new type (e.g. cab.provider, delivery.provider).
  static final List<ChipGroupConfig> _chipGroups = [
    ChipGroupConfig(
      title: 'Cab Provider',
      visitorType: 'CAB',
      storageKey: 'cab',
      field: 'provider',
      options: ['Ola', 'Uber', 'Other'],
      defaultValue: 'Other',
      icon: Icons.directions_car_rounded,
    ),
    ChipGroupConfig(
      title: 'Delivery Partner',
      visitorType: 'DELIVERY',
      storageKey: 'delivery',
      field: 'provider',
      options: ['Zomato', 'Swiggy', 'Blinkit', 'Zepto', 'Amazon', 'Flipkart', 'Dunzo', 'Other'],
      defaultValue: 'Other',
      icon: Icons.local_shipping_rounded,
    ),
  ];

  /// One map for all chip selections; key = "${storageKey}.${field}".
  final Map<String, String?> _chipSelections = {};

  // Controllers
  final _visitorNameController = TextEditingController();
  final _visitorPhoneController = TextEditingController();
  final _vehicleNumberController = TextEditingController();
  final _deliveryPartnerOtherController = TextEditingController();
  final _visitorService = FirebaseVisitorService();
  final _firestore = FirestoreService();

  final ImagePicker _picker = ImagePicker();
  File? _visitorPhoto;

  String _selectedVisitorType = 'GUEST';
  bool _isLoading = false;
  Visitor? _createdVisitor;

  String _getSelection(ChipGroupConfig g) =>
      _chipSelections[_selectionKey(g)] ?? g.defaultValue;

  void _setSelection(ChipGroupConfig g, String? value) {
    setState(() {
      if (value == null) {
        _chipSelections.remove(_selectionKey(g));
      } else {
        _chipSelections[_selectionKey(g)] = value;
      }
      if (g.storageKey == 'delivery' && value != 'Other') {
        _deliveryPartnerOtherController.clear();
      }
    });
  }

  static String _selectionKey(ChipGroupConfig g) => '${g.storageKey}.${g.field}';

  // Flats/units for dropdown (loaded from society)
  List<Map<String, dynamic>> _flats = [];
  bool _flatsLoading = true;
  String? _selectedFlatNo; // Selected unit label (flat no, villa label, etc.)

  // Flat owner (resident) for current flat — shown so guard can call
  String? _flatOwnerName;
  String? _flatOwnerPhone;
  bool _flatOwnerLoading = false;

  bool _submitButtonPressed = false;

  @override
  void initState() {
    super.initState();
    _loadFlats();
  }

  @override
  void dispose() {
    _visitorNameController.dispose();
    _visitorPhoneController.dispose();
    _vehicleNumberController.dispose();
    _deliveryPartnerOtherController.dispose();
    super.dispose();
  }

  Future<void> _loadFlats() async {
    setState(() => _flatsLoading = true);
    try {
      // Prefer society flats (societies/{id}/flats); if empty, use public_societies units (e.g. Villa-E01)
      List<Map<String, dynamic>> list = await _firestore.getSocietyFlats(widget.societyId);
      if (list.isEmpty) {
        final publicUnits = await _firestore.getPublicSocietyUnits(widget.societyId);
        list = publicUnits.map((u) {
          final label = (u['label'] as String?) ?? u['id'] as String;
          return {'id': u['id'], 'flatNo': label};
        }).toList();
      }
      if (!mounted) return;
      setState(() {
        _flats = list;
        _flatsLoading = false;
      });
    } catch (e) {
      AppLogger.e('NewVisitor: load flats failed', error: e);
      if (mounted) setState(() => _flatsLoading = false);
    }
  }

  void _onFlatSelected(String? flatNo) {
    setState(() {
      _selectedFlatNo = flatNo;
      _flatOwnerName = null;
      _flatOwnerPhone = null;
    });
    if (flatNo != null && flatNo.isNotEmpty) _lookupFlatOwner();
  }

  Future<void> _lookupFlatOwner() async {
    final flat = _selectedFlatNo?.trim() ?? '';
    if (flat.isEmpty) {
      if (mounted) {
        setState(() {
        _flatOwnerName = null;
        _flatOwnerPhone = null;
        _flatOwnerLoading = false;
      });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _flatOwnerLoading = true);
    try {
      final members = await _firestore.getMembers(
        societyId: widget.societyId,
        systemRole: 'resident',
      );
      final flatNorm = flat.toUpperCase();
      final matches = members.cast<Map<String, dynamic>>().where((m) {
        final mFlat = (m['flat_no'] ?? m['flatNo'] ?? '').toString().trim().toUpperCase();
        return mFlat == flatNorm;
      }).toList();
      if (!mounted) return;
      if (matches.isNotEmpty) {
        final m = matches.first;
        final name = (m['resident_name'] ?? m['name'] ?? 'Resident').toString();
        final phone = (m['resident_phone'] ?? m['phone'] ?? m['mobile'] ?? '').toString();
        setState(() {
          _flatOwnerName = name;
          _flatOwnerPhone = phone.isNotEmpty ? phone : null;
          _flatOwnerLoading = false;
        });
      } else {
        setState(() {
          _flatOwnerName = null;
          _flatOwnerPhone = null;
          _flatOwnerLoading = false;
        });
      }
    } catch (e) {
      AppLogger.w('Flat owner lookup failed', error: e.toString());
      if (mounted) {
        setState(() {
        _flatOwnerName = null;
        _flatOwnerPhone = null;
        _flatOwnerLoading = false;
      });
      }
    }
  }

  Future<void> _launchCall(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.isEmpty) return;
    final uri = Uri.parse('tel:$cleaned');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // --- LOGIC SECTION ---

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _createdVisitor = null;
    });

    // Look up resident phone for this flat so guard can call owner while approval is pending
    String? residentPhone;
    try {
      final members = await _firestore.getMembers(
        societyId: widget.societyId,
        systemRole: 'resident',
      );
      final flatNorm = (_selectedFlatNo?.trim() ?? '').toUpperCase();
      final matches = members.cast<Map<String, dynamic>>().where((m) {
        final mFlat = (m['flat_no'] ?? m['flatNo'] ?? '').toString().trim().toUpperCase();
        return mFlat == flatNorm;
      }).toList();
      if (matches.isNotEmpty) {
        final m = matches.first;
        residentPhone = (m['resident_phone'] ?? m['phone'] ?? m['mobile'] ?? '').toString();
        if (residentPhone.isEmpty) residentPhone = null;
      }
    } catch (e) {
      AppLogger.w('Resident phone lookup failed (continuing without)', error: e.toString());
    }

    final visitorName = _visitorNameController.text.trim().isEmpty ? null : _visitorNameController.text.trim();
    final vehicleNumber = _vehicleNumberController.text.trim().isEmpty ? null : _vehicleNumberController.text.trim();
    final isDelivery = _selectedVisitorType == 'DELIVERY';
    final deliveryConfig = _chipGroups.firstWhere((g) => g.visitorType == 'DELIVERY');
    final deliveryPartnerValue = _getSelection(deliveryConfig);
    final deliveryPartner = isDelivery && deliveryPartnerValue.trim().isNotEmpty
        ? deliveryPartnerValue.trim()
        : null;
    final deliveryPartnerOther = isDelivery && deliveryPartnerValue == 'Other'
        ? (_deliveryPartnerOtherController.text.trim().isEmpty ? null : _deliveryPartnerOtherController.text.trim())
        : null;

    final flatNo = _selectedFlatNo?.trim() ?? '';
    if (flatNo.isEmpty) {
      _showError('Please select a flat / unit');
      return;
    }

    final extraTypeData = _buildTypePayload();

    final result = (_visitorPhoto != null)
        ? await _visitorService.createVisitorWithPhoto(
            societyId: widget.societyId,
            flatNo: flatNo,
            visitorType: _selectedVisitorType,
            visitorPhone: _visitorPhoneController.text.trim(),
            photoFile: _visitorPhoto!,
            residentPhone: residentPhone,
            visitorName: visitorName,
            deliveryPartner: deliveryPartner,
            deliveryPartnerOther: deliveryPartnerOther,
            vehicleNumber: vehicleNumber,
            typePayload: extraTypeData.isNotEmpty ? extraTypeData : null,
          )
        : await _visitorService.createVisitor(
            societyId: widget.societyId,
            flatNo: flatNo,
            visitorType: _selectedVisitorType,
            visitorPhone: _visitorPhoneController.text.trim(),
            residentPhone: residentPhone,
            visitorName: visitorName,
            deliveryPartner: deliveryPartner,
            deliveryPartnerOther: deliveryPartnerOther,
            vehicleNumber: vehicleNumber,
            typePayload: extraTypeData.isNotEmpty ? extraTypeData : null,
          );

    if (!mounted) return;

    if (result.isSuccess) {
      setState(() {
        _isLoading = false;
        _createdVisitor = result.data!;
      });
    } else {
      setState(() => _isLoading = false);
      final err = result.error ?? AppError(userMessage: 'Failed to create visitor', technicalMessage: 'Unknown');
      AppLogger.e('Visitor creation failed', error: err.technicalMessage);
      _showError(err.userMessage);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _clearForm() {
    setState(() {
      _visitorNameController.clear();
      _selectedFlatNo = null;
      _visitorPhoneController.clear();
      _vehicleNumberController.clear();
      _deliveryPartnerOtherController.clear();
      _selectedVisitorType = 'GUEST';
      _chipSelections.clear();
      _createdVisitor = null;
      _visitorPhoto = null;
      _flatOwnerName = null;
      _flatOwnerPhone = null;
    });
  }

  /// Builds typePayload for Firestore from config and current selections (cab.provider, delivery.provider, etc.).
  Map<String, dynamic> _buildTypePayload() {
    final payload = <String, dynamic>{};
    for (final g in _chipGroups) {
      if (_selectedVisitorType != g.visitorType) continue;
      final value = _getSelection(g);
      payload.putIfAbsent(g.storageKey, () => <String, dynamic>{});
      (payload[g.storageKey] as Map<String, dynamic>)[g.field] = value;
    }
    return payload;
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 75,
        maxWidth: 1080,
      );
      if (picked == null) return;
      setState(() => _visitorPhoto = File(picked.path));
    } catch (e) {
      if (!mounted) return;
      _showError("Camera error. Please allow permission.");
    }
  }

  // --- UI COMPONENTS ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!SocietyModules.isEnabled(SocietyModuleIds.visitorManagement)) {
      return ModuleDisabledPlaceholder(onBack: widget.onBackPressed);
    }
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) {
          // If we're in a tab navigation (IndexedStack), switch to dashboard
          if (widget.onBackPressed != null) {
            widget.onBackPressed!();
          } else if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          automaticallyImplyLeading: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface),
            onPressed: () {
              // If we're in a tab navigation (IndexedStack), switch to dashboard
              if (widget.onBackPressed != null) {
                widget.onBackPressed!();
              } else if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
        title: Text('New Entry', style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w900, fontSize: 22)),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 120), // Responsive bottom padding
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  if (_createdVisitor != null) _buildSuccessCard() else _buildEntryForm(),
                ],
              ),
            ),
          ),
          AppLoader.overlay(show: _isLoading, message: "Syncing with Residents..."),
        ],
      ),
      ),
    );
  }

  Widget _buildEntryForm() {
    return Column(
      children: [
        _buildPhotoSection(),
        const SizedBox(height: 20),
        _buildInputCard(),
      ],
    );
  }

  Widget _buildPhotoSection() {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      height: 220,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor),
        boxShadow: [BoxShadow(color: theme.colorScheme.onSurface.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: _visitorPhoto == null
            ? InkWell(
                onTap: _takePhoto,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(AppIcons.camera, size: 40, color: theme.colorScheme.primary.withOpacity(0.5)),
                    const SizedBox(height: 12),
                    Text("Capture Visitor Photo", style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.7))),
                  ],
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(_visitorPhoto!, fit: BoxFit.cover),
                  Positioned(
                    top: 12, right: 12,
                    child: CircleAvatar(
                      backgroundColor: Colors.black54,
                      child: IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _takePhoto),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildChipGroup(BuildContext context, ChipGroupConfig g) {
    if (_selectedVisitorType != g.visitorType) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        _buildFieldLabel(g.title),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: g.options
                .map((opt) => Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _buildChoiceChip(
                        context: context,
                        label: opt,
                        icon: g.icon,
                        selected: _getSelection(g) == opt,
                        onTap: () => _setSelection(g, _getSelection(g) == opt ? null : opt),
                      ),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildChoiceChip({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final bgColor = selected ? SentinelColors.accentSurface(0.04) : theme.colorScheme.surface;
    final borderColor = selected ? SentinelColors.accentBorder : theme.dividerColor;
    final fgColor = selected ? SentinelColors.accent : theme.colorScheme.onSurface.withOpacity(0.7);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fgColor),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fgColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputCard() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFieldLabel("Visitor Name (optional)"),
          _buildOptionalTextField(
            controller: _visitorNameController,
            hint: "e.g. Rahul / Zomato Delivery",
            icon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 18),
          _buildFieldLabel("Visitor Mobile"),
          _buildTextField(
            controller: _visitorPhoneController,
            hint: "10-digit mobile number",
            icon: AppIcons.phone,
            isPhone: true,
          ),
          const SizedBox(height: 18),
          _buildFieldLabel("Flat / Unit"),
          _flatsLoading
              ? Container(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Row(
                    children: [
                      SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary)),
                      const SizedBox(width: 12),
                      Text("Loading units...", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7), fontWeight: FontWeight.w600)),
                    ],
                  ),
                )
              : _flats.isEmpty
                  ? Container(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: Text("No units configured for this society.", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7), fontWeight: FontWeight.w600)),
                    )
                  : DropdownButtonFormField<String>(
                      value: _selectedFlatNo,
                      decoration: InputDecoration(
                        prefixIcon: Icon(AppIcons.flat, color: theme.colorScheme.primary.withOpacity(0.8)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        filled: true,
                        fillColor: theme.colorScheme.surface,
                      ),
                      hint: const Text("Select unit / villa / flat"),
                      items: _flats.map((f) {
                        final flatNo = (f['flatNo'] as String?) ?? f['id'] as String;
                        return DropdownMenuItem<String>(value: flatNo, child: Text(flatNo));
                      }).toList(),
                      onChanged: _onFlatSelected,
                    ),
          const SizedBox(height: 18),
          _buildFieldLabel("Vehicle Number (optional)"),
          _buildOptionalTextField(
            controller: _vehicleNumberController,
            hint: "e.g. RJ14 AB 1234",
            icon: Icons.directions_car_outlined,
          ),
          if (_flatOwnerLoading) ...[
            const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final t = Theme.of(context);
                return Row(
                  children: [
                    SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: t.colorScheme.primary)),
                    const SizedBox(width: 10),
                    Text("Finding flat owner...", style: TextStyle(fontSize: 12, color: t.colorScheme.onSurface.withOpacity(0.7), fontWeight: FontWeight.w600)),
                  ],
                );
              },
            ),
          ] else if (_flatOwnerName != null || _flatOwnerPhone != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.success.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_rounded, size: 20, color: AppColors.success),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Flat owner", style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          _flatOwnerName ?? '—',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface),
                        ),
                        if (_flatOwnerPhone != null && _flatOwnerPhone!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            _flatOwnerPhone!,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_flatOwnerPhone != null && _flatOwnerPhone!.trim().isNotEmpty)
                    IconButton(
                      onPressed: () => _launchCall(_flatOwnerPhone!),
                      icon: const Icon(Icons.call_rounded, color: AppColors.success, size: 24),
                      tooltip: 'Call flat owner',
                    ),
                ],
              ),
            ),
          ] else if (_selectedFlatNo != null && _selectedFlatNo!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              "No resident found for this flat.",
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 18),
          _buildFieldLabel("Visitor Category"),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildTypePill("GUEST", AppIcons.guest),
              const SizedBox(width: 8),
              _buildTypePill("DELIVERY", AppIcons.delivery),
              const SizedBox(width: 8),
              _buildTypePill("CAB", AppIcons.cab),
            ],
          ),
          ..._chipGroups.map((g) => _buildChipGroup(context, g)).toList(),
          if (_selectedVisitorType == 'DELIVERY' &&
              _getSelection(_chipGroups.firstWhere((c) => c.visitorType == 'DELIVERY')) == 'Other') ...[
            const SizedBox(height: 12),
            _buildOptionalTextField(
              controller: _deliveryPartnerOtherController,
              hint: "Other Partner Name",
              icon: Icons.store_outlined,
            ),
          ],
          const SizedBox(height: 25),
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => setState(() => _submitButtonPressed = true),
            onPointerUp: (_) => setState(() => _submitButtonPressed = false),
            onPointerCancel: (_) => setState(() => _submitButtonPressed = false),
            child: AnimatedScale(
              scale: _submitButtonPressed ? 0.98 : 1.0,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeInOut,
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: Text("NOTIFY RESIDENT", style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String hint, required IconData icon, bool isPhone = false}) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: controller,
      keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
      inputFormatters: isPhone ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)] : [],
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: theme.colorScheme.primary, size: 20),
        filled: true,
        fillColor: theme.scaffoldBackgroundColor,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      ),
      validator: (v) => v!.isEmpty ? "Required" : null,
    );
  }

  Widget _buildOptionalTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.text,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: theme.colorScheme.primary, size: 20),
        filled: true,
        fillColor: theme.scaffoldBackgroundColor,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface, fontSize: 13)),
    );
  }

  Widget _buildTypePill(String type, IconData icon) {
    final theme = Theme.of(context);
    final bool isSelected = _selectedVisitorType == type;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() {
          _selectedVisitorType = type;
          for (final g in _chipGroups) {
            if (g.visitorType != type) _chipSelections.remove(_selectionKey(g));
          }
          if (type != 'DELIVERY') _deliveryPartnerOtherController.clear();
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? theme.colorScheme.primary : theme.scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface.withOpacity(0.7)),
              const SizedBox(height: 4),
              Text(type, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface.withOpacity(0.7))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessCard() {
    final theme = Theme.of(context);
    final v = _createdVisitor!;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.success.withOpacity(0.3))),
      child: Column(
        children: [
          const CircleAvatar(backgroundColor: AppColors.success, radius: 30, child: Icon(Icons.check, color: Colors.white, size: 35)),
          const SizedBox(height: 16),
          const Text("Notification Sent!", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
          Text("Resident has been alerted.", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7))),
          const Divider(height: 32),
          _buildInfoRow("Flat Number", v.flatNo),
          _buildInfoRow("Category", v.visitorType),
          _buildInfoRow("Status", v.status, isStatus: true),
          if (v.residentPhone != null && v.residentPhone!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            _buildResidentPhoneRow(v.residentPhone!),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton(
              onPressed: _clearForm,
              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), side: BorderSide(color: theme.colorScheme.primary)),
              child: const Text("NEW ENTRY", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isStatus = false}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontWeight: FontWeight.bold)),
          isStatus 
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.statusChipBg(value), borderRadius: BorderRadius.circular(8)),
                child: Text(value, style: TextStyle(color: AppColors.statusChipFg(value), fontWeight: FontWeight.bold, fontSize: 12)),
              )
            : Text(value, style: TextStyle(fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
        ],
      ),
    );
  }

  Widget _buildResidentPhoneRow(String phone) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("Resident phone", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontWeight: FontWeight.bold)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(phone, style: TextStyle(fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _launchCall(phone),
                icon: const Icon(Icons.call_rounded, color: AppColors.success, size: 22),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                tooltip: 'Call resident',
              ),
            ],
          ),
        ],
      ),
    );
  }
}