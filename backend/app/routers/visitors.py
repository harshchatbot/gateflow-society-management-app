"""
Visitor API routes
"""

import os
import uuid
from typing import Optional
from fastapi import Header

from fastapi import APIRouter, HTTPException, status, UploadFile, File, Form

from app.models.schemas import (
    VisitorCreateRequest,
    VisitorResponse,
    VisitorListResponse,
)
from app.services.visitor_service import get_visitor_service

import aiofiles
import logging

from app.models.schemas import VisitorStatusUpdateRequest

# ✅ WhatsApp service (best-effort send, non-breaking)
from app.services.whatsapp_service import get_whatsapp_service

logger = logging.getLogger(__name__)

router = APIRouter()


def _normalize_wa_phone(phone: str) -> str:
    """
    WhatsApp Cloud API expects E.164 without '+'.
    Example: '+919876543210' -> '919876543210'
    """
    if not phone:
        return phone
    return str(phone).strip().replace("+", "").replace(" ", "")


def _pick_resident_phone(resident: dict) -> Optional[str]:
    """
    Resident dict may come with normalized lowercase headers (client.py does that).
    Try likely keys safely.
    """
    if not resident:
        return None

    candidates = [
        resident.get("resident_phone"),
        resident.get("residentphone"),
        resident.get("phone"),
        resident.get("mobile"),
    ]
    for p in candidates:
        if isinstance(p, str) and p.strip():
            return p.strip()
    return None


async def _best_effort_send_whatsapp_approval(
    visitor_service,
    society_id: str,
    flat_id: Optional[str],
    flat_no: Optional[str],
    visitor: VisitorResponse,
):
    """
    Best-effort WhatsApp notification to resident.

    - Does NOT raise errors; it will not break existing create flows.
    - Prefer Residents tab (society_id + flat_no) for resident_phone.
    - Fallback to _resolve_flat() if you later store resident_phone in Flats.
    """
    try:
        target_flat_no = flat_no or visitor.flat_no

        # ✅ 1) Preferred: lookup resident in Residents sheet (NEW MVP way)
        resident = None
        try:
            resident = visitor_service.sheets_client.get_resident_by_flat_no(
                society_id=society_id,
                flat_no=target_flat_no,
                active_only=True,
                whatsapp_opt_in_only=True,
            )
        except Exception as e:
            logger.warning(f"RESIDENT_LOOKUP_FAIL | society_id={society_id} flat_no={target_flat_no} err={e}")

        resident_phone = _pick_resident_phone(resident) if resident else None

        # ✅ 2) Fallback: resolve from Flats (if resident_phone exists there)
        if not resident_phone:
            try:
                flat = visitor_service._resolve_flat(
                    society_id=society_id,
                    flat_id=flat_id,
                    flat_no=target_flat_no,
                )
                resident_phone = flat.get("resident_phone")
            except Exception as e:
                # don't break flow
                logger.warning(f"FLAT_RESOLVE_FALLBACK_FAIL | society_id={society_id} flat_no={target_flat_no} err={e}")

        if not resident_phone:
            logger.warning(
                f"WHATSAPP_SKIP | resident_phone not found for society_id={society_id} flat_no={target_flat_no}"
            )
            return

        resident_phone = _normalize_wa_phone(resident_phone)

        # ✅ Send template (Approve/Reject)
        wa = get_whatsapp_service()
        await wa.send_approval_template(
            to_phone_e164_no_plus=resident_phone,
            template_name="gateflow_entry_approval",
            language_code="en_US",
            flat_no=visitor.flat_no,
            visitor_type=visitor.visitor_type,
            visitor_phone=visitor.visitor_phone,
            visitor_id=visitor.visitor_id,
        )

        logger.info(f"WHATSAPP_SENT | to={resident_phone} visitor_id={visitor.visitor_id}")

    except Exception as e:
        # Best effort only - do not fail the API
        logger.warning(
            f"WHATSAPP_SEND_FAILED | visitor_id={getattr(visitor, 'visitor_id', 'UNKNOWN')} err={str(e)}"
        )


@router.post(
    "",
    response_model=VisitorResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create visitor entry",
    description="""
    Create a new visitor entry.

    Validates:
    - Guard exists
    - Flat exists in Flats sheet (by flat_id OR flat_no)
    - Flat is active (active==TRUE)

    Creates visitor entry with:
    - status=PENDING
    - created_at in ISO UTC format
    - Logs approval request stub to resident_phone
    """,
)
async def create_visitor(request: VisitorCreateRequest):
    visitor_service = get_visitor_service()

    # ✅ Require either flat_id or flat_no
    if not request.flat_id and not getattr(request, "flat_no", None):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Either flat_id or flat_no is required (e.g., flat_no='A-101').",
        )

    try:
        visitor = visitor_service.create_visitor(
            flat_id=request.flat_id,
            flat_no=getattr(request, "flat_no", None),
            visitor_type=request.visitor_type,
            visitor_phone=request.visitor_phone,
            guard_id=request.guard_id,
        )

        # ✅ WhatsApp send (best-effort, non-breaking)
        await _best_effort_send_whatsapp_approval(
            visitor_service=visitor_service,
            society_id=visitor.society_id,
            flat_id=request.flat_id,
            flat_no=getattr(request, "flat_no", None),
            visitor=visitor,
        )

        return visitor

    except HTTPException:
        raise
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create visitor entry: {str(e)}",
        )





@router.post(
    "/with-photo",
    response_model=VisitorResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_visitor_with_photo(
    flat_id: Optional[str] = Form(default=None),
    flat_no: Optional[str] = Form(default=None),
    visitor_type: str = Form(...),
    visitor_phone: str = Form(...),

    # keep for backward compatibility, but we'll stop trusting it
    guard_id: str = Form(...),

    photo: UploadFile = File(...),

    # ✅ NEW: read Authorization header
    authorization: Optional[str] = Header(default=None),
):
    visitor_service = get_visitor_service()

    if not flat_id and not flat_no:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Either flat_id or flat_no is required (e.g., flat_no='A-101').",
        )

    # ✅ TEMP LOG (remove later)
    logger.info(f"AUTH HEADER PRESENT? {bool(authorization)}")

    try:
        logger.info(
            f"WITH_PHOTO REQUEST | flat_id={flat_id} flat_no={flat_no} "
            f"visitor_type={visitor_type} visitor_phone={visitor_phone} "
            f"guard_id={guard_id} photo_name={photo.filename} content_type={photo.content_type}"
        )

        # 1) Save photo locally
        os.makedirs("uploads/visitors", exist_ok=True)

        ext = os.path.splitext(photo.filename or "")[1].lower()
        if ext not in [".jpg", ".jpeg", ".png", ".webp"]:
            ext = ".jpg"

        filename = f"{uuid.uuid4().hex}{ext}"
        rel_path = f"visitors/{filename}"   # ✅ MAKE SURE THIS EXISTS
        file_path = os.path.join("uploads", rel_path)

        async with aiofiles.open(file_path, "wb") as f:
            content = await photo.read()
            await f.write(content)


        # ... keep your photo save code exactly same ...

        visitor = visitor_service.create_visitor_with_photo(
            flat_id=flat_id,
            flat_no=flat_no,
            visitor_type=visitor_type,
            visitor_phone=visitor_phone,
            guard_id=guard_id,
            photo_path=rel_path,
        )

        # ...
        return visitor

    except HTTPException:
        raise
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create visitor entry with photo: {str(e)}",
        )



@router.get("/today/{guard_id}", response_model=VisitorListResponse)
async def get_today_visitors(guard_id: str):
    visitor_service = get_visitor_service()
    visitors = visitor_service.get_visitors_today(guard_id)
    return VisitorListResponse(visitors=visitors, count=len(visitors))


@router.get(
    "/by-flat-no/{guard_id}/{flat_no}",
    response_model=VisitorListResponse,
    summary="Get visitors by flat no for a guard's society",
)
async def get_visitors_by_flat_no(guard_id: str, flat_no: str):
    logger.info(f"🔥 HIT BY_FLAT route | guard_id={guard_id} flat_no={flat_no}")

    visitor_service = get_visitor_service()
    visitors = visitor_service.get_visitors_by_flat_no(guard_id=guard_id, flat_no=flat_no)
    return VisitorListResponse(visitors=visitors, count=len(visitors))


@router.post(
    "/{visitor_id}/status",
    response_model=VisitorResponse,
    summary="Update visitor status (APPROVED/REJECTED/LEAVE_AT_GATE)",
)
async def update_visitor_status(visitor_id: str, request: VisitorStatusUpdateRequest):
    visitor_service = get_visitor_service()
    updated = visitor_service.update_visitor_status(
        visitor_id=visitor_id,
        status=request.status,
        approved_by=request.approved_by,
        note=request.note,
    )
    return updated
