"""
Visitor API routes
"""

import os
import uuid
from typing import Optional

from fastapi import APIRouter, HTTPException, status, UploadFile, File, Form

from app.models.schemas import (
    VisitorCreateRequest,
    VisitorResponse,
    VisitorListResponse,
)
from app.services.visitor_service import get_visitor_service

import aiofiles
import logging

logger = logging.getLogger(__name__)

router = APIRouter()


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
    summary="Create visitor entry with photo",
    description="Create a new visitor entry with a captured visitor photo (multipart/form-data).",
)
async def create_visitor_with_photo(
    flat_id: Optional[str] = Form(default=None),
    flat_no: Optional[str] = Form(default=None),
    visitor_type: str = Form(...),
    visitor_phone: str = Form(...),
    guard_id: str = Form(...),
    photo: UploadFile = File(...),
):
    visitor_service = get_visitor_service()

    if not flat_id and not flat_no:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Either flat_id or flat_no is required (e.g., flat_no='A-101').",
        )

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
        rel_path = f"visitors/{filename}"
        file_path = os.path.join("uploads", rel_path)

        async with aiofiles.open(file_path, "wb") as f:
            content = await photo.read()
            await f.write(content)

        visitor = visitor_service.create_visitor_with_photo(
            flat_id=flat_id,
            flat_no=flat_no,
            visitor_type=visitor_type,
            visitor_phone=visitor_phone,
            guard_id=guard_id,
            photo_path=rel_path,
        )

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
