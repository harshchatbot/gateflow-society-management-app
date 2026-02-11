from fastapi import APIRouter, HTTPException, Header, status
from pydantic import BaseModel
from typing import List, Optional

from app.services.unit_service import UnitService
from app.routers.society_requests import _require_super_admin_uid

router = APIRouter(
    prefix="/admin/units",
    tags=["Admin Units"]
)

class UnitCreate(BaseModel):
    unitId: str
    label: Optional[str] = None
    block: Optional[str] = None
    floor: Optional[int] = None
    type: Optional[str] = "FLAT"
    active: Optional[bool] = True
    sortKey: Optional[int] = None

class BulkUnitCreateRequest(BaseModel):
    societyId: str
    units: List[UnitCreate]


@router.post("/bulk-create")
def bulk_create_units(
    payload: BulkUnitCreateRequest,
    authorization: Optional[str] = Header(default=None),
):
    try:
        _require_super_admin_uid(authorization)
        result = UnitService.bulk_create_units(
            society_id=payload.societyId,
            units=[u.dict() for u in payload.units]
        )
        return {
            "success": True,
            "data": result
        }
    except HTTPException:
        raise
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to bulk create units: {e}",
        )
