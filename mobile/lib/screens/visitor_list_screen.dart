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

  // --- REFRESH LOGIC ---
  Future<void> _loadToday() async {
    setState(() { _loading = true; _error = null; });
    final res = await _service.getVisitorsToday(guardId: widget.guardId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.isSuccess) _today = res.data!;
      else _error = res.error?.userMessage ?? "Failed to load visitors";
    });
  }

  Future<void> _loadByFlat() async {
    final flatNo = _flatController.text.trim();
    if (flatNo.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    final res = await _service.getVisitorsByFlatNo(guardId: widget.guardId, flatNo: flatNo);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.isSuccess) _byFlat = res.data!;
      else _error = "No records found";
    });
  }

  // --- COMPACT UI COMPONENTS ---

  Widget _buildCompactVisitorCard(Visitor v) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), // Reduced vertical margin
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withOpacity(0.6)),
      ),
      child: ListTile(
        dense: true, // Makes the tile smaller
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VisitorDetailsScreen(visitor: v, guardId: widget.guardId),
            ),
          );
          _loadToday(); // Refresh on return
        },
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: AppColors.primarySoft,
          backgroundImage: (v.photoUrl != null && v.photoUrl!.isNotEmpty) 
              ? NetworkImage(v.photoUrl!) 
              : null,
          child: (v.photoUrl == null || v.photoUrl!.isEmpty)
              ? const Icon(Icons.person, size: 20, color: AppColors.primary)
              : null,
        ),
        title: Text(
          "${v.visitorType} • Flat ${v.flatNo}",
          style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.text, fontSize: 14),
        ),
        subtitle: Text(v.visitorPhone, style: const TextStyle(fontSize: 12, color: AppColors.text2)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.statusChipBg(v.status),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            v.status,
            style: TextStyle(color: AppColors.statusChipFg(v.status), fontWeight: FontWeight.bold, fontSize: 10),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text("Visitor Logs", style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w900)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_rounded, color: AppColors.primary),
            onPressed: () => _tabController.index == 0 ? _loadToday() : _loadByFlat(),
          )
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.primary,
              indicatorWeight: 3,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textMuted,
              labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
              tabs: const [Tab(text: "Today's List"), Tab(text: "Search by Flat")],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: [
              // Tab 1: Today with Pull-to-Refresh
              RefreshIndicator(
                onRefresh: _loadToday,
                color: AppColors.primary,
                child: _today.isEmpty 
                  ? _buildEmptyState() 
                  : ListView.builder(
                      padding: const EdgeInsets.only(top: 12, bottom: 120),
                      itemCount: _today.length,
                      itemBuilder: (context, index) => _buildCompactVisitorCard(_today[index]),
                    ),
              ),
              // Tab 2: Search
              Column(
                children: [
                  _buildCompactSearchBar(),
                  Expanded(
                    child: _byFlat.isEmpty 
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 120),
                          itemCount: _byFlat.length,
                          itemBuilder: (context, index) => _buildCompactVisitorCard(_byFlat[index]),
                        ),
                  ),
                ],
              ),
            ],
          ),
          GlassLoader(show: _loading, message: "Updating logs..."),
        ],
      ),
    );
  }

  Widget _buildCompactSearchBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: _flatController,
        onSubmitted: (_) => _loadByFlat(),
        decoration: InputDecoration(
          hintText: "Enter Flat No (e.g. A-101)",
          hintStyle: const TextStyle(fontSize: 14),
          border: InputBorder.none,
          suffixIcon: IconButton(
            icon: const Icon(Icons.search, color: AppColors.primary),
            onPressed: _loadByFlat,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Text("No records found", style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.bold)),
    );
  }
}