import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_logger.dart';
import 'firebase_visitor_service.dart';
import 'visitor_service.dart';

/// Action types for the offline queue (guard/resident actions that need network).
const String kActionCreateVisitor = 'create_visitor';
const String kActionUpdateStatus = 'update_status';

const String _prefKeyQueue = 'offline_queue_actions';

/// Single pending action: type + payload (JSON-serializable).
class QueuedAction {
  final String id;
  final String type;
  final Map<String, dynamic> payload;

  QueuedAction({required this.id, required this.type, required this.payload});

  Map<String, dynamic> toJson() => {'id': id, 'type': type, 'payload': payload};

  static QueuedAction? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final type = json['type'] as String?;
    final payload = json['payload'];
    if (id == null || type == null || payload is! Map) return null;
    return QueuedAction(
      id: id,
      type: type,
      payload: Map<String, dynamic>.from(payload),
    );
  }
}

/// Maintains a persistent queue of visitor actions; replays when connectivity returns.
/// No Firestore schema changes; replays same service calls (FirebaseVisitorService, VisitorService).
class OfflineQueueService {
  OfflineQueueService._();
  static final OfflineQueueService instance = OfflineQueueService._();

  final FirebaseVisitorService _firebaseVisitor = FirebaseVisitorService();
  final VisitorService _visitorApi = VisitorService();

  List<QueuedAction> _queue = [];
  bool _isOnline = true;
  bool _isProcessing = false;
  bool _initDone = false;

  Future<void> ensureInit() async {
    if (_initDone) return;
    _initDone = true;
    await init();
  }

  /// Current connectivity (true = we consider device online for sync).
  bool get isOnline => _isOnline;

  /// Number of pending actions. Listen to this for UI (e.g. badge).
  int get pendingCount => _queue.length;

  /// Callback when queue length changes (e.g. setState in dashboard).
  void Function()? onQueueChanged;

  /// Callback when sync fails for an item (e.g. show SnackBar "Retry when online").
  void Function(String message)? onSyncFailure;

  /// Callback when sync succeeds (optional; e.g. show "Synced" toast).
  void Function()? onSyncSuccess;

  static void _notify(OfflineQueueService s) {
    s.onQueueChanged?.call();
  }

  Future<void> init() async {
    await _loadQueue();
    Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      final online = results.isNotEmpty &&
          results.any((r) =>
              r == ConnectivityResult.wifi ||
              r == ConnectivityResult.mobile ||
              r == ConnectivityResult.ethernet);
      if (_isOnline != online) {
        _isOnline = online;
        _notify(this);
        if (online) _processQueue();
      }
    });
    // Initial state
    final results = await Connectivity().checkConnectivity();
    _isOnline = results.isNotEmpty &&
        results.any((r) =>
            r == ConnectivityResult.wifi ||
            r == ConnectivityResult.mobile ||
            r == ConnectivityResult.ethernet);
    _notify(this);
    if (_isOnline) _processQueue();
  }

  Future<String> _getQueuePhotoDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final queueDir = Directory('${dir.path}/offline_queue_photos');
    if (!await queueDir.exists()) await queueDir.create(recursive: true);
    return queueDir.path;
  }

  Future<void> _loadQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = prefs.getStringList(_prefKeyQueue);
      if (jsonList == null) return;
      _queue = [];
      for (final s in jsonList) {
        try {
          final map = jsonDecode(s) as Map<String, dynamic>;
          final a = QueuedAction.fromJson(map);
          if (a != null) _queue.add(a);
        } catch (_) {}
      }
    } catch (e) {
      AppLogger.e('OfflineQueue: load failed', error: e);
    }
  }

  Future<void> _saveQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _queue.map((a) => jsonEncode(a.toJson())).toList();
      await prefs.setStringList(_prefKeyQueue, list);
      _notify(this);
    } catch (e) {
      AppLogger.e('OfflineQueue: save failed', error: e);
    }
  }

  /// Enqueue create visitor (Firebase). [photoPath] optional; if set, file is copied to queue dir and path stored.
  Future<void> enqueueCreateVisitor({
    required String societyId,
    required String flatNo,
    required String visitorType,
    required String visitorPhone,
    String? residentPhone,
    String? visitorName,
    String? deliveryPartner,
    String? deliveryPartnerOther,
    String? vehicleNumber,
    Map<String, dynamic>? typePayload,
    String? photoPath,
  }) async {
    final id = 'cv_${DateTime.now().millisecondsSinceEpoch}_${_queue.length}';
    String? storedPhotoPath;
    if (photoPath != null && photoPath.isNotEmpty) {
      try {
        final src = File(photoPath);
        if (await src.exists()) {
          final dir = await _getQueuePhotoDir();
          final ext = photoPath.toLowerCase().endsWith('.jpg') ||
                  photoPath.toLowerCase().endsWith('.jpeg')
              ? '.jpg'
              : '.jpg';
          final dest = File('$dir/$id$ext');
          await src.copy(dest.path);
          storedPhotoPath = dest.path;
        }
      } catch (e) {
        AppLogger.w('OfflineQueue: copy photo failed', error: e.toString());
      }
    }
    final payload = <String, dynamic>{
      'societyId': societyId,
      'flatNo': flatNo,
      'visitorType': visitorType,
      'visitorPhone': visitorPhone,
      if (residentPhone != null && residentPhone.isNotEmpty)
        'residentPhone': residentPhone,
      if (visitorName != null && visitorName.isNotEmpty)
        'visitorName': visitorName,
      if (deliveryPartner != null && deliveryPartner.isNotEmpty)
        'deliveryPartner': deliveryPartner,
      if (deliveryPartnerOther != null && deliveryPartnerOther.isNotEmpty)
        'deliveryPartnerOther': deliveryPartnerOther,
      if (vehicleNumber != null && vehicleNumber.isNotEmpty)
        'vehicleNumber': vehicleNumber,
      if (typePayload != null && typePayload.isNotEmpty)
        'typePayload': typePayload,
      'hasPhoto': storedPhotoPath != null,
      if (storedPhotoPath != null) 'photoPath': storedPhotoPath,
    };
    _queue.add(
        QueuedAction(id: id, type: kActionCreateVisitor, payload: payload));
    await _saveQueue();
  }

  /// Enqueue update visitor status (API).
  Future<void> enqueueUpdateStatus({
    required String visitorId,
    required String status,
    String? approvedBy,
    String? note,
  }) async {
    final id = 'us_${DateTime.now().millisecondsSinceEpoch}_${_queue.length}';
    final payload = <String, dynamic>{
      'visitorId': visitorId,
      'status': status,
      if (approvedBy != null && approvedBy.isNotEmpty) 'approvedBy': approvedBy,
      if (note != null && note.isNotEmpty) 'note': note,
    };
    _queue
        .add(QueuedAction(id: id, type: kActionUpdateStatus, payload: payload));
    await _saveQueue();
  }

  Future<void> _processQueue() async {
    if (_isProcessing || !_isOnline || _queue.isEmpty) return;
    _isProcessing = true;
    final failed = <QueuedAction>[];
    for (final action in List<QueuedAction>.from(_queue)) {
      if (!_isOnline) break;
      bool success = false;
      if (action.type == kActionCreateVisitor) {
        success = await _replayCreateVisitor(action.payload);
      } else if (action.type == kActionUpdateStatus) {
        success = await _replayUpdateStatus(action.payload);
      }
      if (success) {
        _queue.removeWhere((a) => a.id == action.id);
        await _saveQueue();
        onSyncSuccess?.call();
      } else {
        failed.add(action);
      }
    }
    _isProcessing = false;
    if (failed.isNotEmpty && onSyncFailure != null) {
      onSyncFailure!(
          '${failed.length} action(s) could not sync. Will retry when online.');
    }
  }

  Future<bool> _replayCreateVisitor(Map<String, dynamic> p) async {
    try {
      final societyId = p['societyId'] as String? ?? '';
      final flatNo = p['flatNo'] as String? ?? '';
      final visitorType = p['visitorType'] as String? ?? 'GUEST';
      final visitorPhone = p['visitorPhone'] as String? ?? '';
      if (societyId.isEmpty || flatNo.isEmpty) return false;
      final residentPhone = p['residentPhone'] as String?;
      final visitorName = p['visitorName'] as String?;
      final deliveryPartner = p['deliveryPartner'] as String?;
      final deliveryPartnerOther = p['deliveryPartnerOther'] as String?;
      final vehicleNumber = p['vehicleNumber'] as String?;
      final typePayload = p['typePayload'] is Map
          ? Map<String, dynamic>.from(p['typePayload'] as Map)
          : null;
      final hasPhoto = p['hasPhoto'] == true;
      final photoPath = p['photoPath'] as String?;

      if (hasPhoto && photoPath != null && photoPath.isNotEmpty) {
        final file = File(photoPath);
        if (await file.exists()) {
          final r = await _firebaseVisitor.createVisitorWithPhoto(
            societyId: societyId,
            flatNo: flatNo,
            visitorType: visitorType,
            visitorPhone: visitorPhone,
            photoFile: file,
            residentPhone: residentPhone,
            visitorName: visitorName,
            deliveryPartner: deliveryPartner,
            deliveryPartnerOther: deliveryPartnerOther,
            vehicleNumber: vehicleNumber,
            typePayload: typePayload,
          );
          if (r.isSuccess) {
            try {
              await file.delete();
            } catch (_) {}
            return true;
          }
        }
      }
      final r = await _firebaseVisitor.createVisitor(
        societyId: societyId,
        flatNo: flatNo,
        visitorType: visitorType,
        visitorPhone: visitorPhone,
        residentPhone: residentPhone,
        visitorName: visitorName,
        deliveryPartner: deliveryPartner,
        deliveryPartnerOther: deliveryPartnerOther,
        vehicleNumber: vehicleNumber,
        typePayload: typePayload,
      );
      return r.isSuccess;
    } catch (e) {
      AppLogger.e('OfflineQueue: replay create_visitor failed', error: e);
      return false;
    }
  }

  Future<bool> _replayUpdateStatus(Map<String, dynamic> p) async {
    try {
      final visitorId = p['visitorId'] as String? ?? '';
      final status = p['status'] as String? ?? '';
      if (visitorId.isEmpty || status.isEmpty) return false;
      final approvedBy = p['approvedBy'] as String?;
      final note = p['note'] as String?;
      final r = await _visitorApi.updateVisitorStatus(
        visitorId: visitorId,
        status: status,
        approvedBy: approvedBy,
        note: note,
      );
      return r.isSuccess;
    } catch (e) {
      AppLogger.e('OfflineQueue: replay update_status failed', error: e);
      return false;
    }
  }
}
