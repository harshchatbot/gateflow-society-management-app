## Required Firestore Indexes for Sentinel

These indexes are needed for the new resident directory + join flow.  
Create them via the Firebase Console or `firestore.indexes.json`.

---

### 1) `public_societies` – prefix search by `nameLower`

Used by `FirestoreService.searchPublicSocietiesByPrefix(query)`:

- Collection: `public_societies`
- Fields:
  - `active` – **ASC**
  - `nameLower` – **ASC**

**Important:** Every document must have `nameLower` set to the lowercase society name (e.g. `"kedia amara"`) for resident search to work. If you rename a society in Firestore, either set `nameLower` manually or use **Admin Dashboard → Sync search name** (app updates `nameLower` from `name`; requires Firestore rules allowing admin to update this field).

---

### 2) `public_societies/{societyId}/units` – unit listing

Used by `FirestoreService.getPublicSocietyUnits(societyId)` and (optionally) filtered by type:

1. Basic unit list:
   - Collection: `public_societies/{societyId}/units`
   - Fields:
     - `active` – **ASC**
     - `sortKey` – **ASC**

2. Unit list by type:
   - Collection: `public_societies/{societyId}/units`
   - Fields:
     - `active` – **ASC**
     - `type` – **ASC**
     - `sortKey` – **ASC**

---

### 3) `public_societies/{societyId}/join_requests` – admin review

Used by `FirestoreService.getResidentJoinRequestsForAdmin(societyId)`:

- Collection: `public_societies/{societyId}/join_requests`
- Fields:
  - `requestedRole` – **ASC**
  - `status` – **ASC**
  - `createdAt` – **DESC**

---

### Error handling notes

If an index is missing, Firestore throws a `FirebaseException` with `code == 'failed-precondition'`.  
For the key queries above, the code logs these errors with enough context (collection + filters) so you
can quickly create the corresponding index in the Firebase Console.

