"""
Flat service for flat/resident operations
"""

from typing import List, Optional
from app.sheets.client import get_sheets_client
from app.models.schemas import FlatResponse


class FlatService:
    """Service for flat-related operations"""
    
    def __init__(self):
        self.sheets_client = get_sheets_client()
    
    def get_flats_by_society(self, society_id: str) -> List[FlatResponse]:
        """Get all active flats for a society"""
        flats = self.sheets_client.get_flats(society_id=society_id)
        return [self._dict_to_flat_response(f) for f in flats]
    
    def get_flat_by_id(self, flat_id: str) -> Optional[FlatResponse]:
        """Get a flat by flat_id"""
        flat = self.sheets_client.get_flat_by_id(flat_id)
        if not flat:
            return None
        return self._dict_to_flat_response(flat)
    
    def _dict_to_flat_response(self, flat_dict: dict) -> FlatResponse:
        """Convert flat dict to FlatResponse"""
        return FlatResponse(
            flat_id=flat_dict.get('flat_id', ''),
            society_id=flat_dict.get('society_id', ''),
            flat_no=flat_dict.get('flat_no', ''),
            resident_name=flat_dict.get('resident_name', ''),
            resident_phone=flat_dict.get('resident_phone', ''),
            resident_alt_phone=flat_dict.get('resident_alt_phone'),
            role=flat_dict.get('role', ''),
            active=flat_dict.get('active', '').lower() == 'true',
        )


# Singleton instance
_flat_service: Optional[FlatService] = None


def get_flat_service() -> FlatService:
    """Get singleton FlatService instance"""
    global _flat_service
    if _flat_service is None:
        _flat_service = FlatService()
    return _flat_service
