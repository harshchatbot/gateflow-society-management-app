"""
Resident API routes (Swagger-visible)
"""

from fastapi import APIRouter, HTTPException, UploadFile, File, Form
from typing import Optional, List, Literal
from pydantic import BaseModel, Field

from app.services.resident_service import get_resident_service

from fastapi import Request
from app.models.schemas import ResidentLoginRequest, ResidentLoginResponse


router = APIRouter(prefix="/api/residents", tags=["Residents"])


# -----------------------------
# Schemas
# -----------------------------

class ResidentProfileResponse(BaseModel):
    resident_id: str
    resident_name: str
    society_id: str
    flat_no: str
    resident_phone: Optional[str] = None
    role: Optional[str] = None
    active: Optional[bool] = True


class ResidentUpdateRequest(BaseModel):
    """Update resident profile information"""
    resident_id: str
    society_id: str
    flat_no: str
    resident_name: Optional[str] = None
    resident_phone: Optional[str] = None


class ResidentDecisionRequest(BaseModel):
    society_id: str
    flat_no: str
    resident_id: str
    visitor_id: str
    decision: Literal["APPROVED", "REJECTED"]
    note: Optional[str] = ""


class FcmTokenUpsertRequest(BaseModel):
    resident_id: str
    society_id: str
    flat_no: str
    fcm_token: str


class ResidentDecisionResponse(BaseModel):
    visitor_id: str
    status: str
    updated: bool


class GenericOkResponse(BaseModel):
    ok: bool


class SosAlertRequest(BaseModel):
    """Trigger SOS alert to society staff (guards/admins)"""
    society_id: str
    flat_no: str
    resident_name: str
    resident_phone: Optional[str] = None


# -----------------------------
# Routes
# -----------------------------

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


@router.put("/profile", response_model=ResidentProfileResponse)
def update_profile(payload: ResidentUpdateRequest):
    """
    Update resident profile information (name, phone).
    """
    svc = get_resident_service()
    return svc.update_profile(
        resident_id=payload.resident_id,
        society_id=payload.society_id,
        flat_no=payload.flat_no,
        resident_name=payload.resident_name,
        resident_phone=payload.resident_phone,
    )


@router.post("/profile/image")
async def upload_profile_image(
    resident_id: str = Form(...),
    society_id: str = Form(...),
    flat_no: str = Form(...),
    file: UploadFile = File(...),
):
    """
    Upload resident profile image.
    """
    svc = get_resident_service()
    return await svc.upload_profile_image(
        resident_id=resident_id,
        society_id=society_id,
        flat_no=flat_no,
        file=file,
    )


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


@router.post("/sos", response_model=GenericOkResponse)
def send_sos_alert(payload: SosAlertRequest):
    """
    Trigger an SOS push notification to all staff (guards/admins) in the society.

    Mobile app already writes an SOS document to Firestore; this endpoint is
    focused purely on sending the FCM notification using the existing
    NotificationService and `society_{society_id}_staff` topic.
    """
    svc = get_resident_service()
    svc.send_sos_alert(
        society_id=payload.society_id,
        flat_no=payload.flat_no,
        resident_name=payload.resident_name,
        resident_phone=payload.resident_phone,
    )
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
