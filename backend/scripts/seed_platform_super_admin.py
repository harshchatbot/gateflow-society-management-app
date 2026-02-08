import sys
import firebase_admin
from firebase_admin import credentials, firestore

def main():
    if len(sys.argv) < 2:
        print("Usage: python scripts/seed_platform_super_admin.py <UID> [PHONE_E164]")
        sys.exit(1)

    uid = sys.argv[1].strip()
    phone = sys.argv[2].strip() if len(sys.argv) >= 3 else ""

    if not uid:
        print("UID is empty")
        sys.exit(1)

    # Path is relative to backend/ because you run it from backend folder
    service_account_path = "firebase_service_account.json"

    # Initialize Firebase Admin SDK once
    if not firebase_admin._apps:
        cred = credentials.Certificate(service_account_path)
        firebase_admin.initialize_app(cred)

    db = firestore.client()

    db.collection("members").document(uid).set(
        {
            "uid": uid,
            "systemRole": "super_admin",
            "active": True,
            "phone": phone,
            "createdBy": "bootstrap_script",
            "notes": "Platform super admin",
            "createdAt": firestore.SERVER_TIMESTAMP,
            "updatedAt": firestore.SERVER_TIMESTAMP,
        },
        merge=True,
    )

    print(f"✅ Seeded platform super_admin: {uid}" + (f" ({phone})" if phone else ""))

if __name__ == "__main__":
    main()
