import 'package:flutter/material.dart';
import 'package:gateflow/models/visitor.dart';
import 'package:gateflow/services/visitor_service.dart';
import 'package:gateflow/core/result.dart';

import 'visitor_details_screen.dart';

class VisitorListScreen extends StatefulWidget {
  final String guardId;
  const VisitorListScreen({super.key, required this.guardId});

  @override
  State<VisitorListScreen> createState() => _VisitorListScreenState();
}

class _VisitorListScreenState extends State<VisitorListScreen> with SingleTickerProviderStateMixin {
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

    final res = await _service.getVisitorsToday(guardId: widget.guardId);

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
    final flatId = _flatController.text.trim();
    if (flatId.isEmpty) {
      setState(() => _error = "Enter flat id");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final res = await _service.getVisitorsByFlat(flatId: flatId);

    setState(() {
      _loading = false;
      if (res.isSuccess) {
        _byFlat = res.data!;
      } else {
        _error = res.error?.userMessage ?? "Failed to load visitors";
      }
    });
  }

  Color _statusColor(String status) {
    final s = status.toUpperCase();
    if (s.contains("APPROV")) return Colors.green;
    if (s.contains("REJECT")) return Colors.red;
    if (s.contains("LEAVE")) return Colors.orange;
    if (s.contains("PENDING")) return Colors.blueGrey;
    return Colors.grey;
  }

  Widget _visitorTile(Visitor v) {
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: (v.photoUrl != null && v.photoUrl!.isNotEmpty)
            ? NetworkImage(v.photoUrl!)
            : null,
        child: (v.photoUrl == null || v.photoUrl!.isEmpty) ? const Icon(Icons.person) : null,
      ),
      title: Text("${v.visitorType} • Flat ${v.flatId}"),
      subtitle: Text(v.visitorPhone.isEmpty ? "No phone" : v.visitorPhone),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _statusColor(v.status).withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _statusColor(v.status).withOpacity(0.35)),
        ),
        child: Text(
          v.status,
          style: TextStyle(color: _statusColor(v.status), fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => VisitorDetailsScreen(visitor: v, guardId: widget.guardId)),
        );
        // refresh after returning (status might change)
        if (_tabController.index == 0) {
          _loadToday();
        } else {
          _loadByFlat();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Visitors"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "Today"),
            Tab(text: "By Flat"),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              if (_tabController.index == 0) _loadToday();
              if (_tabController.index == 1) _loadByFlat();
            },
            icon: const Icon(Icons.refresh),
          )
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.red.withOpacity(0.08),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: Stack(
              children: [
                TabBarView(
                  controller: _tabController,
                  children: [
                    // Today
                    RefreshIndicator(
                      onRefresh: _loadToday,
                      child: ListView.separated(
                        itemCount: _today.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) => _visitorTile(_today[i]),
                      ),
                    ),

                    // By flat
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _flatController,
                                  decoration: const InputDecoration(
                                    labelText: "Flat ID",
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: _loadByFlat,
                                  child: const Text("Search"),
                                ),
                              )
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            itemCount: _byFlat.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) => _visitorTile(_byFlat[i]),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                if (_loading)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.05),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
