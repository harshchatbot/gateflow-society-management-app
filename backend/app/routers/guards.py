"""
Guard API routes
"""

from fastapi import APIRouter, HTTPException, status
from app.models.schemas import GuardLoginRequest, GuardLoginResponse, FlatListResponse
from app.services.guard_service import get_guard_service
from app.services.flat_service import get_flat_service
# app/routers/guards.py
from app.models.schemas import GuardLoginRequest, GuardLoginResponse, FlatListResponse
import app.models.schemas as schemas

router = APIRouter()


@router.post("/login", response_model=GuardLoginResponse)
async def guard_login(request: GuardLoginRequest):
    """
    Guard login endpoint
    Authenticates guard using society_id and PIN
    """
    guard_service = get_guard_service()
    
    guard = guard_service.authenticate(
        society_id=request.society_id,
        pin=request.pin
    )
    
    if not guard:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid society code or PIN"
        )
    
    return guard


@router.get("/{guard_id}/flats", response_model=FlatListResponse)
async def get_guard_society_flats(guard_id: str):
    """
    Get all flats for the guard's society
    Used for flat selection in visitor entry
    """
    guard_service = get_guard_service()
    flat_service = get_flat_service()
    
    # Verify guard exists
    guard = guard_service.get_guard_by_id(guard_id)
    if not guard:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Guard not found"
        )
    
    society_id = guard.get('society_id', '')
    flats = flat_service.get_flats_by_society(society_id)
    
    return FlatListResponse(flats=flats, count=len(flats))


@router.get("/profile/{guard_id}", response_model=GuardLoginResponse)
async def get_guard_profile(guard_id: str):
    """
    Get guard profile details by ID.
    Used for dashboard and profile screen initialization.
    """
    guard_service = get_guard_service()
    
    # Fetch from Google Sheets via Service
    guard = guard_service.get_guard_by_id(guard_id)
    
    print(f"The value of variable is: {guard}")

    if not guard:
        # 404 is more accurate for "not found", 401 for "inactive"
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Guard account is inactive or does not exist."
        )
    
    # Ensure the dictionary keys match GuardLoginResponse (guard_id, guard_name, society_id)
    return guard