import os
import firebase_admin
from firebase_admin import credentials, firestore, auth

_db = None


def _ensure_app_initialized():
    if firebase_admin._apps:
        return

    cred_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")

    if not cred_path:
        backend_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
        cred_path = os.path.join(backend_root, "firebase_service_account.json")

    if not os.path.exists(cred_path):
        raise RuntimeError(
            f"Firebase service account json not found at: {cred_path}. "
            f"Set GOOGLE_APPLICATION_CREDENTIALS or place firebase_service_account.json in backend root."
        )

    cred = credentials.Certificate(cred_path)
    firebase_admin.initialize_app(cred)


def get_db():
    """
    Returns a singleton Firestore client using Firebase Admin SDK.
    Requires GOOGLE_APPLICATION_CREDENTIALS env var OR defaults to ./firebase_service_account.json in backend root.
    """
    global _db
    if _db is not None:
        return _db

    _ensure_app_initialized()
    _db = firestore.client()
    return _db


def verify_id_token(id_token: str):
    """Verify Firebase ID token and return decoded claims."""
    _ensure_app_initialized()
    return auth.verify_id_token(id_token)
