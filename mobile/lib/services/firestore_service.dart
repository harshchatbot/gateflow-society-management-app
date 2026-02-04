import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/app_logger.dart';
import 'firebase_auth_service.dart';

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

  /// Get violations subcollection reference (parking / fire-lane etc. - private, no names)
  CollectionReference _violationsRef(String societyId) {
    return _societyRef(societyId).collection('violations');
  }

  /// Get flats subcollection reference
  CollectionReference _flatsRef(String societyId) {
    return _societyRef(societyId).collection('flats');
  }

  /// List active flats/units for a society (for guard dropdown when creating visitor).
  /// Returns list of { id, flatNo } sorted by flatNo.
  Future<List<Map<String, dynamic>>> getSocietyFlats(String societyId) async {
    try {
      final snapshot =
          await _flatsRef(societyId).where('active', isEqualTo: true).get();
      final list = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final flatNo =
            (data['flatNo'] ?? data['flat_no'] ?? data['label'] ?? doc.id)
                .toString()
                .trim();
        return {'id': doc.id, 'flatNo': flatNo.isEmpty ? doc.id : flatNo};
      }).toList();
      list.sort(
          (a, b) => (a['flatNo'] as String).compareTo(b['flatNo'] as String));
      return list;
    } catch (e, st) {
      AppLogger.e('Error getting society flats', error: e, stackTrace: st);
      return [];
    }
  }

  /// Get visitors subcollection reference
  CollectionReference _visitorsRef(String societyId) {
    return _societyRef(societyId).collection('visitors');
  }

  /// Get society codes collection reference
  CollectionReference get _societyCodesRef =>
      _firestore.collection('societyCodes');

  /// Guard join codes (6-digit, 24h). Document ID = code.
  CollectionReference get _guardJoinCodesRef =>
      _firestore.collection('guard_join_codes');

  /// unique_phones/{phoneHash} - enforces one active account per phone.
  /// Doc: { uid, updatedAt }. Do not store plaintext phone.
  static const String _uniquePhonesCollection = 'unique_phones';

  /// Stable hash for phone (E.164) to use as doc id. No plaintext in Firestore.
  static String _phoneHash(String normalizedE164) {
    final bytes = utf8.encode(normalizedE164.trim());
    return sha256.convert(bytes).toString();
  }

  /// Returns true if [normalizedE164] is available (no other ACTIVE member has it).
  /// Same uid or deactivated member allows reuse.
  Future<bool> isPhoneAvailableForUser({
    required String normalizedE164,
    required String forUid,
  }) async {
    final hash = _phoneHash(normalizedE164);
    try {
      final doc =
          await _firestore.collection(_uniquePhonesCollection).doc(hash).get();
      if (!doc.exists) return true;
      final data = doc.data() ?? {};
      final existingUid = data['uid']?.toString();
      if (existingUid == null || existingUid == forUid) return true;
      // Another uid: check if that member is active
      final pointer =
          await _firestore.collection('members').doc(existingUid).get();
      if (!pointer.exists) return true;
      final pointerData = pointer.data() ?? {};
      final active = pointerData['active'];
      if (active == true) return false;
      return true;
    } catch (e, st) {
      AppLogger.e('Error checking phone availability',
          error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Updates member phone in society doc, root pointer, and unique_phones.
  /// Call after linking phone to Firebase user (login or profile link).
  Future<void> setMemberPhone({
    required String societyId,
    required String uid,
    required String normalizedE164,
  }) async {
    final hash = _phoneHash(normalizedE164);
    try {
      final batch = _firestore.batch();
      final memberRef = _memberRef(societyId, uid);
      batch.set(
          memberRef,
          {'phone': normalizedE164, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true));
      final rootRef = _firestore.collection('members').doc(uid);
      batch.set(
          rootRef,
          {'phone': normalizedE164, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true));
      final uniqueRef =
          _firestore.collection(_uniquePhonesCollection).doc(hash);
      batch.set(
          uniqueRef, {'uid': uid, 'updatedAt': FieldValue.serverTimestamp()});
      await batch.commit();
      AppLogger.i('Member phone set',
          data: {'uid': uid, 'societyId': societyId});
    } catch (e, st) {
      AppLogger.e('Error setting member phone', error: e, stackTrace: st);
      rethrow;
    }
  }

  // ============================================
  // GUARD JOIN CODE (6-digit, replaces QR)
  // ============================================

  /// Create a 6-digit guard join code for the society. Valid 24 hours.
  /// Returns the code string (e.g. "847291") or null on failure.
  Future<String?> createGuardJoinCode(String societyId) async {
    final expiry = DateTime.now().add(const Duration(hours: 24));
    final code = (100000 + Random().nextInt(900000)).toString();
    final ref = _guardJoinCodesRef.doc(code);
    try {
      await ref.set({
        'societyId': societyId,
        'exp': Timestamp.fromDate(expiry),
        'createdAt': FieldValue.serverTimestamp(),
      });
      AppLogger.i('Guard join code created',
          data: {'code': code, 'societyId': societyId});
      return code;
    } catch (e, stackTrace) {
      AppLogger.e('Error creating guard join code',
          error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Look up a 6-digit guard join code. Returns societyId if valid and not expired, else null.
  Future<String?> getGuardJoinCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.length != 6 || int.tryParse(trimmed) == null) return null;
    try {
      final doc = await _guardJoinCodesRef.doc(trimmed).get();
      if (!doc.exists) return null;
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return null;
      final exp = data['exp'];
      if (exp is Timestamp && DateTime.now().isAfter(exp.toDate())) return null;
      return data['societyId'] as String?;
    } catch (e, stackTrace) {
      AppLogger.e('Error getting guard join code',
          error: e, stackTrace: stackTrace);
      return null;
    }
  }

  // ============================================
  // SOCIETY OPERATIONS
  // ============================================

  /// Default modules for new societies (all enabled). Controlled via DB; no UI toggles.
  static Map<String, bool> get defaultSocietyModules => {
        'visitor_management': true,
        'complaints': true,
        'notices': true,
        'violations': true,
        'sos': true,
      };

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
        'modules': defaultSocietyModules,
      };

      // Create society document
      await _societyRef(societyId).set(societyData);

      // Create society code mapping (normalize to uppercase for consistency)
      final normalizedCode = code.trim().toUpperCase();
      await _societyCodesRef.doc(normalizedCode).set({
        'societyId': societyId,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
        'createdByUid': createdByUid,
      });

      AppLogger.i('Society created',
          data: {'societyId': societyId, 'code': code});
      return societyData;
    } catch (e, stackTrace) {
      AppLogger.e('Error creating society', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // ============================================
  // PUBLIC SOCIETY DIRECTORY (Resident onboarding)
  // ============================================

  CollectionReference get _publicSocietiesRef =>
      _firestore.collection('public_societies');

  /// Prefix search for active public societies by nameLower.
  /// Scales with index: where(active==true) + orderBy(nameLower) + startAt/endAt.
  Future<List<Map<String, dynamic>>> searchPublicSocietiesByPrefix(
      String query) async {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return [];
    try {
      final snapshot = await _publicSocietiesRef
          .where('active', isEqualTo: true)
          .orderBy('nameLower')
          .startAt([trimmed])
          .endAt(['$trimmed\uf8ff'])
          .limit(25)
          .get();

      final societies = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        return {
          'id': doc.id,
          'name': (data['name'] as String?) ?? doc.id,
          'cityName': data['cityName'],
          'stateName': data['stateName'],
          'active': data['active'] ?? true,
        };
      }).toList();

      AppLogger.i('Public societies prefix search',
          data: {'query': trimmed, 'count': societies.length});
      return societies;
    } on FirebaseException catch (e, st) {
      if (e.code == 'failed-precondition') {
        AppLogger.e(
          'Missing index for searchPublicSocietiesByPrefix. '
          'Expected composite index on {active ASC, nameLower ASC}.',
          error: e,
          stackTrace: st,
          data: {'query': trimmed},
        );
      } else {
        AppLogger.e('Error searching public societies',
            error: e, stackTrace: st);
      }
      return [];
    } catch (e, st) {
      AppLogger.e('Error searching public societies (unknown)',
          error: e, stackTrace: st);
      return [];
    }
  }

  /// Updates nameLower on public_societies/{societyId} from current name.
  /// Call this after changing a society name so resident search by prefix works.
  /// Requires: caller must be admin of that society (enforced by rules).
  Future<void> updatePublicSocietyNameLower(String societyId) async {
    final docRef = _publicSocietiesRef.doc(societyId);
    final snapshot = await docRef.get();
    if (!snapshot.exists) {
      throw Exception('Public society not found: $societyId');
    }
    final data = snapshot.data() as Map<String, dynamic>? ?? {};
    final name = (data['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) {
      throw Exception('Public society has no name to derive nameLower');
    }
    final nameLower = name.toLowerCase();
    await docRef.update({'nameLower': nameLower});
    AppLogger.i('Public society nameLower updated',
        data: {'societyId': societyId, 'nameLower': nameLower});
  }

  /// List active units (villas/flats) for a public society.
  /// Collection: public_societies/{societyId}/units where active == true.
  Future<List<Map<String, dynamic>>> getPublicSocietyUnits(
      String societyId) async {
    try {
      final snapshot = await _publicSocietiesRef
          .doc(societyId)
          .collection('units')
          .where('active', isEqualTo: true)
          .orderBy('sortKey')
          .get();

      final units = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        return {
          'id': doc.id,
          'label': (data['label'] as String?) ?? doc.id,
          'type': data['type'] ?? 'FLAT',
          'active': data['active'] ?? true,
          'sortKey': data['sortKey'],
        };
      }).toList();

      AppLogger.i('Public units fetched',
          data: {'societyId': societyId, 'count': units.length});
      return units;
    } on FirebaseException catch (e, st) {
      if (e.code == 'failed-precondition') {
        AppLogger.e(
          'Missing index for getPublicSocietyUnits. '
          'Expected composite index on {active ASC, sortKey ASC}. '
          'If querying by type as well, also create {active ASC, type ASC, sortKey ASC}.',
          error: e,
          stackTrace: st,
          data: {'societyId': societyId},
        );
      } else {
        AppLogger.e('Error getting public society units',
            error: e, stackTrace: st);
      }
      return [];
    } catch (e, st) {
      AppLogger.e('Error getting public society units (unknown)',
          error: e, stackTrace: st);
      return [];
    }
  }

  /// Create or update a resident join request for the current user under
  /// public_societies/{societyId}/join_requests/{uid}.
  /// [residencyType] should be 'OWNER' or 'TENANT'.
  Future<void> createResidentJoinRequest({
    required String societyId,
    required String societyName,
    required String cityId,
    required String unitLabel,
    required String residencyType,
    required String name,
    required String phoneE164,
  }) async {
    final uid = currentUid;
    if (uid == null) {
      throw StateError('createResidentJoinRequest: currentUid is null');
    }

    try {
      final ref = _publicSocietiesRef
          .doc(societyId)
          .collection('join_requests')
          .doc(uid);

      await ref.set({
        'uid': uid,
        'societyId': societyId,
        'societyName': societyName,
        'cityId': cityId,
        'unitLabel': unitLabel,
        'residencyType': residencyType,
        'requestedRole': 'resident',
        'name': name,
        'phone': phoneE164,
        'status': 'PENDING',
        'createdAt': FieldValue.serverTimestamp(),
        'handledBy': null,
        'handledAt': null,
      }, SetOptions(merge: true));

      AppLogger.i('Resident join request created', data: {
        'uid': uid,
        'societyId': societyId,
        'unitLabel': unitLabel,
      });
    } catch (e, st) {
      AppLogger.e('Error creating resident join request',
          error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Get a resident join request for the current user for a known societyId.
  Future<Map<String, dynamic>?> getResidentJoinRequest({
    required String societyId,
  }) async {
    final uid = currentUid;
    if (uid == null) return null;
    try {
      final doc = await _publicSocietiesRef
          .doc(societyId)
          .collection('join_requests')
          .doc(uid)
          .get();
      if (!doc.exists) return null;
      final data = doc.data() ?? {};
      data['id'] = doc.id;
      return data;
    } catch (e, st) {
      AppLogger.e('Error getting resident join request',
          error: e, stackTrace: st);
      return null;
    }
  }

  /// For admin UI: list pending resident join requests for a society.
  Future<List<Map<String, dynamic>>> getResidentJoinRequestsForAdmin(
      String societyId) async {
    try {
      final snapshot = await _publicSocietiesRef
          .doc(societyId)
          .collection('join_requests')
          .where('requestedRole', isEqualTo: 'resident')
          .where('status', isEqualTo: 'PENDING')
          .orderBy('createdAt')
          .get();

      final list = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        return {
          'uid': data['uid'] ?? doc.id,
          'name': data['name'] ?? '',
          'phone': data['phone'] ?? '',
          'unitLabel': data['unitLabel'] ?? '',
          'createdAt': data['createdAt'],
        };
      }).toList();

      AppLogger.i('Resident join requests loaded',
          data: {'societyId': societyId, 'count': list.length});
      return list;
    } on FirebaseException catch (e, st) {
      if (e.code == 'failed-precondition') {
        AppLogger.e(
          'Missing index for getResidentJoinRequestsForAdmin. '
          'Expected composite index on {requestedRole ASC, status ASC, createdAt DESC}.',
          error: e,
          stackTrace: st,
          data: {'societyId': societyId},
        );
      } else {
        AppLogger.e('Error getting resident join requests',
            error: e, stackTrace: st);
      }
      return [];
    } catch (e, st) {
      AppLogger.e(
        'Error getting resident join requests (unknown)',
        error: e,
        stackTrace: st,
      );
      return [];
    }
  }

  /// Approve resident join request: create active resident member and pointer,
  /// update join_request status, and ensure unique_phones mapping.
  Future<void> approveResidentJoinRequest({
    required String societyId,
    required String uid,
    required String unitLabel,
    required String name,
    required String phoneE164,
    required String handledByUid,
  }) async {
    final normalizedPhone =
        FirebaseAuthService.normalizePhoneForIndia(phoneE164);

    // Enforce unique phone before committing
    final available = await isPhoneAvailableForUser(
      normalizedE164: normalizedPhone,
      forUid: uid,
    );
    if (!available) {
      throw StateError(
        'This mobile number is already linked to another active account.',
      );
    }

    try {
      final batch = _firestore.batch();

      final memberRef = _societyRef(societyId).collection('members').doc(uid);
      final pointerRef = _firestore.collection('members').doc(uid);
      final joinRef = _publicSocietiesRef
          .doc(societyId)
          .collection('join_requests')
          .doc(uid);

      final now = FieldValue.serverTimestamp();

      batch.set(
          memberRef,
          {
            'uid': uid,
            'societyId': societyId,
            'systemRole': 'resident',
            'active': true,
            'name': name,
            'phone': normalizedPhone,
            'flatNo': unitLabel,
            'updatedAt': now,
            'createdAt': now,
          },
          SetOptions(merge: true));

      batch.set(
          pointerRef,
          {
            'uid': uid,
            'societyId': societyId,
            'systemRole': 'resident',
            'active': true,
            'name': name,
            'phone': normalizedPhone,
            'flatNo': unitLabel,
            'updatedAt': now,
            'createdAt': now,
          },
          SetOptions(merge: true));

      batch.set(
          joinRef,
          {
            'status': 'APPROVED',
            'handledBy': handledByUid,
            'handledAt': now,
          },
          SetOptions(merge: true));

      await batch.commit();

      // Ensure unique_phones + normalized phone everywhere.
      await setMemberPhone(
        societyId: societyId,
        uid: uid,
        normalizedE164: normalizedPhone,
      );

      AppLogger.i('Resident join request approved', data: {
        'uid': uid,
        'societyId': societyId,
        'unitLabel': unitLabel,
      });
    } catch (e, st) {
      AppLogger.e('Error approving resident join request',
          error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Reject resident join request: update status only.
  Future<void> rejectResidentJoinRequest({
    required String societyId,
    required String uid,
    required String handledByUid,
  }) async {
    try {
      final ref = _publicSocietiesRef
          .doc(societyId)
          .collection('join_requests')
          .doc(uid);
      await ref.set({
        'status': 'REJECTED',
        'handledBy': handledByUid,
        'handledAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      AppLogger.i('Resident join request rejected',
          data: {'uid': uid, 'societyId': societyId});
    } catch (e, st) {
      AppLogger.e('Error rejecting resident join request',
          error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Get society by code
  /// Handles codes with or without SOC_ prefix (e.g., "AMARA" or "SOC_AMARA" both work)
  Future<String?> getSocietyIdByCode(String code) async {
    try {
      // Normalize code: strip SOC_ prefix if present, then uppercase
      String normalizedCode = code.trim().toUpperCase();

      // Remove SOC_ prefix if present (case-insensitive)
      if (normalizedCode.startsWith('SOC_')) {
        normalizedCode =
            normalizedCode.substring(4); // Remove "SOC_" (4 characters)
      }

      final doc = await _societyCodesRef.doc(normalizedCode).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null && data['active'] == true) {
          return data['societyId'] as String?;
        }
      }
      return null;
    } catch (e, stackTrace) {
      AppLogger.e('Error getting society by code',
          error: e, stackTrace: stackTrace);
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
    required String
        systemRole, // "admin" | "guard" | "resident" | "super_admin"
    String?
        societyRole, // "president" | "secretary" | "treasurer" | "committee" | null
    required String name,
    String? phone,
    String? email,
    String? flatNo,
    String? photoUrl,
    String? shiftTimings,
    bool active = true,
  }) async {
    try {
      // --------------------------------------------
      // 1) SOCIETY MEMBER DOC (source of truth)
      // societies/{societyId}/members/{uid}
      // Rules require request.resource.data.societyId == societyId for create.
      // --------------------------------------------
      await _memberRef(societyId, uid).set({
        'uid': uid,
        'societyId': societyId,
        'systemRole': systemRole,
        'societyRole': societyRole,
        'name': name,
        'phone': phone,
        'email': email,
        'flatNo': flatNo,
        'photoUrl': photoUrl,
        'shiftTimings': shiftTimings,
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
          if (phone != null) 'phone': phone,
          if (email != null) 'email': email,
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        // ✅ Don't block society member creation if root pointer is forbidden
        // This will happen for bulk upload unless you update rules.
        final msg = e.toString();
        final isPermissionDenied = msg.contains('permission-denied') ||
            msg.contains('PERMISSION_DENIED');

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
      final pointerDoc = await _firestore.collection('members').doc(uid).get();

      if (!pointerDoc.exists) {
        AppLogger.w('Membership pointer not found', data: {'uid': uid});
        return null;
      }

      final pointer = pointerDoc.data() ?? {};

      final societyId = pointer['societyId']?.toString();
      if (societyId == null || societyId.isEmpty) {
        AppLogger.e('Membership pointer missing societyId', error: pointer);
        return null;
      }

      // 2) Get actual society membership doc (even if inactive - needed for pending approval check)
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

      final societyMember = societyMemberDoc.data() ?? {};

      // Return membership even if inactive (caller can check active status)
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
      AppLogger.e('Error getting cities for state',
          error: e, stackTrace: stackTrace);
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
      final snapshot =
          await _firestore.collection('states').orderBy('name').get();

      if (snapshot.docs.isEmpty) {
        final fallback = [
          {'id': 'RJ', 'name': 'Rajasthan'},
          {'id': 'MH', 'name': 'Maharashtra'},
          {'id': 'KA', 'name': 'Karnataka'},
          {'id': 'DL', 'name': 'Delhi'},
        ];
        AppLogger.w('No states found, using fallback',
            data: {'count': fallback.length});
        return fallback;
      }

      final states = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final name = (data['name'] as String?) ?? doc.id;
        return {'id': doc.id, 'name': name};
      }).toList();

      AppLogger.i('States fetched from Firestore',
          data: {'count': states.length});
      return states;
    } catch (e, stackTrace) {
      AppLogger.e('Error getting states list',
          error: e, stackTrace: stackTrace);

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

      AppLogger.i('Notice created',
          data: {'noticeId': noticeRef.id, 'societyId': societyId});
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

      query = query
          .orderBy('pinned', descending: true)
          .orderBy('createdAt', descending: true);

      final snapshot = await query.get();

      final notices = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'notice_id': doc.id,
          ...data,
          'created_at':
              (data['createdAt'] as Timestamp?)?.toDate().toIso8601String(),
          'expiry_date':
              (data['expiryAt'] as Timestamp?)?.toDate().toIso8601String(),
        };
      }).toList();

      AppLogger.i('Notices fetched',
          data: {'count': notices.length, 'societyId': societyId});
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
      AppLogger.i('Notice status updated',
          data: {'noticeId': noticeId, 'isActive': isActive});
    } catch (e, stackTrace) {
      AppLogger.e('Error updating notice status',
          error: e, stackTrace: stackTrace);
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

  /// Create complaint (writes BOTH camelCase + snake_case for compatibility)
  /// [visibility] 'general' = visible to everyone; 'personal' = visible to admins & guards only
  /// [photoUrl] optional image URL (e.g. from Firebase Storage) for the complaint
  Future<String> createComplaint({
    required String societyId,
    required String flatNo,
    required String residentUid,
    required String residentName,
    required String category,
    String? title,
    required String description,
    String visibility = 'general',
    String? photoUrl,
  }) async {
    try {
      final complaintRef = _complaintsRef(societyId).doc();

      final normalizedFlat = flatNo.trim().toUpperCase();
      final now = FieldValue.serverTimestamp();
      final vis = visibility.trim().toLowerCase() == 'personal'
          ? 'personal'
          : 'general';

      final data = <String, dynamic>{
        // ✅ canonical (camelCase)
        'flatNo': normalizedFlat,
        'residentUid': residentUid,
        'residentName': residentName.trim(),
        'category': category.trim(),
        'title': title?.trim(),
        'description': description.trim(),
        'status': 'pending',
        'visibility': vis,
        'createdAt': now,
        'updatedAt': now,

        // ✅ compatibility (snake_case)
        'flat_no': normalizedFlat,
        'resident_uid': residentUid,
        'resident_name': residentName.trim(),
        'created_at': now,
        'updated_at': now,
        'society_id': societyId,
        'complaint_id': complaintRef.id,
      };
      if (photoUrl != null && photoUrl.isNotEmpty) {
        data['photoUrl'] = photoUrl;
        data['photo_url'] = photoUrl;
      }
      await complaintRef.set(data);

      AppLogger.i('Complaint created', data: {
        'complaintId': complaintRef.id,
        'societyId': societyId,
        'flatNo': normalizedFlat,
        'residentUid': residentUid,
      });

      return complaintRef.id;
    } catch (e, stackTrace) {
      AppLogger.e('Error creating complaint', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Get resident complaints (supports BOTH schemas).
  /// When residentUid is provided, queries only that resident's complaints (so read rule allows it for personal visibility).
  Future<List<Map<String, dynamic>>> getResidentComplaints({
    required String societyId,
    required String flatNo,
    String? residentUid,
  }) async {
    try {
      final normalizedFlat = flatNo.trim().toUpperCase();

      final QuerySnapshot snapshot;
      if (residentUid != null && residentUid.isNotEmpty) {
        // Query only this resident's complaints so Firestore read rule allows (own docs always readable)
        snapshot = await _complaintsRef(societyId)
            .where('residentUid', isEqualTo: residentUid)
            .orderBy('createdAt', descending: true)
            .limit(200)
            .get()
            .catchError((_) async {
          return await _complaintsRef(societyId)
              .where('residentUid', isEqualTo: residentUid)
              .limit(200)
              .get();
        });
      } else {
        snapshot = await _complaintsRef(societyId)
            .orderBy('createdAt', descending: true)
            .limit(200)
            .get()
            .catchError((_) async {
          return await _complaintsRef(societyId).limit(200).get();
        });
      }

      final results = <Map<String, dynamic>>[];

      for (final doc in snapshot.docs) {
        final data = (doc.data() as Map<String, dynamic>);

        final docFlat = (data['flatNo'] ?? data['flat_no'])
            ?.toString()
            .trim()
            .toUpperCase();
        final docResident =
            (data['residentUid'] ?? data['resident_uid'])?.toString();

        if (docFlat != normalizedFlat) continue;
        if (residentUid != null && docResident != residentUid) continue;

        final createdTs = (data['createdAt'] ?? data['created_at']);
        final updatedTs = (data['updatedAt'] ?? data['updated_at']);
        final resolvedTs = (data['resolvedAt'] ?? data['resolved_at']);

        results.add({
          'complaint_id': doc.id,

          // ✅ normalized output keys (snake_case for UI consistency)
          'society_id': societyId,
          'flat_no': docFlat,
          'resident_uid': docResident,
          'resident_name':
              (data['residentName'] ?? data['resident_name'])?.toString(),
          'category': data['category']?.toString(),
          'title': data['title']?.toString(),
          'description': data['description']?.toString(),
          'status': (data['status'] ?? 'pending')?.toString().toLowerCase(),
          'visibility': (data['visibility'] ?? 'general')?.toString(),

          // keep originals too (optional, harmless)
          ...data,

          'created_at': (createdTs is Timestamp)
              ? createdTs.toDate().toIso8601String()
              : null,
          'updated_at': (updatedTs is Timestamp)
              ? updatedTs.toDate().toIso8601String()
              : null,
          'resolved_at': (resolvedTs is Timestamp)
              ? resolvedTs.toDate().toIso8601String()
              : null,
        });
      }

      // ✅ Client-side sort fallback
      results.sort((a, b) {
        final aDate =
            DateTime.tryParse((a['created_at'] ?? '') as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
        final bDate =
            DateTime.tryParse((b['created_at'] ?? '') as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

      AppLogger.i('Resident complaints fetched',
          data: {'count': results.length});
      return results;
    } catch (e, stackTrace) {
      AppLogger.e('Error getting resident complaints',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Get all complaints (admin) (supports BOTH schemas)
  Future<List<Map<String, dynamic>>> getAllComplaints({
    required String societyId,
    String? status,
  }) async {
    try {
      final normalizedStatus = status?.trim().toLowerCase();

      final snapshot = await _complaintsRef(societyId)
          .orderBy('createdAt', descending: true)
          .limit(500)
          .get()
          .catchError((_) async {
        // Fallback if createdAt missing in some docs
        return await _complaintsRef(societyId).limit(500).get();
      });

      final results = <Map<String, dynamic>>[];

      for (final doc in snapshot.docs) {
        final data = (doc.data() as Map<String, dynamic>);
        final st = (data['status'] ?? 'pending')?.toString().toLowerCase();

        if (normalizedStatus != null &&
            normalizedStatus.isNotEmpty &&
            st != normalizedStatus) {
          continue;
        }

        final createdTs = (data['createdAt'] ?? data['created_at']);
        final updatedTs = (data['updatedAt'] ?? data['updated_at']);
        final resolvedTs = (data['resolvedAt'] ?? data['resolved_at']);

        results.add({
          'complaint_id': doc.id,

          // ✅ normalized output keys (snake_case)
          'society_id': societyId,
          'flat_no': (data['flatNo'] ?? data['flat_no'])
              ?.toString()
              .trim()
              .toUpperCase(),
          'resident_uid':
              (data['residentUid'] ?? data['resident_uid'])?.toString(),
          'resident_name':
              (data['residentName'] ?? data['resident_name'])?.toString(),
          'category': data['category']?.toString(),
          'title': data['title']?.toString(),
          'description': data['description']?.toString(),
          'status': st,
          'visibility': (data['visibility'] ?? 'general')?.toString(),

          ...data,

          'created_at': (createdTs is Timestamp)
              ? createdTs.toDate().toIso8601String()
              : null,
          'updated_at': (updatedTs is Timestamp)
              ? updatedTs.toDate().toIso8601String()
              : null,
          'resolved_at': (resolvedTs is Timestamp)
              ? resolvedTs.toDate().toIso8601String()
              : null,
        });
      }

      results.sort((a, b) {
        final aDate =
            DateTime.tryParse((a['created_at'] ?? '') as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
        final bDate =
            DateTime.tryParse((b['created_at'] ?? '') as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

      AppLogger.i('All complaints fetched', data: {'count': results.length});
      return results;
    } catch (e, stackTrace) {
      AppLogger.e('Error getting all complaints',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Update complaint status (updates BOTH schemas)
  Future<void> updateComplaintStatus({
    required String societyId,
    required String complaintId,
    required String status,
    String? resolvedByUid,
    String? resolvedByName,
    String? adminResponse,
  }) async {
    try {
      final normalizedStatus = status.trim().toLowerCase();

      final updateData = <String, dynamic>{
        // canonical
        'status': normalizedStatus,
        'updatedAt': FieldValue.serverTimestamp(),

        // compat
        'updated_at': FieldValue.serverTimestamp(),
      };

      // Store admin response if provided
      if (adminResponse != null && adminResponse.trim().isNotEmpty) {
        updateData['adminResponse'] = adminResponse.trim();
        updateData['admin_response'] = adminResponse.trim();
      }

      if (normalizedStatus == 'resolved' && resolvedByUid != null) {
        updateData['resolvedAt'] = FieldValue.serverTimestamp();
        updateData['resolved_at'] = FieldValue.serverTimestamp();

        updateData['resolvedByUid'] = resolvedByUid;
        updateData['resolved_by_uid'] = resolvedByUid;

        if (resolvedByName != null) {
          updateData['resolvedByName'] = resolvedByName;
          updateData['resolved_by_name'] = resolvedByName;
        }
      }

      await _complaintsRef(societyId).doc(complaintId).update(updateData);

      AppLogger.i('Complaint status updated',
          data: {'complaintId': complaintId, 'status': normalizedStatus});
    } catch (e, stackTrace) {
      AppLogger.e('Error updating complaint status',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // ============================================
  // VIOLATIONS (Parking / Fire-lane - private, no names)
  // Guard: own reports | Admin: full | Resident: only self (by flat)
  // ============================================

  /// Violation types
  static const String violationTypeParking = 'PARKING';
  static const String violationTypeFireLane = 'FIRE_LANE';
  static const String violationTypeOther = 'OTHER';

  Future<String> createViolation({
    required String societyId,
    required String guardUid,
    required String flatNo,
    required String violationType,
    String? note,
    String? photoUrl,
  }) async {
    try {
      final ref = _violationsRef(societyId).doc();
      final normalizedFlat = flatNo.trim().toUpperCase();
      final now = FieldValue.serverTimestamp();
      final type = violationType.trim().toUpperCase();
      final validType =
          type == 'FIRE_LANE' || type == 'PARKING' ? type : 'OTHER';

      await ref.set({
        'guardUid': guardUid,
        'flatNo': normalizedFlat,
        'violationType': validType,
        'note': note?.trim(),
        'photoUrl': photoUrl,
        'status': 'OPEN',
        'createdAt': now,
        'updatedAt': now,
      });
      AppLogger.i('Violation created',
          data: {'violationId': ref.id, 'societyId': societyId});
      return ref.id;
    } catch (e, stackTrace) {
      AppLogger.e('Error creating violation', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Guard: list violations reported by this guard
  Future<List<Map<String, dynamic>>> getViolationsByGuard({
    required String societyId,
    required String guardUid,
  }) async {
    try {
      final snapshot = await _violationsRef(societyId)
          .where('guardUid', isEqualTo: guardUid)
          .orderBy('createdAt', descending: true)
          .limit(200)
          .get();
      return _violationDocsToMaps(snapshot.docs, societyId);
    } catch (e, stackTrace) {
      AppLogger.e('Error getViolationsByGuard',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Resident: list violations for this flat only (no reporter name)
  Future<List<Map<String, dynamic>>> getViolationsByFlat({
    required String societyId,
    required String flatNo,
  }) async {
    try {
      final normalizedFlat = flatNo.trim().toUpperCase();
      final snapshot = await _violationsRef(societyId)
          .where('flatNo', isEqualTo: normalizedFlat)
          .orderBy('createdAt', descending: true)
          .limit(200)
          .get();
      return _violationDocsToMaps(snapshot.docs, societyId);
    } catch (e, stackTrace) {
      AppLogger.e('Error getViolationsByFlat',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Admin: list all violations (filter status/year/month in memory to avoid composite index)
  Future<List<Map<String, dynamic>>> getAllViolations({
    required String societyId,
    String? status,
    int? year,
    int? month,
  }) async {
    try {
      final snapshot = await _violationsRef(societyId)
          .orderBy('createdAt', descending: true)
          .limit(500)
          .get();
      var list = _violationDocsToMaps(snapshot.docs, societyId);
      if (status != null && status.isNotEmpty) {
        final st = status.trim().toUpperCase();
        list = list
            .where((m) => (m['status'] ?? '').toString().toUpperCase() == st)
            .toList();
      }
      if (year != null && month != null) {
        list = list.where((m) {
          final createdAt = m['created_at'];
          if (createdAt == null) return false;
          final dt = DateTime.tryParse(createdAt.toString());
          if (dt == null) return false;
          return dt.year == year && dt.month == month;
        }).toList();
      }
      return list;
    } catch (e, stackTrace) {
      AppLogger.e('Error getAllViolations', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  List<Map<String, dynamic>> _violationDocsToMaps(List docs, String societyId) {
    return docs.map<Map<String, dynamic>>((doc) {
      final d = doc as QueryDocumentSnapshot<Object?>;
      final data = d.data() as Map<String, dynamic>? ?? {};
      final createdAt = data['createdAt'];
      final updatedAt = data['updatedAt'];
      return {
        'violation_id': d.id,
        'society_id': societyId,
        'guard_uid': data['guardUid'],
        'flat_no': (data['flatNo'] ?? '').toString(),
        'violation_type': (data['violationType'] ?? 'OTHER').toString(),
        'note': data['note']?.toString(),
        'photo_url': data['photoUrl']?.toString(),
        'status': (data['status'] ?? 'OPEN').toString(),
        'created_at': createdAt is Timestamp
            ? (createdAt).toDate().toIso8601String()
            : createdAt?.toString(),
        'updated_at': updatedAt is Timestamp
            ? (updatedAt).toDate().toIso8601String()
            : updatedAt?.toString(),
        ...data,
      };
    }).toList();
  }

  /// Admin: stats for a month (anonymous summary - no names)
  /// Returns: total, byType (PARKING, FIRE_LANE, OTHER), repeatedFlatsCount, previousMonthRepeatedFlatsCount
  Future<Map<String, dynamic>> getViolationStatsForMonth({
    required String societyId,
    required int year,
    required int month,
  }) async {
    try {
      final start = DateTime(year, month, 1);
      final end =
          month < 12 ? DateTime(year, month + 1, 1) : DateTime(year + 1, 1, 1);
      final startTs = Timestamp.fromDate(start);
      final endTs = Timestamp.fromDate(end);

      final snapshot = await _violationsRef(societyId)
          .where('createdAt', isGreaterThanOrEqualTo: startTs)
          .where('createdAt', isLessThan: endTs)
          .get();

      final prevStart =
          month > 1 ? DateTime(year, month - 1, 1) : DateTime(year - 1, 12, 1);
      final prevEnd = start;
      final prevSnapshot = await _violationsRef(societyId)
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(prevStart))
          .where('createdAt', isLessThan: Timestamp.fromDate(prevEnd))
          .get();

      final byType = <String, int>{'PARKING': 0, 'FIRE_LANE': 0, 'OTHER': 0};
      final flatCountThisMonth = <String, int>{};
      final flatCountPrevMonth = <String, int>{};

      for (final doc in snapshot.docs) {
        final d = doc.data() as Map<String, dynamic>? ?? {};
        final t = (d['violationType'] ?? 'OTHER').toString().toUpperCase();
        byType[t] = (byType[t] ?? 0) + 1;
        final flat = (d['flatNo'] ?? '').toString();
        if (flat.isNotEmpty)
          flatCountThisMonth[flat] = (flatCountThisMonth[flat] ?? 0) + 1;
      }
      for (final doc in prevSnapshot.docs) {
        final d = doc.data() as Map<String, dynamic>? ?? {};
        final flat = (d['flatNo'] ?? '').toString();
        if (flat.isNotEmpty)
          flatCountPrevMonth[flat] = (flatCountPrevMonth[flat] ?? 0) + 1;
      }

      final repeatedThis = flatCountThisMonth.values.where((c) => c > 1).length;
      final repeatedPrev = flatCountPrevMonth.values.where((c) => c > 1).length;
      num reducedPercent = 0;
      if (repeatedPrev > 0) {
        reducedPercent =
            ((repeatedPrev - repeatedThis) / repeatedPrev * 100).round();
        if (reducedPercent < 0) reducedPercent = 0;
      }

      return {
        'total': snapshot.docs.length,
        'byType': byType,
        'parking': byType['PARKING'] ?? 0,
        'fireLane': byType['FIRE_LANE'] ?? 0,
        'other': byType['OTHER'] ?? 0,
        'repeatedFlatsCount': repeatedThis,
        'previousMonthRepeatedFlatsCount': repeatedPrev,
        'repeatedViolationsReducedPercent': reducedPercent,
      };
    } catch (e, stackTrace) {
      AppLogger.e('Error getViolationStatsForMonth',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Admin: update violation status (e.g. RESOLVED)
  Future<void> updateViolationStatus({
    required String societyId,
    required String violationId,
    required String status,
  }) async {
    try {
      await _violationsRef(societyId).doc(violationId).update({
        'status': status.trim().toUpperCase(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e, stackTrace) {
      AppLogger.e('Error updateViolationStatus',
          error: e, stackTrace: stackTrace);
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
      final membersSnapshot =
          await _membersRef(societyId).where('active', isEqualTo: true).get();
      final flatsSnapshot =
          await _flatsRef(societyId).where('active', isEqualTo: true).get();

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
      final startOfDay = Timestamp.fromDate(
          DateTime(now.toDate().year, now.toDate().month, now.toDate().day));
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
      AppLogger.e('Error getting admin stats',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Visitor counts per day for the last 7 days (for dashboard chart).
  /// Returns list of 7 counts: [day-6, day-5, ..., today] (local calendar days).
  /// [guardId] if set filters to that guard's entries only; otherwise society-wide.
  /// [flatNo] if set filters to visitors for that flat (for resident dashboard).
  Future<List<int>> getVisitorCountsByDayLast7Days({
    required String societyId,
    String? guardId,
    String? flatNo,
  }) async {
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final sevenDaysAgoStart = todayStart.subtract(const Duration(days: 6));

      final snapshot = guardId != null && guardId.isNotEmpty
          ? await _visitorsRef(societyId)
              .where('guard_uid', isEqualTo: guardId)
              .limit(400)
              .get()
          : await _visitorsRef(societyId).limit(400).get();

      final flatNorm = (flatNo ?? '').trim().toUpperCase();

      final counts = List<int>.filled(7, 0);
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (data == null) continue;
        final map = data as Map<String, dynamic>;
        if (flatNorm.isNotEmpty) {
          final docFlat = (map['flatNo'] ?? map['flat_no'] ?? '')
              .toString()
              .trim()
              .toUpperCase();
          if (docFlat != flatNorm) continue;
        }
        final createdAt = map['createdAt'];
        if (createdAt == null) continue;
        DateTime date;
        if (createdAt is Timestamp) {
          date = createdAt.toDate().toLocal();
        } else if (createdAt is DateTime) {
          date = createdAt.toLocal();
        } else {
          continue;
        }
        final dayStart = DateTime(date.year, date.month, date.day);
        if (dayStart.isBefore(sevenDaysAgoStart) ||
            dayStart.isAfter(todayStart)) continue;
        final index = dayStart.difference(sevenDaysAgoStart).inDays;
        if (index >= 0 && index < 7) {
          counts[index]++;
        }
      }

      AppLogger.i('Visitor counts by day (last 7)',
          data: {'counts': counts, 'guardId': guardId, 'flatNo': flatNo});
      return counts;
    } catch (e, stackTrace) {
      AppLogger.e('Error getVisitorCountsByDayLast7Days',
          error: e, stackTrace: stackTrace);
      return List<int>.filled(7, 0);
    }
  }

  /// ============================================
  /// SOS / Emergency Requests
  /// ============================================

  Future<void> updateSosStatus({
    required String societyId,
    required String sosId,
    required String status,
  }) async {
    try {
      final uid = currentUid;
      Map<String, dynamic>? membership;
      if (uid != null) {
        membership = await getCurrentUserMembership();
      }

      final actorName = membership?['name']?.toString();
      final actorRole = membership?['systemRole']?.toString();
      final statusUpper = status.toUpperCase();

      final ref = _firestore
          .collection('societies')
          .doc(societyId)
          .collection('sos_requests')
          .doc(sosId);

      final updateData = <String, dynamic>{
        'status': statusUpper,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Track who last touched this SOS
      if (uid != null) {
        updateData['lastUpdatedByUid'] = uid;
        if (actorName != null) {
          updateData['lastUpdatedByName'] = actorName;
        }
        if (actorRole != null) {
          updateData['lastUpdatedByRole'] = actorRole;
        }
      }

      // Track specific ack / resolve handlers for audit
      if (statusUpper == 'ACKNOWLEDGED' && uid != null) {
        updateData['acknowledgedAt'] = FieldValue.serverTimestamp();
        updateData['acknowledgedByUid'] = uid;
        if (actorName != null) {
          updateData['acknowledgedByName'] = actorName;
        }
        if (actorRole != null) {
          updateData['acknowledgedByRole'] = actorRole;
        }
      } else if (statusUpper == 'RESOLVED' && uid != null) {
        updateData['resolvedAt'] = FieldValue.serverTimestamp();
        updateData['resolvedByUid'] = uid;
        if (actorName != null) {
          updateData['resolvedByName'] = actorName;
        }
        if (actorRole != null) {
          updateData['resolvedByRole'] = actorRole;
        }
      }

      await ref.update(updateData);
      AppLogger.i('SOS status updated', data: {
        'societyId': societyId,
        'sosId': sosId,
        'status': statusUpper,
      });
    } catch (e, st) {
      AppLogger.e('Error updating SOS status', error: e, stackTrace: st);
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getSosRequests({
    required String societyId,
    int limit = 50,
  }) async {
    try {
      final snap = await _firestore
          .collection('societies')
          .doc(societyId)
          .collection('sos_requests')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snap.docs.map((d) {
        final data = d.data();
        return {
          'sosId': d.id,
          ...data,
        };
      }).toList();
    } catch (e, st) {
      AppLogger.e('Error getting SOS requests', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Paginated SOS requests: one-time get(), returns list and lastDoc for "Load more".
  Future<Map<String, dynamic>> getSosRequestsPage({
    required String societyId,
    int limit = 30,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      final baseQuery = _firestore
          .collection('societies')
          .doc(societyId)
          .collection('sos_requests')
          .orderBy('createdAt', descending: true)
          .limit(limit);

      final snap = startAfter == null
          ? await baseQuery.get()
          : await baseQuery.startAfterDocument(startAfter).get();

      final list = snap.docs.map((d) {
        final data = d.data() as Map<String, dynamic>? ?? {};
        return {
          'sosId': d.id,
          ...data,
        };
      }).toList();

      final lastDoc = snap.docs.isEmpty ? null : snap.docs.last;
      return {'list': list, 'lastDoc': lastDoc};
    } catch (e, st) {
      AppLogger.e('Error getting SOS requests page', error: e, stackTrace: st);
      rethrow;
    }
  }

  Future<String> createSosRequest({
    required String societyId,
    required String residentId,
    required String residentName,
    required String flatNo,
    String? phone,
    String? type, // e.g. MEDICAL, SECURITY, OTHER
    String? note,
  }) async {
    try {
      final sosRef = _firestore
          .collection('societies')
          .doc(societyId)
          .collection('sos_requests')
          .doc();

      final payload = <String, dynamic>{
        'sosId': sosRef.id,
        'residentId': residentId,
        'residentName': residentName,
        'flatNo': flatNo,
        if (phone != null) 'phone': phone,
        'type': (type ?? 'OTHER').toUpperCase(),
        'note': note,
        'status': 'OPEN', // OPEN -> ACKNOWLEDGED -> RESOLVED (future)
        'createdAt': FieldValue.serverTimestamp(),
      };

      await sosRef.set(payload);
      AppLogger.i('SOS request created', data: {
        'societyId': societyId,
        'residentId': residentId,
        'flatNo': flatNo,
        'type': payload['type'],
      });
      return sosRef.id;
    } catch (e, st) {
      AppLogger.e('Error creating SOS request', error: e, stackTrace: st);
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

  /// Resolve societyId from a society code (case-insensitive)
  /// Handles codes with or without SOC_ prefix (e.g., "AMARA" or "SOC_AMARA" both work)
  Future<String?> getSocietyByCode(String societyCode) async {
    try {
      // Normalize code: strip SOC_ prefix if present, then uppercase
      String normalized = societyCode.trim().toUpperCase();

      // Remove SOC_ prefix if present (case-insensitive)
      if (normalized.startsWith('SOC_')) {
        normalized = normalized.substring(4); // Remove "SOC_" (4 characters)
      }

      if (normalized.isEmpty) return null;

      debugPrint(
          "getSocietyByCode | normalized=$normalized (original=$societyCode)");

      // ✅ Use societyCodes mapping doc: /societyCodes/AMARA -> { societyId: "soc_amara", active: true }
      final doc =
          await _firestore.collection('societyCodes').doc(normalized).get();

      if (!doc.exists) {
        debugPrint("getSocietyByCode | not found: $normalized");
        return null;
      }

      final data = doc.data() as Map<String, dynamic>;

      // Optional: block inactive codes
      final isActive = data['active'] == true;
      if (!isActive) {
        debugPrint("getSocietyByCode | inactive code: $normalized");
        return null;
      }

      final societyId = data['societyId']?.toString();
      debugPrint("getSocietyByCode | societyId=$societyId");

      if (societyId == null || societyId.isEmpty) return null;
      return societyId;
    } catch (e, st) {
      AppLogger.e("getSocietyByCode failed", error: e, stackTrace: st);
      debugPrint("getSocietyByCode failed: $e");
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getMembers({
    required String societyId,
    String? systemRole,
  }) async {
    Query query =
        _firestore.collection('societies').doc(societyId).collection('members');

    if (systemRole != null && systemRole.isNotEmpty) {
      query = query.where('systemRole', isEqualTo: systemRole);
    }

    final snap = await query.get();
    return snap.docs.map((d) {
      final data = d.data() as Map<String, dynamic>;
      return _mapMemberDoc(d.id, data);
    }).toList();
  }

  /// Paginated members: one-time get(), orderBy document ID, returns list and lastDoc for "Load more".
  /// Requires composite index: systemRole (==), __name__ (asc) if not auto-created.
  Future<Map<String, dynamic>> getMembersPage({
    required String societyId,
    required String systemRole,
    int limit = 30,
    DocumentSnapshot? startAfter,
  }) async {
    final baseQuery = _firestore
        .collection('societies')
        .doc(societyId)
        .collection('members')
        .where('systemRole', isEqualTo: systemRole)
        .orderBy(FieldPath.documentId)
        .limit(limit);

    final snap = startAfter == null
        ? await baseQuery.get()
        : await baseQuery.startAfterDocument(startAfter).get();
    final list = snap.docs.map((d) {
      final data = d.data();
      return _mapMemberDoc(d.id, data);
    }).toList();

    final lastDoc = snap.docs.isEmpty ? null : snap.docs.last;
    return {'list': list, 'lastDoc': lastDoc};
  }

  Map<String, dynamic> _mapMemberDoc(String docId, Map<String, dynamic> data) {
    return {
      'id': docId,
      ...data,
      'resident_id': data['uid'] ?? docId,
      'resident_name': data['name'] ?? data['residentName'],
      'flat_no': data['flatNo'] ?? data['flat_no'],
      'resident_phone': data['phone'] ?? data['mobile'],
      'guard_id': data['uid'] ?? docId,
      'guard_name': data['name'] ?? data['guardName'] ?? 'Guard',
    };
  }

  // ============================================
  // GUARD PROFILE HELPERS
  // ============================================

  Future<void> updateGuardProfile({
    required String societyId,
    required String uid,
    String? phone,
    String? email,
    String? photoUrl,
    String? shiftTimings,
  }) async {
    try {
      final data = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (phone != null) data['phone'] = phone;
      if (email != null) data['email'] = email;
      if (photoUrl != null) data['photoUrl'] = photoUrl;
      if (shiftTimings != null) data['shiftTimings'] = shiftTimings;

      await _memberRef(societyId, uid).update(data);
      AppLogger.i('Guard profile updated', data: {
        'societyId': societyId,
        'uid': uid,
      });
    } catch (e, st) {
      AppLogger.e('Error updating guard profile', error: e, stackTrace: st);
      rethrow;
    }
  }

  // ============================================
  // PHONE DUPLICATE CHECK
  // ============================================

  /// Check if phone number is already used by an ACTIVE member in the society.
  /// Returns the existing member's UID if duplicate found, null otherwise.
  /// Excludes the current user (excludeUid) from the check.
  Future<String?> checkDuplicatePhone({
    required String societyId,
    required String phone,
    String? excludeUid,
  }) async {
    try {
      if (phone.trim().isEmpty) return null;

      final normalizedPhone = phone.trim().replaceAll(RegExp(r'[^\d+]'), '');
      if (normalizedPhone.isEmpty) return null;

      final querySnapshot = await _firestore
          .collection('societies')
          .doc(societyId)
          .collection('members')
          .where('phone', isEqualTo: normalizedPhone)
          .where('active', isEqualTo: true)
          .where('systemRole', isEqualTo: 'resident')
          .limit(5)
          .get();

      for (final doc in querySnapshot.docs) {
        final uid = doc.data()['uid']?.toString();
        if (uid != null && uid != excludeUid) {
          AppLogger.i('Duplicate phone found', data: {
            'phone': normalizedPhone,
            'existingUid': uid,
            'societyId': societyId,
          });
          return uid;
        }
      }

      return null;
    } catch (e, st) {
      AppLogger.e('Error checking duplicate phone', error: e, stackTrace: st);
      rethrow;
    }
  }

  // ============================================
  // MEMBER DEACTIVATION
  // ============================================

  /// Deactivate a member's account in a society.
  /// Sets active=false, allowing them to join another society.
  /// Only the member themselves or an admin can deactivate.
  Future<void> deactivateMember({
    required String societyId,
    required String uid,
  }) async {
    try {
      final batch = _firestore.batch();

      // Update society member doc
      final memberRef = _memberRef(societyId, uid);
      batch.update(memberRef, {
        'active': false,
        'deactivatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update root pointer
      final rootPointerRef = _firestore.collection('members').doc(uid);
      batch.update(rootPointerRef, {
        'active': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      AppLogger.i('Member deactivated', data: {
        'societyId': societyId,
        'uid': uid,
      });
    } catch (e, st) {
      AppLogger.e('Error deactivating member', error: e, stackTrace: st);
      rethrow;
    }
  }

  // ============================================
  // RESIDENT PROFILE HELPERS
  // ============================================

  Future<void> updateResidentProfile({
    required String societyId,
    required String uid,
    String? phone,
    String? email,
    String? photoUrl,
  }) async {
    try {
      final data = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (phone != null) data['phone'] = phone;
      if (email != null) data['email'] = email;
      if (photoUrl != null) data['photoUrl'] = photoUrl;

      await _memberRef(societyId, uid).update(data);
      AppLogger.i('Resident profile updated', data: {
        'societyId': societyId,
        'uid': uid,
      });
    } catch (e, st) {
      AppLogger.e('Error updating resident profile', error: e, stackTrace: st);
      rethrow;
    }
  }

  // ============================================
  // ADMIN PROFILE HELPERS
  // ============================================

  Future<void> updateAdminProfile({
    required String societyId,
    required String uid,
    String? phone,
    String? email,
    String? photoUrl,
  }) async {
    try {
      final data = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (phone != null) data['phone'] = phone;
      if (email != null) data['email'] = email;
      if (photoUrl != null) data['photoUrl'] = photoUrl;

      await _memberRef(societyId, uid).update(data);
      AppLogger.i('Admin profile updated', data: {
        'societyId': societyId,
        'uid': uid,
      });
    } catch (e, st) {
      AppLogger.e('Error updating admin profile', error: e, stackTrace: st);
      rethrow;
    }
  }

  Future<void> setRootMemberPointer({
    required String uid,
    required String societyId,
    required String systemRole,
    bool active = true,
  }) async {
    await FirebaseFirestore.instance.collection('members').doc(uid).set({
      'uid': uid,
      'societyId': societyId,
      'systemRole': systemRole,
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

// =========================
// Phone index helpers
// =========================

  Future<Map<String, dynamic>?> getPhoneIndex(String normalizedPhone) async {
    final doc = await FirebaseFirestore.instance
        .collection('phone_index')
        .doc(normalizedPhone)
        .get();

    if (!doc.exists) return null;
    return doc.data();
  }

// =========================
// Root pointer repair: members/{uid}
// =========================

  Future<void> ensureRootMemberPointer({
    required String uid,
    required String societyId,
    required String systemRole,
    required bool active,
  }) async {
    final ref = FirebaseFirestore.instance.collection('members').doc(uid);

    await ref.set({
      "uid": uid,
      "societyId": societyId,
      "systemRole": systemRole,
      "active": active,
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> createAdminJoinRequest({
    required String societyId,
    required String societyName,
    required String cityId,
    required String name,
    required String phoneE164,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('createAdminJoinRequest: user not logged in');
    }

    final uid = user.uid;
    final now = FieldValue.serverTimestamp();

    // Normalize phone (keep consistent with your unique phone logic)
    final normalizedPhone =
        FirebaseAuthService.normalizePhoneForIndia(phoneE164);

    // Optional: enforce unique phone globally (recommended)
    final available = await isPhoneAvailableForUser(
      normalizedE164: normalizedPhone,
      forUid: uid,
    );
    if (!available) {
      throw StateError(
          'This mobile number is already linked to another active account.');
    }

    final joinRef = _publicSocietiesRef
        .doc(societyId)
        .collection('admin_join_requests')
        .doc(uid);

    final rootPtrRef = _firestore.collection('members').doc(uid);

    await _firestore.runTransaction((tx) async {
      // 1) Create / update admin join request (under public directory)
      tx.set(
        joinRef,
        {
          'uid': uid,
          'societyId': societyId,
          'societyName': societyName,
          'cityId': cityId,
          'requestedRole': 'admin',
          'name': name,
          'phone': normalizedPhone,
          'status': 'PENDING',
          'createdAt': now,
          'updatedAt': now,
          'handledBy': null,
          'handledAt': null,
        },
        SetOptions(merge: true),
      );

      // 2) Create / update root pointer as inactive admin (so AuthRouter can route to pending)
      tx.set(
        rootPtrRef,
        {
          'uid': uid,
          'societyId': societyId,
          'systemRole': 'admin',
          'active': false,
          'name': name,
          'phone': normalizedPhone,
          'updatedAt': now,
          'createdAt': now,
        },
        SetOptions(merge: true),
      );
    });

    // 3) Ensure phone mapping exists (your project uses unique_phones)
    // This will write to societies/{societyId}/members/{uid} too — if you do NOT want that yet,
    // comment this out and only call setMemberPhone on approval.
    //
    // await setMemberPhone(
    //   societyId: societyId,
    //   uid: uid,
    //   normalizedE164: normalizedPhone,
    // );

    AppLogger.i('Admin join request created', data: {
      'uid': uid,
      'societyId': societyId,
    });
  }
}
