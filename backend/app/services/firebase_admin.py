import os
import firebase_admin
from firebase_admin import credentials, firestore

_db = None

def get_db():
    """
    Returns a singleton Firestore client using Firebase Admin SDK.
    Requires GOOGLE_APPLICATION_CREDENTIALS env var OR defaults to ./firebase_service_account.json in backend root.
    """
    global _db
    if _db is not None:
        return _db

    if not firebase_admin._apps:
        cred_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")

        # Fallback to backend root file if env var not set
        if not cred_path:
            # backend/app/core/firebase_admin.py -> backend/
            backend_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
            candidate = os.path.join(backend_root, "firebase_service_account.json")
            cred_path = candidate

        if not os.path.exists(cred_path):
            raise RuntimeError(
                f"Firebase service account json not found at: {cred_path}. "
                f"Set GOOGLE_APPLICATION_CREDENTIALS or place firebase_service_account.json in backend root."
            )

        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred)

    _db = firestore.client()
    return _db
