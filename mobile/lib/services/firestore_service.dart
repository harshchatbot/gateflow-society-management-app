import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/app_logger.dart';

/// FirestoreService - Multi-tenant Firestore operations
/// 
/// All operations are scoped to societies/{societyId}/...
/// Ensures data isolation between societies
class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Get current user's UID
  String? get currentUid => _auth.currentUser?.uid;

  /// Get society document reference
  DocumentReference _societyRef(String societyId) {
    return _firestore.collection('societies').doc(societyId);
  }

  /// Get members subcollection reference
  CollectionReference _membersRef(String societyId) {
    return _societyRef(societyId).collection('members');
  }

  /// Get member document reference
  DocumentReference _memberRef(String societyId, String uid) {
    return _membersRef(societyId).doc(uid);
  }

  /// Get notices subcollection reference
  CollectionReference _noticesRef(String societyId) {
    return _societyRef(societyId).collection('notices');
  }

  /// Get complaints subcollection reference
  CollectionReference _complaintsRef(String societyId) {
    return _societyRef(societyId).collection('complaints');
  }

  /// Get flats subcollection reference
  CollectionReference _flatsRef(String societyId) {
    return _societyRef(societyId).collection('flats');
  }

  /// Get visitors subcollection reference
  CollectionReference _visitorsRef(String societyId) {
    return _societyRef(societyId).collection('visitors');
  }

  /// Get society codes collection reference
  CollectionReference get _societyCodesRef => _firestore.collection('societyCodes');

  // ============================================
  // SOCIETY OPERATIONS
  // ============================================

  /// Create a new society
  Future<Map<String, dynamic>> createSociety({
    required String societyId,
    required String code,
    required String name,
    String? city,
    String? state,
    required String createdByUid,
  }) async {
    try {
      final societyData = {
        'name': name,
        'code': code,
        'city': city,
        'state': state,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
        'createdByUid': createdByUid,
      };

      // Create society document
      await _societyRef(societyId).set(societyData);

      // Create society code mapping
      await _societyCodesRef.doc(code).set({
        'societyId': societyId,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
        'createdByUid': createdByUid,
      });

      AppLogger.i('Society created', data: {'societyId': societyId, 'code': code});
      return societyData;
    } catch (e, stackTrace) {
      AppLogger.e('Error creating society', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Get society by code
  Future<String?> getSocietyIdByCode(String code) async {
    try {
      final doc = await _societyCodesRef.doc(code).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null && data['active'] == true) {
          return data['societyId'] as String?;
        }
      }
      return null;
    } catch (e, stackTrace) {
      AppLogger.e('Error getting society by code', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Get society document
  Future<Map<String, dynamic>?> getSociety(String societyId) async {
    try {
      final doc = await _societyRef(societyId).get();
      if (doc.exists) {
        return doc.data() as Map<String, dynamic>?;
      }
      return null;
    } catch (e, stackTrace) {
      AppLogger.e('Error getting society', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  // ============================================
  // MEMBER OPERATIONS
  // ============================================

  /// Create or update member
  Future<void> setMember({
    required String societyId,
    required String uid,
    required String systemRole, // "admin" | "guard" | "resident"
    String? societyRole, // "president" | "secretary" | "treasurer" | "committee" | null
    required String name,
    String? phone,
    String? flatNo,
    bool active = true,
  }) async {
    try {
      await _memberRef(societyId, uid).set({
        'uid': uid,
        'systemRole': systemRole,
        'societyRole': societyRole,
        'name': name,
        'phone': phone,
        'flatNo': flatNo,
        'active': active,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      AppLogger.i('Member set', data: {
        'societyId': societyId,
        'uid': uid,
        'systemRole': systemRole,
      });
    } catch (e, stackTrace) {
      AppLogger.e('Error setting member', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Get member document
  Future<Map<String, dynamic>?> getMember({
    required String societyId,
    required String uid,
  }) async {
    try {
      final doc = await _memberRef(societyId, uid).get();
      if (doc.exists) {
        return doc.data() as Map<String, dynamic>?;
      }
      return null;
    } catch (e, stackTrace) {
      AppLogger.e('Error getting member', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Get current user's membership (checks all societies)
  Future<Map<String, dynamic>?> getCurrentUserMembership() async {
    final uid = currentUid;
    if (uid == null) return null;

    try {
      // Query all societies for this user's membership
      final societiesSnapshot = await _firestore.collection('societies').get();
      
      for (var societyDoc in societiesSnapshot.docs) {
        final memberDoc = await _membersRef(societyDoc.id).doc(uid).get();
        if (memberDoc.exists) {
          final memberData = memberDoc.data() as Map<String, dynamic>?;
          if (memberData?['active'] == true) {
            return {
              'societyId': societyDoc.id,
              'uid': uid,
              ...?memberData,
            };
          }
        }
      }
      return null;
    } catch (e, stackTrace) {
      AppLogger.e('Error getting current user membership', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  // ============================================
  // LOCATION METADATA (States & Cities)
  // ============================================

  /// Get list of states from Firestore (dynamic).
  /// Expected structure:
  /// Collection: states
  ///   - docId: stateId (e.g. RJ)
  ///   - fields: { name: \"Rajasthan\" }
  Future<List<Map<String, String>>> getStatesList() async {
    try {
      final snapshot = await _firestore.collection('states').orderBy('name').get();
      if (snapshot.docs.isEmpty) {
        // Fallback basic list if no config in Firestore
        final fallback = [
          {'id': 'RJ', 'name': 'Rajasthan'},
          {'id': 'MH', 'name': 'Maharashtra'},
          {'id': 'KA', 'name': 'Karnataka'},
          {'id': 'DL', 'name': 'Delhi'},
          {'id': 'GJ', 'name': 'Gujarat'},
          {'id': 'UP', 'name': 'Uttar Pradesh'},
          {'id': 'MP', 'name': 'Madhya Pradesh'},
        ];
        AppLogger.w('No states found in Firestore, using fallback list', data: {'count': fallback.length});
        return fallback;
      }
      final states = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final name = (data['name'] as String?) ?? doc.id;
        return {'id': doc.id, 'name': name};
      }).toList();
      AppLogger.i('States fetched from Firestore', data: {'count': states.length});
      return states;
    } catch (e, stackTrace) {
      AppLogger.e('Error getting states list', error: e, stackTrace: stackTrace);
      // On error, still return fallback so UI works
      final fallback = [
        {'id': 'RJ', 'name': 'Rajasthan'},
        {'id': 'MH', 'name': 'Maharashtra'},
        {'id': 'KA', 'name': 'Karnataka'},
        {'id': 'DL', 'name': 'Delhi'},
        {'id': 'GJ', 'name': 'Gujarat'},
        {'id': 'UP', 'name': 'Uttar Pradesh'},
        {'id': 'MP', 'name': 'Madhya Pradesh'},
      ];
      return fallback;
    }
  }

  /// Get cities for a given state from Firestore (dynamic).
  /// Expected structure:
  /// Collection: states/{stateId}/cities
  ///   - fields: { name: \"Jaipur\" }
  Future<List<Map<String, String>>> getCitiesForState(String stateId) async {
    try {
      final snapshot = await _firestore
          .collection('states')
          .doc(stateId)
          .collection('cities')
          .orderBy('name')
          .get();
      if (snapshot.docs.isEmpty) {
        // Fallback small list if no config in Firestore
        final fallback = [
          {'id': 'CITY1', 'name': 'Jaipur'},
          {'id': 'CITY2', 'name': 'Mumbai'},
          {'id': 'CITY3', 'name': 'Bengaluru'},
        ];
        AppLogger.w('No cities found for state, using fallback', data: {
          'stateId': stateId,
          'count': fallback.length,
        });
        return fallback;
      }
      final cities = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final name = (data['name'] as String?) ?? doc.id;
        return {'id': doc.id, 'name': name};
      }).toList();
      AppLogger.i('Cities fetched from Firestore', data: {
        'stateId': stateId,
        'count': cities.length,
      });
      return cities;
    } catch (e, stackTrace) {
      AppLogger.e('Error getting cities for state', error: e, stackTrace: stackTrace);
      // On error, still return fallback so UI is usable
      final fallback = [
        {'id': 'CITY1', 'name': 'Jaipur'},
        {'id': 'CITY2', 'name': 'Mumbai'},
        {'id': 'CITY3', 'name': 'Bengaluru'},
      ];
      return fallback;
    }
  }

  // ============================================
  // NOTICE OPERATIONS
  // ============================================

  /// Create notice
  Future<String> createNotice({
    required String societyId,
    required String title,
    required String content,
    required String noticeType,
    required String priority,
    required String createdByUid,
    required String createdByName,
    bool pinned = false,
    String? targetRole, // "all" | "admin" | "guard" | "resident"
    Timestamp? expiryAt,
  }) async {
    try {
      final noticeRef = _noticesRef(societyId).doc();
      await noticeRef.set({
        'title': title,
        'content': content,
        'noticeType': noticeType,
        'priority': priority,
        'pinned': pinned,
        'status': 'active',
        'targetRole': targetRole ?? 'all',
        'expiryAt': expiryAt,
        'createdByUid': createdByUid,
        'createdByName': createdByName,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      AppLogger.i('Notice created', data: {'noticeId': noticeRef.id, 'societyId': societyId});
      return noticeRef.id;
    } catch (e, stackTrace) {
      AppLogger.e('Error creating notice', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Get notices
  Future<List<Map<String, dynamic>>> getNotices({
    required String societyId,
    bool activeOnly = true,
    String? targetRole,
  }) async {
    try {
      Query query = _noticesRef(societyId);

      if (activeOnly) {
        query = query.where('status', isEqualTo: 'active');
        
        // Filter by expiry date if activeOnly
        final now = Timestamp.now();
        query = query.where('expiryAt', isGreaterThan: now);
      }

      if (targetRole != null) {
        query = query.where('targetRole', whereIn: ['all', targetRole]);
      }

      query = query.orderBy('pinned', descending: true)
          .orderBy('createdAt', descending: true);

      final snapshot = await query.get();
      
      final notices = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'notice_id': doc.id,
          ...data,
          'created_at': (data['createdAt'] as Timestamp?)?.toDate().toIso8601String(),
          'expiry_date': (data['expiryAt'] as Timestamp?)?.toDate().toIso8601String(),
        };
      }).toList();

      AppLogger.i('Notices fetched', data: {'count': notices.length, 'societyId': societyId});
      return notices;
    } catch (e, stackTrace) {
      AppLogger.e('Error getting notices', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Update notice status
  Future<void> updateNoticeStatus({
    required String societyId,
    required String noticeId,
    required bool isActive,
  }) async {
    try {
      await _noticesRef(societyId).doc(noticeId).update({
        'status': isActive ? 'active' : 'inactive',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      AppLogger.i('Notice status updated', data: {'noticeId': noticeId, 'isActive': isActive});
    } catch (e, stackTrace) {
      AppLogger.e('Error updating notice status', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Delete notice (soft delete by setting status to inactive)
  Future<void> deleteNotice({
    required String societyId,
    required String noticeId,
  }) async {
    try {
      await _noticesRef(societyId).doc(noticeId).update({
        'status': 'inactive',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      AppLogger.i('Notice deleted', data: {'noticeId': noticeId});
    } catch (e, stackTrace) {
      AppLogger.e('Error deleting notice', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // ============================================
  // COMPLAINT OPERATIONS
  // ============================================

  /// Create complaint
  Future<String> createComplaint({
    required String societyId,
    required String flatNo,
    required String residentUid,
    required String residentName,
    required String category,
    String? title,
    required String description,
  }) async {
    try {
      final complaintRef = _complaintsRef(societyId).doc();
      await complaintRef.set({
        'flatNo': flatNo,
        'residentUid': residentUid,
        'residentName': residentName,
        'category': category,
        'title': title,
        'description': description,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      AppLogger.i('Complaint created', data: {'complaintId': complaintRef.id, 'societyId': societyId});
      return complaintRef.id;
    } catch (e, stackTrace) {
      AppLogger.e('Error creating complaint', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Get resident complaints
  Future<List<Map<String, dynamic>>> getResidentComplaints({
    required String societyId,
    required String flatNo,
    String? residentUid,
  }) async {
    try {
      Query query = _complaintsRef(societyId).where('flatNo', isEqualTo: flatNo);
      
      if (residentUid != null) {
        query = query.where('residentUid', isEqualTo: residentUid);
      }

      query = query.orderBy('createdAt', descending: true);

      final snapshot = await query.get();
      
      final complaints = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'complaint_id': doc.id,
          ...data,
          'created_at': (data['createdAt'] as Timestamp?)?.toDate().toIso8601String(),
          'updated_at': (data['updatedAt'] as Timestamp?)?.toDate().toIso8601String(),
          'resolved_at': (data['resolvedAt'] as Timestamp?)?.toDate().toIso8601String(),
        };
      }).toList();

      AppLogger.i('Resident complaints fetched', data: {'count': complaints.length});
      return complaints;
    } catch (e, stackTrace) {
      AppLogger.e('Error getting resident complaints', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Get all complaints (admin)
  Future<List<Map<String, dynamic>>> getAllComplaints({
    required String societyId,
    String? status,
  }) async {
    try {
      Query query = _complaintsRef(societyId);
      
      if (status != null && status.isNotEmpty) {
        query = query.where('status', isEqualTo: status);
      }

      query = query.orderBy('createdAt', descending: true);

      final snapshot = await query.get();
      
      final complaints = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'complaint_id': doc.id,
          ...data,
          'created_at': (data['createdAt'] as Timestamp?)?.toDate().toIso8601String(),
          'updated_at': (data['updatedAt'] as Timestamp?)?.toDate().toIso8601String(),
          'resolved_at': (data['resolvedAt'] as Timestamp?)?.toDate().toIso8601String(),
        };
      }).toList();

      AppLogger.i('All complaints fetched', data: {'count': complaints.length});
      return complaints;
    } catch (e, stackTrace) {
      AppLogger.e('Error getting all complaints', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Update complaint status
  Future<void> updateComplaintStatus({
    required String societyId,
    required String complaintId,
    required String status,
    String? resolvedByUid,
    String? resolvedByName,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (status == 'resolved' && resolvedByUid != null) {
        updateData['resolvedAt'] = FieldValue.serverTimestamp();
        updateData['resolvedByUid'] = resolvedByUid;
        if (resolvedByName != null) {
          updateData['resolvedByName'] = resolvedByName;
        }
      }

      await _complaintsRef(societyId).doc(complaintId).update(updateData);
      AppLogger.i('Complaint status updated', data: {'complaintId': complaintId, 'status': status});
    } catch (e, stackTrace) {
      AppLogger.e('Error updating complaint status', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // ============================================
  // ADMIN STATS OPERATIONS
  // ============================================

  /// Get admin dashboard stats
  Future<Map<String, dynamic>> getAdminStats({
    required String societyId,
  }) async {
    try {
      // Get counts from subcollections
      final membersSnapshot = await _membersRef(societyId).where('active', isEqualTo: true).get();
      final flatsSnapshot = await _flatsRef(societyId).where('active', isEqualTo: true).get();
      
      // Count by systemRole
      int totalResidents = 0;
      int totalGuards = 0;
      for (var doc in membersSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null) {
          if (data['systemRole'] == 'resident') totalResidents++;
          if (data['systemRole'] == 'guard') totalGuards++;
        }
      }

      // Get today's visitors count
      final now = Timestamp.now();
      final startOfDay = Timestamp.fromDate(DateTime(now.toDate().year, now.toDate().month, now.toDate().day));
      final visitorsSnapshot = await _visitorsRef(societyId)
          .where('createdAt', isGreaterThanOrEqualTo: startOfDay)
          .get();
      
      int visitorsToday = visitorsSnapshot.docs.length;
      int pendingApprovals = visitorsSnapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        return data != null && data['status'] == 'pending';
      }).length;
      int approvedToday = visitorsSnapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        return data != null && data['status'] == 'approved';
      }).length;

      final stats = {
        'total_residents': totalResidents,
        'total_guards': totalGuards,
        'total_flats': flatsSnapshot.docs.length,
        'visitors_today': visitorsToday,
        'pending_approvals': pendingApprovals,
        'approved_today': approvedToday,
      };

      AppLogger.i('Admin stats fetched', data: stats);
      return stats;
    } catch (e, stackTrace) {
      AppLogger.e('Error getting admin stats', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }
}
