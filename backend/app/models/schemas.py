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

    flat_id: Optional[str] = Field(default=None, description="Flat ID (preferred if known)")
    flat_no: Optional[str] = Field(default=None, description="Flat number like A-101")

    visitor_type: str = Field(..., description="Visitor type: Guest, Delivery, or Cab")
    visitor_phone: str = Field(..., description="Visitor phone number")
    guard_id: str = Field(..., description="Guard ID creating the entry")

    # Optional photo fields (kept for compatibility)
    photo_path: Optional[str] = Field(default=None, description="Local/photo storage path (optional)")
    photo_url: Optional[str] = Field(default=None, description="Public URL of photo (optional)")


class VisitorResponse(BaseModel):
    """Visitor entry response"""
    visitor_id: str
    society_id: str

    flat_id: str
    flat_no: str  # ✅ NEW: always return to frontend

    visitor_type: str
    visitor_phone: str
    status: str  # PENDING, APPROVED, REJECTED
    created_at: datetime
    approved_at: Optional[datetime] = None
    approved_by: Optional[str] = None
    guard_id: str

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


class VisitorNotificationTestRequest(BaseModel):
    """Manual test trigger for visitor push notifications."""
    society_id: str = Field(..., description="Society ID")
    flat_no: str = Field(..., description="Flat number, e.g. A-101")
    flat_id: Optional[str] = Field(default=None, description="Optional legacy flat ID")
    visitor_type: str = Field(default="GUEST", description="Visitor type shown in notification")
    visitor_phone: str = Field(default="9999999999", description="Visitor phone shown in notification")
    visitor_id: Optional[str] = Field(default=None, description="Optional visitor id for payload")

class VisitorResidentNotifyRequest(BaseModel):
    """Notify resident topics after visitor entry is created in Firestore/mobile flow."""
    society_id: str = Field(..., description="Society ID")
    flat_no: str = Field(..., description="Flat number, e.g. A-101")
    flat_id: Optional[str] = Field(default=None, description="Optional legacy flat ID")
    visitor_id: str = Field(..., description="Visitor id")
    visitor_type: str = Field(default="GUEST", description="Visitor type shown in notification")
    visitor_phone: str = Field(default="", description="Visitor phone shown in notification")
    status: str = Field(default="PENDING", description="Visitor status")


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


# -----------------------------
# Resident Models (MVP PIN Login)
# -----------------------------

class ResidentLoginRequest(BaseModel):
    """Resident login request (PIN-based MVP)"""
    society_id: str = Field(..., description="Society code/ID")
    phone: str = Field(..., description="Resident phone number")
    pin: str = Field(..., description="Resident PIN", min_length=4)


class ResidentLoginResponse(BaseModel):
    """Resident login response"""
    resident_id: str
    resident_name: str
    society_id: str
    flat_id: Optional[str] = None
    flat_no: Optional[str] = None
    phone: Optional[str] = None
    token: Optional[str] = None  # For future JWT implementation
