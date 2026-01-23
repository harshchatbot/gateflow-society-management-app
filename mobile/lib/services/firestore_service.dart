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
  /// Create or update member
  Future<void> setMember({
    required String societyId,
    required String uid,
    required String systemRole, // "admin" | "guard" | "resident" | "super_admin"
    String? societyRole, // "president" | "secretary" | "treasurer" | "committee" | null
    required String name,
    String? phone,
    String? flatNo,
    bool active = true,
  }) async {
  try {
    // --------------------------------------------
    // 1) SOCIETY MEMBER DOC (source of truth)
    // societies/{societyId}/members/{uid}
    // --------------------------------------------
    await _memberRef(societyId, uid).set({
      'uid': uid,
      'systemRole': systemRole,
      'societyRole': societyRole,
      'name': name,
      'phone': phone,
      'flatNo': flatNo,
      'active': active,

      // ✅ createdAt should not be overwritten repeatedly
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // --------------------------------------------
    // 2) ROOT POINTER (members/{uid})
    // Used for login resolution in your old flow.
    //
    // IMPORTANT:
    // Your current rules ONLY allow the user to write their own pointer doc.
    // During bulk upload (admin writing new user's pointer) it will be denied.
    //
    // So we try it, and if permission denied -> skip without failing whole upload.
    // --------------------------------------------
    try {
      await _firestore.collection('members').doc(uid).set({
        'uid': uid,
        'societyId': societyId,
        'systemRole': systemRole,
        'societyRole': societyRole,
        'active': active,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      // ✅ Don't block society member creation if root pointer is forbidden
      // This will happen for bulk upload unless you update rules.
      final msg = e.toString();
      final isPermissionDenied =
          msg.contains('permission-denied') || msg.contains('PERMISSION_DENIED');

      if (isPermissionDenied) {
        AppLogger.i('Root pointer write skipped (permission-denied)', data: {
          'uid': uid,
          'societyId': societyId,
        });
      } else {
        // if it's some other error, rethrow
        rethrow;
      }
    }

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


  

  // ============================================
  // LOCATION METADATA (States & Cities)
  // ============================================

  /// Get list of states from Firestore (dynamic).
  /// Expected structure:
  /// Collection: states
  ///   - docId: stateId (e.g. RJ)
  ///   - fields: { name: \"Rajasthan\" }
  // Get current user's membership using ROOT POINTER doc: members/{uid}
// ثم (optional) validate against societies/{societyId}/members/{uid}
Future<Map<String, dynamic>?> getCurrentUserMembership() async {
  final uid = currentUid;
  if (uid == null) return null;

  try {
    // 1) Read root pointer: members/{uid}
    final pointerDoc =
        await _firestore.collection('members').doc(uid).get();

    if (!pointerDoc.exists) {
      AppLogger.w('Membership pointer not found', data: {'uid': uid});
      return null;
    }

    final pointer = pointerDoc.data() as Map<String, dynamic>? ?? {};

    // Support both active/status styles (depending on your schema)
    final bool isActive = pointer['active'] == true ||
        (pointer['status']?.toString().toUpperCase() == 'ACTIVE');

    if (!isActive) {
      AppLogger.w('Membership pointer inactive', data: {'uid': uid, ...pointer});
      return null;
    }

    final societyId = pointer['societyId']?.toString();
    if (societyId == null || societyId.isEmpty) {
      AppLogger.e('Membership pointer missing societyId', error: pointer);
      return null;
    }

    // 2) Optional: validate actual society membership doc exists & active
    // This is useful if pointer exists but society member doc got deleted.
    final societyMemberDoc = await _firestore
        .collection('societies')
        .doc(societyId)
        .collection('members')
        .doc(uid)
        .get();

    if (!societyMemberDoc.exists) {
      AppLogger.w(
        'Society member doc missing though pointer exists',
        data: {'uid': uid, 'societyId': societyId},
      );
      return null;
    }

    final societyMember = societyMemberDoc.data() as Map<String, dynamic>? ?? {};

    final bool societyActive = societyMember['active'] == true ||
        (societyMember['status']?.toString().toUpperCase() == 'ACTIVE');

    if (!societyActive) {
      AppLogger.w(
        'Society member doc inactive',
        data: {'uid': uid, 'societyId': societyId, ...societyMember},
      );
      return null;
    }

    final result = {
      'uid': uid,
      'societyId': societyId,
      ...societyMember, // prefer society member fields as source of truth
      // Keep pointer fields too if you want:
      // '_pointer': pointer,
    };

    AppLogger.i('Current user membership resolved (pointer)', data: result);
    return result;
  } catch (e, stackTrace) {
    AppLogger.e(
      'Error getting current user membership (pointer)',
      error: e,
      stackTrace: stackTrace,
    );
    return null;
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

  Future<List<Map<String, String>>> getStatesList() async {
  try {
    final snapshot = await _firestore
        .collection('states')
        .orderBy('name')
        .get();

    if (snapshot.docs.isEmpty) {
      final fallback = [
        {'id': 'RJ', 'name': 'Rajasthan'},
        {'id': 'MH', 'name': 'Maharashtra'},
        {'id': 'KA', 'name': 'Karnataka'},
        {'id': 'DL', 'name': 'Delhi'},
      ];
      AppLogger.w('No states found, using fallback', data: {'count': fallback.length});
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

    // fallback on error
    return [
      {'id': 'RJ', 'name': 'Rajasthan'},
      {'id': 'MH', 'name': 'Maharashtra'},
      {'id': 'KA', 'name': 'Karnataka'},
      {'id': 'DL', 'name': 'Delhi'},
    ];
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

  Future<void> createInvite({
  required String societyId,
  required String email,
  required String systemRole, // admin|guard|resident
  String? societyRole,
  String? flatNo,
}) async {
  final cleanedEmail = email.trim().toLowerCase();
  final ref = _firestore
      .collection('societies')
      .doc(societyId)
      .collection('invites')
      .doc();

  await ref.set({
    'email': cleanedEmail,
    'systemRole': systemRole.toLowerCase(),
    'societyRole': societyRole,
    'flatNo': flatNo,
    'status': 'pending',
    'active': true,
    'createdAt': FieldValue.serverTimestamp(),
  });

  AppLogger.i('Invite created', data: {
    'societyId': societyId,
    'email': cleanedEmail,
    'systemRole': systemRole,
  });
}



}
