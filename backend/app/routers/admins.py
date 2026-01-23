"""
Admin API routes
"""

from fastapi import APIRouter, HTTPException, status, UploadFile, File, Form
from typing import List, Optional
from pydantic import BaseModel, Field
from app.services.admin_service import get_admin_service

import logging

logger = logging.getLogger(__name__)


router = APIRouter(prefix="/api/admins", tags=["Admins"])


# -----------------------------
# Schemas
# -----------------------------

class AdminLoginRequest(BaseModel):
    """Admin login request"""
    society_id: str = Field(..., description="Society code/ID")
    admin_id: str = Field(..., description="Admin ID (e.g., president, secretary)")
    pin: str = Field(..., description="Admin pin/password")


class AdminLoginResponse(BaseModel):
    """Admin login response"""
    admin_id: str
    admin_name: str
    society_id: str
    role: str  # president, secretary, treasurer, etc.
    token: Optional[str] = None


class AdminStatsResponse(BaseModel):
    """Admin dashboard stats"""
    total_residents: int
    total_guards: int
    total_flats: int
    visitors_today: int
    pending_approvals: int
    approved_today: int


# -----------------------------
# Routes
# -----------------------------

@router.post("/login", response_model=AdminLoginResponse)
def admin_login(payload: AdminLoginRequest):
    """
    Admin login endpoint
    Authenticates admin using society_id, admin_id, and pin
    """
    admin_service = get_admin_service()
    
    admin = admin_service.authenticate(
        society_id=payload.society_id,
        admin_id=payload.admin_id,
        pin=payload.pin
    )
    
    if not admin:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials"
        )
    
    return admin


@router.get("/stats", response_model=AdminStatsResponse)
def get_admin_stats(society_id: str):
    """
    Get admin dashboard statistics
    """
    admin_service = get_admin_service()
    return admin_service.get_dashboard_stats(society_id)


@router.get("/residents", response_model=List[dict])
def get_all_residents(society_id: str):
    """
    Get all residents for the society
    """
    admin_service = get_admin_service()
    return admin_service.get_all_residents(society_id)


@router.get("/guards", response_model=List[dict])
def get_all_guards(society_id: str):
    """
    Get all guards for the society
    """
    admin_service = get_admin_service()
    return admin_service.get_all_guards(society_id)


@router.get("/flats", response_model=List[dict])
def get_all_flats(society_id: str):
    """
    Get all flats for the society
    """
    admin_service = get_admin_service()
    return admin_service.get_all_flats(society_id)


@router.get("/visitors", response_model=List[dict])
def get_all_visitors(society_id: str, limit: int = 100):
    """
    Get all visitors for the society
    """
    admin_service = get_admin_service()
    return admin_service.get_all_visitors(society_id, limit=limit)


@router.post("/profile/image")
async def upload_profile_image(
    admin_id: str = Form(...),
    society_id: str = Form(...),
    file: UploadFile = File(...),
):
    """
    Upload admin profile image.
    """
    admin_service = get_admin_service()
    return await admin_service.upload_profile_image(
        admin_id=admin_id,
        society_id=society_id,
        file=file,
    )


class AdminRegisterRequest(BaseModel):
    """Admin registration request"""
    society_id: str = Field(..., description="Society ID")
    admin_id: str = Field(..., description="Admin ID (unique identifier)")
    admin_name: str = Field(..., description="Admin full name")
    pin: str = Field(..., description="Admin PIN/password", min_length=4)
    phone: Optional[str] = Field(None, description="Admin phone number")
    role: str = Field("ADMIN", description="Admin role (president, secretary, etc.)")


@router.post("/register", response_model=dict)
def register_admin(payload: AdminRegisterRequest):
    """
    Register a new admin account.
    """
    admin_service = get_admin_service()
    try:
        admin = admin_service.create_admin(
            society_id=payload.society_id,
            admin_id=payload.admin_id,
            admin_name=payload.admin_name,
            pin=payload.pin,
            phone=payload.phone,
            role=payload.role,
        )
        return {
            "ok": True,
            "message": "Admin registered successfully",
            "admin": admin,
        }
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        logger.error(f"Error registering admin: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to register admin"
        )
