import 'package:flutter/material.dart';
import 'package:gateflow/models/visitor.dart';
import 'package:gateflow/services/visitor_service.dart';

import 'visitor_details_screen.dart';

import '../ui/app_colors.dart';
import '../ui/glass_loader.dart';

class VisitorListScreen extends StatefulWidget {
  final String guardId;
  const VisitorListScreen({super.key, required this.guardId});

  @override
  State<VisitorListScreen> createState() => _VisitorListScreenState();
}

class _VisitorListScreenState extends State<VisitorListScreen>
    with SingleTickerProviderStateMixin {
  final _service = VisitorService();
  late final TabController _tabController;

  bool _loading = false;
  String? _error;

  List<Visitor> _today = [];
  List<Visitor> _byFlat = [];

  final _flatController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadToday();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _flatController.dispose();
    super.dispose();
  }

  Future<void> _loadToday() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final Result<List<Visitor>> res =
        await _service.getVisitorsToday(guardId: widget.guardId);

    if (!mounted) return;

    setState(() {
      _loading = false;
      if (res.isSuccess) {
        _today = res.data!;
      } else {
        _error = res.error?.userMessage ?? "Failed to load visitors";
      }
    });
  }

  Future<void> _loadByFlat() async {
    debugPrint(
        "BY_FLAT: Search clicked. flatInput='${_flatController.text}' guardId='${widget.guardId}'");

    final flatNo = _flatController.text.trim();
    debugPrint("BY_FLAT: calling API getVisitorsByFlatNo... $flatNo");

    if (flatNo.isEmpty) {
      setState(() => _error = "Enter flat no (e.g., A-101)");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final Result<List<Visitor>> res = await _service.getVisitorsByFlatNo(
      guardId: widget.guardId,
      flatNo: flatNo,
    );

    if (!mounted) return;

    setState(() {
      _loading = false;
      if (res.isSuccess) {
        _byFlat = res.data!;
      } else {
        _error = res.error?.userMessage ?? "Failed to load visitors";
      }
    });
  }

  // Kept existing semantics; only mapped to premium palette.
  Color _statusColor(String status) {
    final s = status.toUpperCase();
    if (s.contains("APPROV")) return AppColors.success;
    if (s.contains("REJECT")) return AppColors.error;
    if (s.contains("LEAVE")) return AppColors.warning;
    if (s.contains("PENDING")) return AppColors.text2; // neutral
    return AppColors.textMuted;
  }

  Widget _visitorTile(Visitor v) {
    final displayFlat = v.flatNo.isNotEmpty ? v.flatNo : v.flatId;
    final statusColor = _statusColor(v.status);

    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                VisitorDetailsScreen(visitor: v, guardId: widget.guardId),
          ),
        );
        // refresh after returning (status might change)
        if (!mounted) return;
        if (_tabController.index == 0) {
          _loadToday();
        } else {
          _loadByFlat();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(
            bottom: BorderSide(color: AppColors.border, width: 1),
          ),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: (v.photoUrl != null && v.photoUrl!.isNotEmpty)
                    ? Image.network(
                        v.photoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.person, color: AppColors.primary),
                      )
                    : const Icon(Icons.person, color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 12),

            // Main text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${v.visitorType} • Flat $displayFlat",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    v.visitorPhone.isEmpty ? "No phone" : v.visitorPhone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.text2,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            // Status chip (same text, premium styling)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: statusColor.withOpacity(0.35)),
              ),
              child: Text(
                v.status,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 11.8,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildTabBar() {
    return TabBar(
      controller: _tabController,
      indicatorSize: TabBarIndicatorSize.label,
      indicator: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.text2,
      labelStyle: const TextStyle(fontWeight: FontWeight.w800),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
      tabs: const [
        Tab(text: "Today"),
        Tab(text: "By Flat"),
      ],
    );
  }

  Widget _errorBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: AppColors.error.withOpacity(0.9)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 12.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _error = null),
            icon: const Icon(Icons.close_rounded),
            color: AppColors.error.withOpacity(0.9),
            tooltip: "Dismiss",
          ),
        ],
      ),
    );
  }

  Widget _byFlatSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: _flatController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _loadByFlat(),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.home_outlined, color: AppColors.text2),
                  labelText: "Flat No",
                  hintText: "e.g. A-101",
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 48,
            width: 110,
            child: ElevatedButton(
              onPressed: _loadByFlat,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                "Search",
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // NOTE: No functionality changes:
    // - Same API calls
    // - Same refresh logic
    // - Same tabs and lists
    // - Only UI polish + GlassLoader + theme colors

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        surfaceTintColor: AppColors.bg,
        title: const Text(
          "Visitors",
          style: TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.w800,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.border),
              ),
              child: _buildTabBar(),
            ),
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {
              if (_tabController.index == 0) _loadToday();
              if (_tabController.index == 1) _loadByFlat();
            },
            icon: const Icon(Icons.refresh_rounded, color: AppColors.text),
            tooltip: "Refresh",
          )
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_error != null) _errorBanner(),

              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Today
                    RefreshIndicator(
                      onRefresh: _loadToday,
                      child: ListView.separated(
                        itemCount: _today.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 0),
                        itemBuilder: (_, i) => _visitorTile(_today[i]),
                      ),
                    ),

                    // By Flat
                    Column(
                      children: [
                        _byFlatSearchBar(),
                        Expanded(
                          child: ListView.separated(
                            itemCount: _byFlat.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 0),
                            itemBuilder: (_, i) => _visitorTile(_byFlat[i]),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ✅ Full screen glassmorphism loader for all loadings
          GlassLoader(
            show: _loading,
            message: "Loading…",
          ),
        ],
      ),
    );
  }
}
