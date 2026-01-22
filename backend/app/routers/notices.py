"""
Notice API routes
"""

from fastapi import APIRouter, HTTPException, status
from typing import Optional, List
from pydantic import BaseModel, Field
from app.services.notice_service import get_notice_service

router = APIRouter(prefix="/api/notices", tags=["Notices"])


# -----------------------------
# Schemas
# -----------------------------

class NoticeCreateRequest(BaseModel):
    """Create notice request"""
    society_id: str = Field(..., description="Society ID")
    admin_id: str = Field(..., description="Admin ID creating the notice")
    admin_name: str = Field(..., description="Admin name")
    title: str = Field(..., description="Notice title", min_length=5, max_length=200)
    content: str = Field(..., description="Notice content", min_length=10, max_length=5000)
    notice_type: str = Field(
        default="GENERAL",
        description="Notice type: GENERAL, SCHEDULE, POLICY, EMERGENCY, MAINTENANCE"
    )
    priority: str = Field(
        default="NORMAL",
        description="Priority: LOW, NORMAL, HIGH, URGENT"
    )
    expiry_date: Optional[str] = Field(
        None,
        description="Expiry date in ISO format (optional)"
    )


class NoticeResponse(BaseModel):
    """Notice response"""
    notice_id: str
    society_id: str
    admin_id: str
    admin_name: str
    title: str
    content: str
    notice_type: str
    priority: str
    is_active: str
    created_at: str
    expiry_date: Optional[str] = None


class NoticeStatusUpdateRequest(BaseModel):
    """Update notice status request"""
    is_active: bool = Field(..., description="Active status")


# -----------------------------
# Routes
# -----------------------------

@router.post("", response_model=NoticeResponse)
def create_notice(payload: NoticeCreateRequest):
    """
    Create a new notice (admin only)
    """
    service = get_notice_service()
    try:
        notice = service.create_notice(
            society_id=payload.society_id,
            admin_id=payload.admin_id,
            admin_name=payload.admin_name,
            title=payload.title,
            content=payload.content,
            notice_type=payload.notice_type,
            priority=payload.priority,
            expiry_date=payload.expiry_date,
        )
        return NoticeResponse(**notice)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(e)
        )


@router.get("", response_model=List[dict])
def get_notices(
    society_id: str,
    active_only: bool = True,
):
    """
    Get all notices for a society
    Visible to Guards, Residents, and Admins
    """
    from app.services.notice_service import logger
    logger.info(f"GET /api/notices called with society_id={society_id}, active_only={active_only}")
    service = get_notice_service()
    notices = service.get_all_notices(society_id=society_id, active_only=active_only)
    logger.info(f"GET /api/notices returning {len(notices)} notices")
    return notices


@router.put("/{notice_id}/status", response_model=NoticeResponse)
def update_notice_status(
    notice_id: str,
    payload: NoticeStatusUpdateRequest,
):
    """
    Update notice active status (admin only)
    """
    service = get_notice_service()
    try:
        notice = service.update_notice_status(
            notice_id=notice_id,
            is_active=payload.is_active,
        )
        if not notice:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Notice not found"
            )
        return NoticeResponse(**notice)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(e)
        )


@router.delete("/{notice_id}")
def delete_notice(notice_id: str):
    """
    Delete a notice (admin only)
    """
    service = get_notice_service()
    try:
        success = service.delete_notice(notice_id)
        if not success:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Notice not found"
            )
        return {"ok": True, "message": "Notice deleted successfully"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(e)
        )
