"""
Pydantic models for request/response schemas
"""

from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field


# Guard Models
class GuardLoginRequest(BaseModel):
    """Guard login request"""
    society_id: str = Field(..., description="Society code/ID")
    pin: str = Field(..., description="Guard PIN", min_length=4)


class GuardLoginResponse(BaseModel):
    """Guard login response"""
    guard_id: str
    guard_name: str
    society_id: str
    token: Optional[str] = None  # For future JWT implementation


# Visitor Models
class VisitorCreateRequest(BaseModel):
    """Create visitor entry request"""
    flat_id: str = Field(..., description="Flat ID")
    visitor_type: str = Field(..., description="Visitor type: Guest, Delivery, or Cab")
    visitor_phone: str = Field(..., description="Visitor phone number")
    guard_id: str = Field(..., description="Guard ID creating the entry")


class VisitorResponse(BaseModel):
    """Visitor entry response"""
    visitor_id: str
    society_id: str
    flat_id: str
    visitor_type: str
    visitor_phone: str
    status: str  # PENDING, APPROVED, REJECTED
    created_at: datetime
    approved_at: Optional[datetime] = None
    approved_by: Optional[str] = None
    guard_id: str

    # NEW (optional)
    photo_path: Optional[str] = None
    photo_url: Optional[str] = None
    note: Optional[str] = None


class VisitorStatusUpdateRequest(BaseModel):
    """Update visitor status request"""
    status: str = Field(..., description="APPROVED / REJECTED / LEAVE_AT_GATE")
    approved_by: Optional[str] = Field(default=None, description="Resident identifier/phone")
    note: Optional[str] = Field(default=None, description="Optional note, eg leave at gate")



class VisitorListResponse(BaseModel):
    """List of visitors response"""
    visitors: list[VisitorResponse]
    count: int


# Flat Models
class FlatResponse(BaseModel):
    """Flat information response"""
    flat_id: str
    society_id: str
    flat_no: str
    resident_name: str
    resident_phone: str
    resident_alt_phone: Optional[str] = None
    role: str
    active: bool


class FlatListResponse(BaseModel):
    """List of flats response"""
    flats: list[FlatResponse]
    count: int


class VisitorCreateRequest(BaseModel):
    """Create visitor entry request"""
    flat_id: str = Field(..., description="Flat ID")
    visitor_type: str = Field(..., description="Visitor type: Guest, Delivery, or Cab")
    visitor_phone: str = Field(..., description="Visitor phone number")
    guard_id: str = Field(..., description="Guard ID creating the entry")
    photo_path: Optional[str] = Field(default=None, description="Local/photo storage path (optional)")
    photo_url: Optional[str] = Field(default=None, description="Public URL of photo (optional)")
