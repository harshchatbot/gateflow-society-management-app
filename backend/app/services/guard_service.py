"""
Guard service for authentication and guard operations
"""

from typing import Optional
from app.sheets.client import get_sheets_client
from app.models.schemas import GuardLoginResponse


class GuardService:
    """Service for guard-related operations"""
    
    def __init__(self):
        self.sheets_client = get_sheets_client()
    
    def authenticate(self, society_id: str, pin: str) -> Optional[GuardLoginResponse]:
        """
        Authenticate guard by society_id and PIN
        
        Returns GuardLoginResponse if authentication succeeds, None otherwise
        """
        guard = self.sheets_client.get_guard_by_pin(society_id=society_id, pin=pin)
        
        if not guard:
            return None
        
        return GuardLoginResponse(
            guard_id=guard.get('guard_id', ''),
            guard_name=guard.get('guard_name', ''),
            society_id=guard.get('society_id', ''),
            token=None  # Future: JWT token
        )
    
    def get_guard_by_id(self, guard_id: str) -> Optional[dict]:
        """Get guard details by guard_id"""
        return self.sheets_client.get_guard_by_id(guard_id)


# Singleton instance
_guard_service: Optional[GuardService] = None


def get_guard_service() -> GuardService:
    """Get singleton GuardService instance"""
    global _guard_service
    if _guard_service is None:
        _guard_service = GuardService()
    return _guard_service
