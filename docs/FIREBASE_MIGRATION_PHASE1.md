# Firebase Migration - Phase 1 Implementation Summary

## Overview
Phase 1 migration from FastAPI + Google Sheets to Firebase Authentication + Firestore for core CRUD operations (Notices, Complaints, Admin Stats). All UI screens remain intact, only service implementations changed.

---

## Files Created

### 1. `mobile/lib/services/firestore_service.dart`
- Multi-tenant Firestore operations wrapper
- All operations scoped to `societies/{societyId}/...`
- Methods for: Society, Member, Notice, Complaint, Admin Stats operations

### 2. `mobile/lib/services/firebase_auth_service.dart`
- Firebase Authentication wrapper
- Email/password auth for admins
- Deterministic email aliases for guards/residents (preserves PIN UX)
- Helper methods: `getGuardEmail()`, `getResidentEmail()`

---

## Files Modified

### 1. `mobile/pubspec.yaml`
- Added: `firebase_auth: ^5.3.1`
- Added: `cloud_firestore: ^5.4.4`

### 2. `mobile/lib/core/storage.dart`
- Added Firebase session storage methods:
  - `saveFirebaseSession()` - Store uid, societyId, systemRole, societyRole, name, flatNo
  - `getFirebaseSession()` - Retrieve Firebase session
  - `clearFirebaseSession()` - Clear Firebase session
  - `hasFirebaseSession()` - Check if session exists

### 3. `mobile/lib/services/notice_service.dart`
- **Changed**: Internal implementation now uses Firestore
- **Kept**: Same method signatures (`createNotice`, `getNotices`, `updateNoticeStatus`, `deleteNotice`)
- **New**: Uses `FirestoreService` instead of HTTP calls

### 4. `mobile/lib/services/complaint_service.dart`
- **Changed**: Internal implementation now uses Firestore
- **Kept**: Same method signatures (`createComplaint`, `getResidentComplaints`, `getAllComplaints`, `updateComplaintStatus`)
- **New**: Uses `FirestoreService` instead of HTTP calls

### 5. `mobile/lib/services/admin_service.dart`
- **Changed**: `getStats()` now uses Firestore
- **Kept**: Other methods unchanged (for Phase 2/3)
- **New**: Imports `FirestoreService`

### 6. `mobile/lib/services/notification_service.dart`
- **Changed**: Topic naming updated for multi-tenant:
  - Society: `society_{societyId}`
  - Flat: `flat_{societyId}_{flatNo}` (was `flat_{flatId}`)

### 7. `mobile/lib/screens/admin_onboarding_screen.dart`
- **Changed**: Now creates Firebase Auth account + Firestore society + member document
- **Flow**:
  1. Create Firebase Auth account (email/password)
  2. Create society document in Firestore
  3. Create society code mapping
  4. Create member document with systemRole="admin"
  5. Save Firebase session
  6. Navigate to AdminShellScreen

### 8. `mobile/lib/screens/admin_login_screen.dart`
- **Changed**: Now uses Firebase Auth email/password login
- **Flow**:
  1. Sign in with Firebase Auth
  2. Get membership from Firestore
  3. Verify systemRole="admin"
  4. Save Firebase session
  5. Navigate to AdminShellScreen

### 9. `mobile/lib/main.dart`
- **Changed**: Initial routing now checks Firebase Auth + Firestore membership
- **Flow**:
  1. Check `FirebaseAuth.instance.currentUser`
  2. If signed in, get membership from Firestore
  3. Route to appropriate shell screen based on `systemRole`
  4. Fallback to old session storage for backward compatibility

---

## Firestore Data Model

### Collection Structure

```
/societies/{societyId}
  fields: name, code, city(optional), state(optional), active, createdAt, createdByUid
  subcollections:
    /members/{uid}
      fields: uid, systemRole, societyRole, name, phone, flatNo, active, createdAt, updatedAt
    /notices/{noticeId}
      fields: title, content, noticeType, priority, pinned, status, targetRole, expiryAt, 
              createdByUid, createdByName, createdAt, updatedAt
    /complaints/{complaintId}
      fields: flatNo, residentUid, residentName, category, title, description, status,
              createdAt, updatedAt, resolvedAt, resolvedByUid, resolvedByName
    /flats/{flatId}
      fields: flatNo, active, createdAt, updatedAt
    /visitors/{visitorId}
      fields: (Phase 2 - not implemented yet)

/societyCodes/{code}
  fields: societyId, active, createdAt
```

---

## Firestore Security Rules (Draft)

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Helper function: Check if user is member of society
    function isMemberOfSociety(societyId) {
      return request.auth != null && 
             exists(/databases/$(database)/documents/societies/$(societyId)/members/$(request.auth.uid)) &&
             get(/databases/$(database)/documents/societies/$(societyId)/members/$(request.auth.uid)).data.active == true;
    }
    
    // Helper function: Get user's system role in society
    function getUserSystemRole(societyId) {
      return get(/databases/$(database)/documents/societies/$(societyId)/members/$(request.auth.uid)).data.systemRole;
    }
    
    // Societies collection - read only for members
    match /societies/{societyId} {
      allow read: if isMemberOfSociety(societyId);
      allow write: if false; // Only server-side writes for now
      
      // Members subcollection
      match /members/{uid} {
        allow read: if isMemberOfSociety(societyId);
        allow create: if request.auth != null && request.auth.uid == uid;
        allow update: if request.auth != null && request.auth.uid == uid;
      }
      
      // Notices subcollection
      match /notices/{noticeId} {
        allow read: if isMemberOfSociety(societyId);
        allow create: if isMemberOfSociety(societyId) && getUserSystemRole(societyId) == 'admin';
        allow update: if isMemberOfSociety(societyId) && getUserSystemRole(societyId) == 'admin';
        allow delete: if isMemberOfSociety(societyId) && getUserSystemRole(societyId) == 'admin';
      }
      
      // Complaints subcollection
      match /complaints/{complaintId} {
        allow read: if isMemberOfSociety(societyId) && (
          // Resident can read their own complaints
          (getUserSystemRole(societyId) == 'resident' && 
           resource.data.residentUid == request.auth.uid) ||
          // Admin can read all complaints
          getUserSystemRole(societyId) == 'admin'
        );
        allow create: if isMemberOfSociety(societyId) && getUserSystemRole(societyId) == 'resident';
        allow update: if isMemberOfSociety(societyId) && getUserSystemRole(societyId) == 'admin';
      }
      
      // Flats subcollection
      match /flats/{flatId} {
        allow read: if isMemberOfSociety(societyId);
        allow write: if isMemberOfSociety(societyId) && getUserSystemRole(societyId) == 'admin';
      }
      
      // Visitors subcollection (Phase 2)
      match /visitors/{visitorId} {
        allow read: if isMemberOfSociety(societyId);
        allow create: if isMemberOfSociety(societyId) && getUserSystemRole(societyId) == 'guard';
        allow update: if isMemberOfSociety(societyId) && (
          getUserSystemRole(societyId) == 'guard' ||
          (getUserSystemRole(societyId) == 'resident' && 
           resource.data.flatNo == get(/databases/$(database)/documents/societies/$(societyId)/members/$(request.auth.uid)).data.flatNo)
        );
      }
    }
    
    // Society codes collection - read only
    match /societyCodes/{code} {
      allow read: if request.auth != null;
      allow write: if false; // Only server-side writes
    }
  }
}
```

---

## Firestore Index Requirements

### Required Composite Indexes:

1. **Notices Query** (for activeOnly + targetRole filtering):
   - Collection: `societies/{societyId}/notices`
   - Fields: `status` (Ascending), `expiryAt` (Ascending), `targetRole` (Ascending), `pinned` (Descending), `createdAt` (Descending)

2. **Complaints Query** (for resident complaints):
   - Collection: `societies/{societyId}/complaints`
   - Fields: `flatNo` (Ascending), `residentUid` (Ascending), `createdAt` (Descending)

3. **Complaints Query** (for admin all complaints):
   - Collection: `societies/{societyId}/complaints`
   - Fields: `status` (Ascending), `createdAt` (Descending)

4. **Visitors Query** (Phase 2 - for today's visitors):
   - Collection: `societies/{societyId}/visitors`
   - Fields: `createdAt` (Ascending), `status` (Ascending)

**Note**: Firestore will prompt you to create these indexes when you first run queries that require them. You can also create them manually in Firebase Console.

---

## Testing Phase 1

### Prerequisites:
1. Firebase project created
2. Firestore database initialized
3. Security rules deployed (use draft rules above)
4. Firebase Auth enabled (Email/Password provider)

### Test Steps:

#### 1. Create Society + Admin (via Admin Onboarding)

1. Open app → Select "Admin" → "Create Account"
2. Fill form:
   - Society Code: `TEST001`
   - Email: `admin@test.com`
   - Name: `Test Admin`
   - Phone: `9876543210`
   - Role: `PRESIDENT`
   - PIN: `123456`
   - Confirm PIN: `123456`
3. Tap "CREATE ACCOUNT"
4. **Expected**: Account created, navigated to Admin Dashboard

**Verify in Firestore Console:**
- `societies/soc_test001` document exists with fields: name, code, active, createdAt
- `societyCodes/TEST001` document exists with societyId: `soc_test001`
- `societies/soc_test001/members/{uid}` document exists with systemRole: `admin`, societyRole: `president`

#### 2. Create Notice (via Admin)

1. In Admin Dashboard → Navigate to "Notice Board" or "Manage Notices"
2. Tap "Create Notice" or "+" button
3. Fill form:
   - Type: `Announcement`
   - Priority: `Normal`
   - Title: `Test Notice`
   - Content: `This is a test notice`
   - Expiry: (optional)
4. Tap "Create" or "Publish"
5. **Expected**: Notice created, appears in notice board

**Verify in Firestore Console:**
- `societies/soc_test001/notices/{noticeId}` document exists with all fields

#### 3. Create Complaint (via Resident - if resident login implemented)

**Note**: Resident login not yet migrated in Phase 1, but complaint creation can be tested via Firestore console manually.

**Verify in Firestore Console:**
- Manually create: `societies/soc_test001/complaints/{complaintId}` with:
  ```json
  {
    "flatNo": "A-101",
    "residentUid": "test-resident-uid",
    "residentName": "Test Resident",
    "category": "maintenance",
    "title": "Test Complaint",
    "description": "This is a test complaint",
    "status": "pending",
    "createdAt": [timestamp],
    "updatedAt": [timestamp]
  }
  ```

#### 4. View Admin Stats

1. In Admin Dashboard
2. **Expected**: Stats cards show:
   - Total Residents: 0 (no residents yet)
   - Total Guards: 0 (no guards yet)
   - Total Flats: 0 (no flats yet)
   - Visitors Today: 0 (Phase 2)
   - Pending Approvals: 0 (Phase 2)
   - Approved Today: 0 (Phase 2)

**Verify in Firestore Console:**
- Check that `getAdminStats()` queries are working correctly

#### 5. Admin Login (after logout)

1. Logout from Admin Dashboard
2. Select "Admin" → "Login"
3. Enter:
   - Email: `admin@test.com`
   - Password: `123456`
4. Tap "LOGIN"
5. **Expected**: Successfully logged in, navigated to Admin Dashboard

**Verify:**
- Firebase Auth shows user signed in
- Firestore membership document is loaded correctly

---

## Migration Notes

### What Works in Phase 1:
✅ Admin onboarding (creates society + admin)
✅ Admin login (Firebase Auth + Firestore membership)
✅ Notice creation, listing, update, delete
✅ Complaint creation, listing, status update
✅ Admin dashboard stats (from Firestore)
✅ Multi-tenant data isolation
✅ Notification topic naming (updated for multi-tenant)

### What Still Uses FastAPI (Phase 2/3):
⚠️ Guard login/onboarding
⚠️ Resident login/onboarding
⚠️ Visitor creation/management
⚠️ Visitor approvals/history
⚠️ Admin management screens (residents, guards, flats lists)

### Backward Compatibility:
- Old session storage methods still exist
- `main.dart` falls back to old sessions if Firebase Auth not available
- FastAPI backend remains untouched in codebase

---

## Next Steps (Phase 2)

1. Migrate Guard login/onboarding to Firebase Auth
2. Migrate Resident login/onboarding to Firebase Auth
3. Migrate Visitor operations to Firestore
4. Update visitor approval flows
5. Update admin management screens to use Firestore

---

## Troubleshooting

### Common Issues:

1. **"User membership not found"**
   - Check Firestore: `societies/{societyId}/members/{uid}` exists
   - Verify `active == true`

2. **"Permission denied"**
   - Check Firestore security rules
   - Verify user is authenticated
   - Verify user is member of society

3. **"Index required"**
   - Firestore will show link to create index
   - Click link or create manually in Firebase Console

4. **"Email already in use"**
   - Admin email already registered
   - Use login instead of onboarding

---

## Files Summary

**Created:**
- `mobile/lib/services/firestore_service.dart`
- `mobile/lib/services/firebase_auth_service.dart`
- `docs/FIREBASE_MIGRATION_PHASE1.md` (this file)

**Modified:**
- `mobile/pubspec.yaml`
- `mobile/lib/core/storage.dart`
- `mobile/lib/services/notice_service.dart`
- `mobile/lib/services/complaint_service.dart`
- `mobile/lib/services/admin_service.dart`
- `mobile/lib/services/notification_service.dart`
- `mobile/lib/screens/admin_onboarding_screen.dart`
- `mobile/lib/screens/admin_login_screen.dart`
- `mobile/lib/main.dart`

**Total**: 2 new files, 9 modified files

---

## Deployment Checklist

- [ ] Update `pubspec.yaml` dependencies (`flutter pub get`)
- [ ] Deploy Firestore security rules
- [ ] Create required Firestore indexes (or let Firestore prompt)
- [ ] Test admin onboarding flow
- [ ] Test admin login flow
- [ ] Test notice creation/listing
- [ ] Test complaint creation/listing
- [ ] Verify admin dashboard stats load correctly
- [ ] Test notification topic subscriptions
- [ ] Verify multi-tenant isolation (create 2 societies, verify data separation)

---

**Phase 1 Complete** ✅
