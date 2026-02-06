from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional

from app.services.unit_service import UnitService

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

class BulkUnitCreateRequest(BaseModel):
    societyId: str
    units: List[UnitCreate]


@router.post("/bulk-create")
def bulk_create_units(payload: BulkUnitCreateRequest):
    try:
        result = UnitService.bulk_create_units(
            society_id=payload.societyId,
            units=[u.dict() for u in payload.units]
        )
        return {
            "success": True,
            "data": result
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
