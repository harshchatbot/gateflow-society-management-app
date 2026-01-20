"""
Visitor API routes
"""

import os
import uuid
from fastapi import APIRouter, HTTPException, status, UploadFile, File, Form

from app.models.schemas import (
    VisitorCreateRequest,
    VisitorResponse,
    VisitorListResponse,
)
from app.services.visitor_service import get_visitor_service

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
    - Flat exists in Flats sheet
    - Flat is active (active==TRUE)
    - Guard exists

    Creates visitor entry with:
    - status=PENDING
    - created_at in ISO UTC format
    - Logs approval request stub to resident_phone
    """,
)
async def create_visitor(request: VisitorCreateRequest):
    visitor_service = get_visitor_service()

    try:
        visitor = visitor_service.create_visitor(
            flat_id=request.flat_id,
            visitor_type=request.visitor_type,
            visitor_phone=request.visitor_phone,
            guard_id=request.guard_id,
        )
        return visitor
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
    flat_id: str = Form(...),
    visitor_type: str = Form(...),
    visitor_phone: str = Form(...),
    guard_id: str = Form(...),
    photo: UploadFile = File(...),
):
    visitor_service = get_visitor_service()

    try:

        logger.info(
            f"WITH_PHOTO REQUEST | "
            f"flat_id={flat_id}, "
            f"visitor_type={visitor_type}, "
            f"visitor_phone={visitor_phone}, "
            f"guard_id={guard_id}, "
            f"photo_name={photo.filename}, "
            f"content_type={photo.content_type}"
        )

        # 1) Save photo locally
        os.makedirs("uploads/visitors", exist_ok=True)

        ext = os.path.splitext(photo.filename or "")[1].lower()
        if ext not in [".jpg", ".jpeg", ".png", ".webp"]:
            ext = ".jpg"

        filename = f"{uuid.uuid4().hex}{ext}"
        file_path = os.path.join("uploads", "visitors", filename)

        content = await photo.read()
        with open(file_path, "wb") as f:
            f.write(content)

        # 2) Create visitor row (store photo_path in sheets)
        visitor = visitor_service.create_visitor_with_photo(
            flat_id=flat_id,
            visitor_type=visitor_type,
            visitor_phone=visitor_phone,
            guard_id=guard_id,
            photo_path=file_path,
        )

        return visitor

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
