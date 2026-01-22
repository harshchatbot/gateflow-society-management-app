"""
Resident API routes (Swagger-visible)
"""

from fastapi import APIRouter, HTTPException
from typing import Optional, List, Literal
from pydantic import BaseModel, Field

from app.services.resident_service import get_resident_service

from fastapi import Request
from app.models.schemas import ResidentLoginRequest, ResidentLoginResponse


router = APIRouter(prefix="/api/residents", tags=["Residents"])


# -----------------------------
# Schemas (can move to models/schemas.py later)
# -----------------------------

class ResidentProfileResponse(BaseModel):
    resident_id: str
    resident_name: str
    society_id: str
    flat_no: str
    resident_phone: Optional[str] = None
    role: Optional[str] = None
    active: Optional[bool] = True


class ResidentDecisionRequest(BaseModel):
    society_id: str
    flat_no: str
    resident_id: str
    visitor_id: str
    decision: Literal["APPROVED", "REJECTED"]
    note: Optional[str] = ""

class FcmTokenRequest(BaseModel):
    society_id: str
    flat_no: str
    resident_id: str
    fcm_token: str



class ResidentDecisionResponse(BaseModel):
    visitor_id: str
    status: str
    updated: bool


class FcmTokenUpsertRequest(BaseModel):
    resident_id: str
    society_id: str
    flat_no: str
    fcm_token: str


class GenericOkResponse(BaseModel):
    ok: bool


# -----------------------------
# Routes
# -----------------------------

@router.get("/profile")
def resident_profile(society_id: str, flat_no: str, phone: Optional[str] = None):
    svc = get_resident_service()
    return svc.get_profile(society_id=society_id, flat_no=flat_no, phone=phone)


@router.get("/approvals", response_model=List[dict])
def approvals(society_id: str, flat_no: str):
    svc = get_resident_service()
    return svc.pending_approvals(society_id=society_id, flat_no=flat_no)


@router.get("/history", response_model=List[dict])
def history(society_id: str, flat_no: str, limit: int = 50):
    svc = get_resident_service()
    return svc.history(society_id=society_id, flat_no=flat_no, limit=limit)

@router.post("/decision")
def decision(payload: ResidentDecisionRequest):
    svc = get_resident_service()
    return svc.decide(
        society_id=payload.society_id,
        flat_no=payload.flat_no,
        resident_id=payload.resident_id,
        visitor_id=payload.visitor_id,
        decision=payload.decision,
        note=payload.note or "",
    )

@router.post("/fcm-token")
def save_fcm_token(payload: FcmTokenRequest):
    svc = get_resident_service()
    svc.save_fcm_token(
        society_id=payload.society_id,
        flat_no=payload.flat_no,
        resident_id=payload.resident_id,
        fcm_token=payload.fcm_token,
    )
    return {"ok": True}    

@router.get("/profile", response_model=ResidentProfileResponse)
def get_profile(
    society_id: str,
    flat_no: str,
    phone: Optional[str] = None,
):
    """
    Lookup resident profile by society_id + flat_no.
    Optional phone validation for MVP security.
    """
    svc = get_resident_service()
    return svc.get_resident_profile(society_id=society_id, flat_no=flat_no, phone=phone)


@router.get("/approvals", response_model=List[dict])
def approvals(
    society_id: str,
    flat_no: str,
):
    """
    Pending visitor requests for this flat (status=PENDING).
    """
    svc = get_resident_service()
    return svc.get_pending_approvals(society_id=society_id, flat_no=flat_no)


@router.post("/decision", response_model=ResidentDecisionResponse)
def decision(payload: ResidentDecisionRequest):
    """
    Approve/Reject a visitor request.
    """
    svc = get_resident_service()
    return svc.decide_visitor(payload)


@router.get("/history", response_model=List[dict])
def history(
    society_id: str,
    flat_no: str,
    limit: int = 50,
):
    """
    Approval history for this flat (non-pending).
    """
    svc = get_resident_service()
    return svc.get_history(society_id=society_id, flat_no=flat_no, limit=limit)


@router.post("/fcm-token", response_model=GenericOkResponse)
def upsert_fcm_token(payload: FcmTokenUpsertRequest):
    """
    Store/update resident device token (for FCM push).
    """
    svc = get_resident_service()
    svc.upsert_fcm_token(payload)
    return GenericOkResponse(ok=True)


@router.post("/login", response_model=ResidentLoginResponse)
def resident_login(payload: ResidentLoginRequest, request: Request):
    """
    PIN-based login (MVP).
    """
    svc = get_resident_service()
    return svc.login_with_pin(
        society_id=payload.society_id,
        phone=payload.phone,
        pin=payload.pin,
    )
