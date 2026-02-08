from typing import Optional
import hashlib

from fastapi import APIRouter, Header, HTTPException, status
from pydantic import BaseModel, Field
from firebase_admin import firestore

from app.services.firebase_admin import get_db, verify_id_token

router = APIRouter(prefix="/api/society-requests", tags=["society-requests"])


class ApproveSocietyRequestPayload(BaseModel):
    request_id: str = Field(..., min_length=3)


class RejectSocietyRequestPayload(BaseModel):
    request_id: str = Field(..., min_length=3)
    reason: Optional[str] = Field(default=None, max_length=300)


def _require_super_admin_uid(authorization: Optional[str]) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing Authorization token")

    token = authorization.split(" ", 1)[1].strip()
    if not token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid Authorization token")

    try:
        claims = verify_id_token(token)
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=f"Invalid Firebase token: {e}")

    uid = claims.get("uid")
    if not uid:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token missing uid")

    db = get_db()
    platform_admin = db.collection("platform_admins").document(uid).get()
    if not platform_admin.exists:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Super admin access required")

    data = platform_admin.to_dict() or {}
    role = (data.get("role") or data.get("systemRole") or "").strip().lower()
    if role != "super_admin" or data.get("active") is not True:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Super admin access required")

    return uid


def _normalize_code(raw: str) -> str:
    return (raw or "").strip().upper()


@router.get("/pending")
def list_pending_society_requests(
    limit: int = 50,
    authorization: Optional[str] = Header(default=None),
):
    _require_super_admin_uid(authorization)
    db = get_db()

    safe_limit = max(1, min(limit, 200))
    snaps = (
        db.collection("society_creation_requests")
        .where("status", "==", "PENDING")
        .limit(safe_limit)
        .stream()
    )

    items = []
    for s in snaps:
        data = s.to_dict() or {}
        data["id"] = s.id
        items.append(data)

    return {
        "ok": True,
        "count": len(items),
        "items": items,
    }


@router.get("/dashboard")
def get_society_requests_dashboard(
    authorization: Optional[str] = Header(default=None),
):
    _require_super_admin_uid(authorization)
    db = get_db()

    pending_items = []
    for s in (
        db.collection("society_creation_requests")
        .where("status", "==", "PENDING")
        .limit(100)
        .stream()
    ):
        d = s.to_dict() or {}
        d["id"] = s.id
        pending_items.append(d)

    total_societies = 0
    active_societies = 0
    recent_societies = []

    for s in (
        db.collection("societies")
        .limit(200)
        .stream()
    ):
        total_societies += 1
        d = s.to_dict() or {}
        if d.get("active") is True:
            active_societies += 1
        recent_societies.append({
            "id": s.id,
            "name": d.get("name"),
            "code": d.get("code"),
            "city": d.get("city"),
            "state": d.get("state"),
            "active": d.get("active") is True,
            "createdAt": d.get("createdAt"),
        })

    return {
        "ok": True,
        "summary": {
            "total_societies": total_societies,
            "active_societies": active_societies,
            "pending_requests": len(pending_items),
        },
        "pending_requests": pending_items,
        "recent_societies": recent_societies[:20],
    }


@router.post("/approve")
def approve_society_request(
    payload: ApproveSocietyRequestPayload,
    authorization: Optional[str] = Header(default=None),
):
    approver_uid = _require_super_admin_uid(authorization)
    db = get_db()

    req_ref = db.collection("society_creation_requests").document(payload.request_id)
    req_snap = req_ref.get()
    if not req_snap.exists:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Request not found")

    req = req_snap.to_dict() or {}
    if req.get("status") != "PENDING":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Request is not pending")

    requester_uid = str(req.get("requestedByUid") or "").strip()
    proposed_code = _normalize_code(str(req.get("proposedCode") or ""))
    proposed_name = str(req.get("proposedName") or "").strip()
    proposed_society_id = str(req.get("proposedSocietyId") or "").strip()

    if not requester_uid or not proposed_code or not proposed_name or not proposed_society_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Request data is incomplete")

    society_ref = db.collection("societies").document(proposed_society_id)
    society_code_ref = db.collection("societyCodes").document(proposed_code)

    if society_ref.get().exists:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Society already exists")

    if society_code_ref.get().exists:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Society code already exists")

    now = firestore.SERVER_TIMESTAMP

    requester_name = str(req.get("requesterName") or "").strip()
    requester_email = str(req.get("requesterEmail") or "").strip()
    requester_phone = str(req.get("requesterPhone") or "").strip()

    society_doc = {
        "name": proposed_name,
        "code": proposed_code,
        "city": req.get("city"),
        "state": req.get("state"),
        "active": True,
        "createdAt": now,
        "createdByUid": requester_uid,
        "modules": {
            "visitor_management": True,
            "complaints": True,
            "notices": True,
            "violations": True,
            "sos": True,
        },
    }

    root_member_doc = {
        "uid": requester_uid,
        "societyId": proposed_society_id,
        "systemRole": "admin",
        "societyRole": "society_owner",
        "active": True,
        "name": requester_name,
        "email": requester_email if requester_email else None,
        "phone": requester_phone if requester_phone else None,
        "pendingSocietyRequestId": None,
        "pendingSocietyRequestStatus": "APPROVED",
        "updatedAt": now,
    }

    society_member_doc = {
        "uid": requester_uid,
        "societyId": proposed_society_id,
        "systemRole": "admin",
        "societyRole": "society_owner",
        "name": requester_name,
        "email": requester_email if requester_email else None,
        "phone": requester_phone if requester_phone else None,
        "active": True,
        "createdAt": now,
        "updatedAt": now,
    }

    public_society_doc = {
        "name": proposed_name,
        "nameLower": proposed_name.lower(),
        "code": proposed_code,
        "city": req.get("city"),
        "state": req.get("state"),
        "active": True,
        "createdAt": now,
        "updatedAt": now,
        "createdByUid": requester_uid,
    }

    batch = db.batch()
    batch.set(society_ref, society_doc)
    batch.set(society_code_ref, {
        "societyId": proposed_society_id,
        "active": True,
        "createdAt": now,
        "createdByUid": requester_uid,
    })
    batch.set(db.collection("societies").document(proposed_society_id).collection("members").document(requester_uid), society_member_doc, merge=True)
    batch.set(db.collection("members").document(requester_uid), root_member_doc, merge=True)
    batch.set(db.collection("public_societies").document(proposed_society_id), public_society_doc, merge=True)
    if requester_phone:
        batch.set(
            db.collection("phone_index").document(requester_phone),
            {
                    "uid": requester_uid,
                    "societyId": proposed_society_id,
                    "systemRole": "admin",
                    "active": True,
                    "updatedAt": now,
                },
            merge=True,
        )
        phone_hash = hashlib.sha256(requester_phone.encode("utf-8")).hexdigest()
        batch.set(
            db.collection("unique_phones").document(phone_hash),
            {
                "uid": requester_uid,
                "updatedAt": now,
            },
            merge=True,
        )
    batch.update(req_ref, {
        "status": "APPROVED",
        "approvedByUid": approver_uid,
        "approvedAt": now,
        "updatedAt": now,
    })
    batch.commit()

    return {
        "ok": True,
        "request_id": payload.request_id,
        "status": "APPROVED",
        "society_id": proposed_society_id,
        "society_code": proposed_code,
    }


@router.post("/reject")
def reject_society_request(
    payload: RejectSocietyRequestPayload,
    authorization: Optional[str] = Header(default=None),
):
    approver_uid = _require_super_admin_uid(authorization)
    db = get_db()

    req_ref = db.collection("society_creation_requests").document(payload.request_id)
    req_snap = req_ref.get()
    if not req_snap.exists:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Request not found")

    req = req_snap.to_dict() or {}
    if req.get("status") != "PENDING":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Request is not pending")

    req_ref.update({
        "status": "REJECTED",
        "rejectedByUid": approver_uid,
        "rejectedAt": firestore.SERVER_TIMESTAMP,
        "updatedAt": firestore.SERVER_TIMESTAMP,
        "rejectionReason": payload.reason,
    })
    requester_uid = (req.get("requestedByUid") or "").strip()
    if requester_uid:
        db.collection("members").document(requester_uid).set({
            "pendingSocietyRequestStatus": "REJECTED",
            "updatedAt": firestore.SERVER_TIMESTAMP,
        }, merge=True)

    return {
        "ok": True,
        "request_id": payload.request_id,
        "status": "REJECTED",
    }
