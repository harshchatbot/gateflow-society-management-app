# 🏘️ Units Bulk Upload (Flats / Villas) – Sentinel Backend

This document explains **how to bulk create society units (flats / villas)** in Firestore using the **existing FastAPI backend**.

This is required because:
- Resident “Find Society” flow depends on `public_societies/{societyId}/units`
- Manual creation of 50–200 units is not practical
- Units must exist before residents can request joining

---

## 📌 Firestore Structure (Final)

Units are stored in **two places**:

### 1️⃣ Private (Admin / Guard usage)


commands : /Users/harshveersinghnirwan/.zshrc:46: unmatched `
harshveersinghnirwan@Harshs-MacBook-Pro gateflow % cd back
end
harshveersinghnirwan@Harshs-MacBook-Pro backend % curl -X POST "http://127.0.0.1:8000/admin/units/bulk-create" \
  -H "Content-Type: application/json" \
  --data-binary @villa_units_L_01_80.json

{"success":true,"data":{"created":80,"societyId":"soc_amara"}}%                                                     
harshveersinghnirwan@Harshs-MacBook-Pro backend % curl -X POST "http://127.0.0.1:8000/admin/units/bulk-create" \
  -H "Content-Type: application/json" \
  --data-binary @villa_units_L_01_80.json

{"success":true,"data":{"created":80,"societyId":"soc_amara","path":"public_societies/soc_amara/units"}}%           
harshveersinghnirwan@Harshs-MacBook-Pro backend % source .venv/bin/activate
python -m scripts.test_join_requests --society soc_amara


=== public_societies/soc_amara/join_requests ===
RAW count (first 20): 2

- docId=BJ73idlbqdZs4UjsQrgXGf8Clux1
  cityId: 
  createdAt: 2026-02-05 19:00:46.318000+00:00
  handledAt: 2026-02-05 20:36:03.020000+00:00
  handledBy: kaDF3wkCO3hoFfuyPeCKsUqIyMR2
  name: Admin 1
  phone: +917976111087
  requestedRole: admin
  societyId: soc_amara
  societyName: amara
  status: APPROVED
  uid: BJ73idlbqdZs4UjsQrgXGf8Clux1

- docId=yQuGh5SipiXOfaQK4XrEZxot5fF2
  cityId: 
  createdAt: 2026-02-06 05:08:50.268000+00:00
  handledAt: None
  handledBy: None
  name: Resident
  phone: +917733946646
  requestedRole: resident
  residencyType: OWNER
  societyId: soc_amara
  societyName: amara
  status: PENDING
  uid: yQuGh5SipiXOfaQK4XrEZxot5fF2
  unitLabel: Villa L-70
(.venv) harshveersinghnirwan@Harshs-MacBook-Pro backend % 
python -m scripts.test_join_requests --society soc_amara --filtered


=== public_societies/soc_amara/join_requests ===
RAW count (first 20): 2

- docId=BJ73idlbqdZs4UjsQrgXGf8Clux1
  cityId: 
  createdAt: 2026-02-05 19:00:46.318000+00:00
  handledAt: 2026-02-05 20:36:03.020000+00:00
  handledBy: kaDF3wkCO3hoFfuyPeCKsUqIyMR2
  name: Admin 1
  phone: +917976111087
  requestedRole: admin
  societyId: soc_amara
  societyName: amara
  status: APPROVED
  uid: BJ73idlbqdZs4UjsQrgXGf8Clux1

- docId=yQuGh5SipiXOfaQK4XrEZxot5fF2
  cityId: 
  createdAt: 2026-02-06 05:08:50.268000+00:00
  handledAt: None
  handledBy: None
  name: Resident
  phone: +917733946646
  requestedRole: resident
  residencyType: OWNER
  societyId: soc_amara
  societyName: amara
  status: PENDING
  uid: yQuGh5SipiXOfaQK4XrEZxot5fF2
  unitLabel: Villa L-70

=== FILTERED (requestedRole='resident', status='PENDING') ===
/Users/harshveersinghnirwan/Downloads/gateflow/backend/.venv/lib/python3.12/site-packages/google/cloud/firestore_v1/base_collection.py:316: UserWarning: Detected filter using positional arguments. Prefer using the 'filter' keyword argument instead.
  return query.where(field_path, op_string, value)
/Users/harshveersinghnirwan/Downloads/gateflow/backend/scripts/test_join_requests.py:32: UserWarning: Detected filter using positional arguments. Prefer using the 'filter' keyword argument instead.
  .where("status", "==", "PENDING")
Filtered count (first 20): 1
- docId=yQuGh5SipiXOfaQK4XrEZxot5fF2 => {'residencyType': 'OWNER', 'cityId': '', 'handledAt': None, 'requestedRole': 'resident', 'societyId': 'soc_amara', 'uid': 'yQuGh5SipiXOfaQK4XrEZxot5fF2', 'unitLabel': 'Villa L-70', 'societyName': 'amara', 'phone': '+917733946646', 'handledBy': None, 'createdAt': DatetimeWithNanoseconds(2026, 2, 6, 5, 8, 50, 268000, tzinfo=datetime.timezone.utc), 'status': 'PENDING', 'name': 'Resident'}
(.venv) harshveersinghnirwan@Harshs-MacBook-Pro backend % python -m scripts.test_join_requests --society soc_amara --filtered


=== public_societies/soc_amara/join_requests ===
RAW count (first 20): 0

=== FILTERED (requestedRole='resident', status='PENDING') ===
/Users/harshveersinghnirwan/Downloads/gateflow/backend/.venv/lib/python3.12/site-packages/google/cloud/firestore_v1/base_collection.py:316: UserWarning: Detected filter using positional arguments. Prefer using the 'filter' keyword argument instead.
  return query.where(field_path, op_string, value)
/Users/harshveersinghnirwan/Downloads/gateflow/backend/scripts/test_join_requests.py:32: UserWarning: Detected filter using positional arguments. Prefer using the 'filter' keyword argument instead.
  .where("status", "==", "PENDING")
Filtered count (first 20): 0
(.venv) harshveersinghnirwan@Harshs-MacBook-Pro backend % 
python -m scripts.test_join_requests --society soc_amara --filtered


=== public_societies/soc_amara/join_requests ===
RAW count (first 20): 0

=== FILTERED (requestedRole='resident', status='PENDING') ===
/Users/harshveersinghnirwan/Downloads/gateflow/backend/.venv/lib/python3.12/site-packages/google/cloud/firestore_v1/base_collection.py:316: UserWarning: Detected filter using positional arguments. Prefer using the 'filter' keyword argument instead.
  return query.where(field_path, op_string, value)
/Users/harshveersinghnirwan/Downloads/gateflow/backend/scripts/test_join_requests.py:32: UserWarning: Detected filter using positional arguments. Prefer using the 'filter' keyword argument instead.
  .where("status", "==", "PENDING")
Filtered count (first 20): 0
(.venv) harshveersinghnirwan@Harshs-MacBook-Pro backend % 
curl -X POST "http://127.0.0.1:8000/admin/units/bulk-create" \                                                    
  -H "Content-Type: application/json" \
  --data-binary @villa_units_L_01_80.json

{"success":true,"data":{"created":80,"societyId":"soc_amara","path":"public_societies/soc_amara/units"}}%           
(.venv) harshveersinghnirwan@Harshs-MacBook-Pro backend % 
