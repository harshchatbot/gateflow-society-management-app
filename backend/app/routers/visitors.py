"""
Visitor API routes
"""

from fastapi import APIRouter, HTTPException, status
from app.models.schemas import (
    VisitorCreateRequest,
    VisitorResponse,
    VisitorListResponse
)
from app.services.visitor_service import get_visitor_service

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
    """
)
async def create_visitor(request: VisitorCreateRequest):
    """
    Create a new visitor entry
    
    - Validates flat_id exists and is active
    - Appends to Visitors sheet with status=PENDING
    - Returns created visitor record
    - Logs approval request stub
    """
    visitor_service = get_visitor_service()
    
    try:
        visitor = visitor_service.create_visitor(
            flat_id=request.flat_id,
            visitor_type=request.visitor_type,
            visitor_phone=request.visitor_phone,
            guard_id=request.guard_id
        )
        return visitor
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create visitor entry: {str(e)}"
        )


@router.get("/today/{guard_id}", response_model=VisitorListResponse)
async def get_today_visitors(guard_id: str):
    """
    Get all visitors created today by a guard
    """
    visitor_service = get_visitor_service()
    
    visitors = visitor_service.get_visitors_today(guard_id)
    
    return VisitorListResponse(visitors=visitors, count=len(visitors))
