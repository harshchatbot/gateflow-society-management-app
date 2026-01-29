import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gateflow/models/visitor.dart';
import 'package:gateflow/services/firestore_service.dart';

import 'visitor_details_screen.dart';
import '../ui/app_colors.dart';
import '../ui/app_loader.dart';
import '../core/app_logger.dart';

class VisitorListScreen extends StatefulWidget {
  final String guardId;
  final VoidCallback? onBackPressed;
  const VisitorListScreen({
    super.key,
    required this.guardId,
    this.onBackPressed,
  });

  @override
  State<VisitorListScreen> createState() => _VisitorListScreenState();
}

class _VisitorListScreenState extends State<VisitorListScreen>
    with SingleTickerProviderStateMixin {
  final FirestoreService _firestore = FirestoreService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  late final TabController _tabController;

  bool _loading = false;
  String? _error;
  String? _societyId;

  List<Visitor> _today = [];
  List<Visitor> _byFlat = [];

  final _flatController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSocietyIdAndToday();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _flatController.dispose();
    super.dispose();
  }

  Future<void> _loadSocietyIdAndToday() async {
    // Get societyId from membership
    try {
      final membership = await _firestore.getCurrentUserMembership();
      _societyId = membership?['societyId'] as String?;
      if (_societyId != null && _societyId!.isNotEmpty) {
        await _loadToday();
      } else {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = "Society ID not found";
          });
        }
      }
    } catch (e) {
      AppLogger.e("Error loading society ID", error: e);
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Failed to load data";
        });
      }
    }
  }

  // --- REFRESH LOGIC ---
  Future<void> _loadToday() async {
    if (_societyId == null || _societyId!.isEmpty) {
      await _loadSocietyIdAndToday();
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      // Get today's visitors from Firestore
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final visitorsRef = _db
          .collection('societies')
          .doc(_societyId!)
          .collection('visitors');

      QuerySnapshot querySnapshot;
      try {
        querySnapshot = await visitorsRef
            .where('guard_uid', isEqualTo: widget.guardId)
            .limit(100)
            .get()
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        AppLogger.w("getTodayVisitors timeout or error", error: e.toString());
        querySnapshot = await visitorsRef
            .where('guard_uid', isEqualTo: widget.guardId)
            .limit(0)
            .get();
      }

      // Filter by today's date in memory and convert to Visitor objects
      final todayVisitors = querySnapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) return false;
        
        final createdAt = data['createdAt'];
        if (createdAt == null) return false;
        
        DateTime createdDate;
        if (createdAt is Timestamp) {
          createdDate = createdAt.toDate();
        } else if (createdAt is DateTime) {
          createdDate = createdAt;
        } else {
          return false;
        }
        
        return createdDate.isAfter(startOfDay.subtract(const Duration(seconds: 1))) &&
               createdDate.isBefore(endOfDay);
      }).map((doc) => _mapToVisitor(doc.data() as Map<String, dynamic>, doc.id)).toList();

      // Sort by createdAt descending
      todayVisitors.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (mounted) {
        setState(() {
          _loading = false;
          _today = todayVisitors;
          _error = null;
        });
      }

      AppLogger.i("Loaded ${todayVisitors.length} today's visitors", data: {
        "guardId": widget.guardId,
        "societyId": _societyId,
      });
    } catch (e, stackTrace) {
      AppLogger.e("Error loading today's visitors", error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Failed to load visitors";
        });
      }
    }
  }

  Future<void> _loadByFlat() async {
    final flatNo = _flatController.text.trim().toUpperCase();
    if (flatNo.isEmpty || _societyId == null || _societyId!.isEmpty) return;
    
    setState(() { _loading = true; _error = null; });

    try {
      final visitorsRef = _db
          .collection('societies')
          .doc(_societyId!)
          .collection('visitors');

      QuerySnapshot querySnapshot;
      try {
        querySnapshot = await visitorsRef
            .where('guard_uid', isEqualTo: widget.guardId)
            .where('flat_no', isEqualTo: flatNo)
            .orderBy('createdAt', descending: true)
            .limit(50)
            .get()
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        AppLogger.w("getVisitorsByFlat timeout or error", error: e.toString());
        // Try without orderBy if composite index is missing
        querySnapshot = await visitorsRef
            .where('guard_uid', isEqualTo: widget.guardId)
            .where('flat_no', isEqualTo: flatNo)
            .limit(50)
            .get()
            .timeout(const Duration(seconds: 10));
      }

      final visitors = querySnapshot.docs
          .map((doc) => _mapToVisitor(doc.data() as Map<String, dynamic>, doc.id))
          .toList();

      // Sort by createdAt descending
      visitors.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (mounted) {
        setState(() {
          _loading = false;
          _byFlat = visitors;
          _error = visitors.isEmpty ? "No records found" : null;
        });
      }
    } catch (e, stackTrace) {
      AppLogger.e("Error loading visitors by flat", error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Failed to load visitors";
        });
      }
    }
  }

  Visitor _mapToVisitor(Map<String, dynamic> data, String docId) {
    // Parse createdAt
    DateTime createdAt;
    final createdAtValue = data['createdAt'];
    if (createdAtValue is Timestamp) {
      createdAt = createdAtValue.toDate();
    } else if (createdAtValue is DateTime) {
      createdAt = createdAtValue;
    } else {
      createdAt = DateTime.now();
    }

    // Parse approvedAt if exists
    DateTime? approvedAt;
    final approvedAtValue = data['approvedAt'] ?? data['approved_at'];
    if (approvedAtValue != null) {
      if (approvedAtValue is Timestamp) {
        approvedAt = approvedAtValue.toDate();
      } else if (approvedAtValue is DateTime) {
        approvedAt = approvedAtValue;
      }
    }

    return Visitor(
      visitorId: docId,
      societyId: data['society_id']?.toString() ?? _societyId ?? '',
      flatId: data['flat_id']?.toString() ?? data['flat_no']?.toString() ?? '',
      flatNo: (data['flat_no'] ?? data['flatNo'] ?? '').toString(),
      visitorType: (data['visitor_type'] ?? data['visitorType'] ?? 'GUEST').toString(),
      visitorPhone: (data['visitor_phone'] ?? data['visitorPhone'] ?? '').toString(),
      status: (data['status'] ?? 'PENDING').toString(),
      createdAt: createdAt,
      approvedAt: approvedAt,
      approvedBy: data['approved_by']?.toString() ?? data['approvedBy']?.toString(),
      guardId: data['guard_uid']?.toString() ?? data['guard_id']?.toString() ?? widget.guardId,
      photoPath: data['photo_path']?.toString(),
      photoUrl: data['photo_url']?.toString() ?? data['photoUrl']?.toString(),
      note: data['note']?.toString(),
    );
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
          if (!mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VisitorDetailsScreen(visitor: v, guardId: widget.guardId),
            ),
          );
          if (mounted) {
            _loadToday(); // Refresh on return
          }
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
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.text),
            onPressed: () {
              // If we're in a tab navigation (IndexedStack), switch to dashboard
              if (widget.onBackPressed != null) {
                widget.onBackPressed!();
              } else if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
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
          AppLoader.overlay(show: _loading, message: "Updating logs..."),
        ],
      ),
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