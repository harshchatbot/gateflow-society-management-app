"""
Complaint API routes
"""

from fastapi import APIRouter, HTTPException, status
from typing import Optional, List
from pydantic import BaseModel, Field
from app.services.complaint_service import get_complaint_service

router = APIRouter(prefix="/api/complaints", tags=["Complaints"])


# -----------------------------
# Schemas
# -----------------------------

class ComplaintCreateRequest(BaseModel):
    """Create complaint request"""
    society_id: str = Field(..., description="Society ID")
    flat_no: str = Field(..., description="Flat number")
    resident_id: str = Field(..., description="Resident ID")
    resident_name: str = Field(..., description="Resident name")
    title: str = Field(..., description="Complaint title", min_length=5, max_length=200)
    description: str = Field(..., description="Complaint description", min_length=10, max_length=2000)
    category: str = Field(default="GENERAL", description="Complaint category: GENERAL, MAINTENANCE, SECURITY, CLEANING, OTHER")


class ComplaintResponse(BaseModel):
    """Complaint response"""
    complaint_id: str
    society_id: str
    flat_no: str
    resident_id: str
    resident_name: str
    title: str
    description: str
    category: str
    status: str
    created_at: str
    resolved_at: Optional[str] = None
    resolved_by: Optional[str] = None
    admin_response: Optional[str] = None


class ComplaintStatusUpdateRequest(BaseModel):
    """Update complaint status request"""
    status: str = Field(..., description="Status: PENDING, IN_PROGRESS, RESOLVED, REJECTED")
    resolved_by: Optional[str] = Field(None, description="Admin ID who resolved")
    admin_response: Optional[str] = Field(None, description="Admin response/notes", max_length=1000)


# -----------------------------
# Routes
# -----------------------------

@router.post("", response_model=ComplaintResponse)
def create_complaint(payload: ComplaintCreateRequest):
    """
    Create a new complaint
    """
    service = get_complaint_service()
    try:
        complaint = service.create_complaint(
            society_id=payload.society_id,
            flat_no=payload.flat_no,
            resident_id=payload.resident_id,
            resident_name=payload.resident_name,
            title=payload.title,
            description=payload.description,
            category=payload.category,
        )
        return ComplaintResponse(**complaint)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(e)
        )


@router.get("/resident", response_model=List[dict])
def get_resident_complaints(
    society_id: str,
    flat_no: str,
    resident_id: Optional[str] = None,
):
    """
    Get complaints for a specific resident/flat
    """
    service = get_complaint_service()
    return service.get_resident_complaints(
        society_id=society_id,
        flat_no=flat_no,
        resident_id=resident_id,
    )


@router.get("/admin", response_model=List[dict])
def get_all_complaints(
    society_id: str,
    status: Optional[str] = None,
):
    """
    Get all complaints for a society (admin view)
    Optionally filter by status: PENDING, IN_PROGRESS, RESOLVED, REJECTED
    """
    service = get_complaint_service()
    return service.get_all_complaints(society_id=society_id, status=status)


@router.put("/{complaint_id}/status", response_model=ComplaintResponse)
def update_complaint_status(
    complaint_id: str,
    payload: ComplaintStatusUpdateRequest,
):
    """
    Update complaint status (admin only)
    """
    service = get_complaint_service()
    try:
        complaint = service.update_complaint_status(
            complaint_id=complaint_id,
            status=payload.status,
            resolved_by=payload.resolved_by,
            admin_response=payload.admin_response,
        )
        if not complaint:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Complaint not found"
            )
        return ComplaintResponse(**complaint)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(e)
        )
