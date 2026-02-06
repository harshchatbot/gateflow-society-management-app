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
