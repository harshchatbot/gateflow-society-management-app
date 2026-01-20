"""
Visitor service for visitor entry management
"""

from datetime import datetime, timezone
from typing import List, Optional
import uuid
import logging

from app.sheets.client import get_sheets_client
from app.models.schemas import VisitorResponse, FlatResponse
from app.models.enums import VisitorStatus



logger = logging.getLogger(__name__)


class VisitorService:
    """Service for visitor-related operations"""
    
    def __init__(self):
        self.sheets_client = get_sheets_client()
    
    def create_visitor(
        self,
        flat_id: str,
        visitor_type: str,
        visitor_phone: str,
        guard_id: str,
        photo_path: str = ""
    ) -> VisitorResponse:
        """
        Create a new visitor entry
        
        Returns VisitorResponse with created visitor data
        """
        # Validate flat exists (check without active filter first)
        flat = self.sheets_client.get_flat_by_id(flat_id, active_only=False)
        if not flat:
            raise ValueError(f"Flat with ID {flat_id} not found")
        
        # Validate flat is active (case-insensitive check)
        flat_active = str(flat.get('active', '')).lower()
        if flat_active != 'true':
            raise ValueError(f"Flat with ID {flat_id} exists but is not active")
        
        # Validate guard exists
        guard = self.sheets_client.get_guard_by_id(guard_id)
        if not guard:
            raise ValueError(f"Guard with ID {guard_id} not found")
        
        # Generate visitor_id
        visitor_id = str(uuid.uuid4())
        society_id = flat.get('society_id', '')
        
        # Create visitor entry with ISO UTC timestamp
        created_at_utc = datetime.now(timezone.utc).isoformat()
        visitor_data = {
            'visitor_id': visitor_id,
            'society_id': society_id,
            'flat_id': flat_id,
            'visitor_type': visitor_type,
            'visitor_phone': visitor_phone,
            'status': VisitorStatus.PENDING.value,
            'created_at': created_at_utc,
            'approved_at': '',
            'approved_by': '',
            'guard_id': guard_id,
            'photo_path': photo_path,
        }
        
        # Append to Visitors sheet
        self.sheets_client.create_visitor(visitor_data)
        
        # Log approval stub to resident phone
        self._log_approval_request(flat, visitor_data)
        
        return self._dict_to_visitor_response(visitor_data)
    


    def create_visitor_with_photo(
        self,
        flat_id: str,
        visitor_type: str,
        visitor_phone: str,
        guard_id: str,
        photo_path: str
    ) -> VisitorResponse:
        return self.create_visitor(
            flat_id=flat_id,
            visitor_type=visitor_type,
            visitor_phone=visitor_phone,
            guard_id=guard_id,
            photo_path=photo_path
        )




    def get_visitors_today(self, guard_id: str) -> List[VisitorResponse]:
        """Get all visitors created today by a guard"""
        today = datetime.now().strftime('%Y-%m-%d')
        visitors = self.sheets_client.get_visitors(
            guard_id=guard_id,
            date_filter=today
        )
        
        return [self._dict_to_visitor_response(v) for v in visitors]
    
    def get_visitors_by_flat(self, flat_id: str) -> List[VisitorResponse]:
        """Get all visitors for a flat"""
        visitors = self.sheets_client.get_visitors(flat_id=flat_id)
        return [self._dict_to_visitor_response(v) for v in visitors]
    
    def _dict_to_visitor_response(self, visitor_dict: dict) -> VisitorResponse:
        """Convert visitor dict to VisitorResponse"""
        created_at_str = visitor_dict.get('created_at', '')
        approved_at_str = visitor_dict.get('approved_at', '')
        
        # Parse created_at (ISO UTC format)
        try:
            if created_at_str:
                # Handle ISO format with timezone info
                created_at = datetime.fromisoformat(created_at_str.replace('Z', '+00:00'))
                # Ensure it's timezone-aware
                if created_at.tzinfo is None:
                    created_at = created_at.replace(tzinfo=timezone.utc)
            else:
                created_at = datetime.now(timezone.utc)
        except Exception as e:
            logger.warning(f"Failed to parse created_at '{created_at_str}': {e}")
            created_at = datetime.now(timezone.utc)
        
        # Parse approved_at (optional)
        approved_at = None
        if approved_at_str:
            try:
                approved_at = datetime.fromisoformat(approved_at_str.replace('Z', '+00:00'))
                if approved_at.tzinfo is None:
                    approved_at = approved_at.replace(tzinfo=timezone.utc)
            except Exception as e:
                logger.warning(f"Failed to parse approved_at '{approved_at_str}': {e}")
                approved_at = None
        
        return VisitorResponse(
            visitor_id=visitor_dict.get('visitor_id', ''),
            society_id=visitor_dict.get('society_id', ''),
            flat_id=visitor_dict.get('flat_id', ''),
            visitor_type=visitor_dict.get('visitor_type', ''),
            visitor_phone=visitor_dict.get('visitor_phone', ''),
            status=visitor_dict.get('status', VisitorStatus.PENDING.value),
            created_at=created_at,
            approved_at=approved_at,
            approved_by=visitor_dict.get('approved_by'),
            guard_id=visitor_dict.get('guard_id', ''),
        )
    
    def _log_approval_request(self, flat: dict, visitor_data: dict):
        """
        Log approval request stub for resident
        
        This logs the approval request that would be sent via WhatsApp/SMS
        to the resident's phone number from the Flats sheet.
        """
        resident_phone = flat.get('resident_phone', '')
        flat_no = flat.get('flat_no', '')
        resident_name = flat.get('resident_name', '')
        visitor_type = visitor_data.get('visitor_type', '')
        visitor_phone = visitor_data.get('visitor_phone', '')
        visitor_id = visitor_data.get('visitor_id', '')
        
        # Log approval stub
        logger.info(
            f"APPROVAL_REQUEST_STUB | "
            f"To: {resident_phone} | "
            f"Flat: {flat_no} ({resident_name}) | "
            f"Visitor: {visitor_type} | "
            f"Phone: {visitor_phone} | "
            f"VisitorID: {visitor_id}"
        )
        
        # Also print for development visibility
        print(f"[APPROVAL_STUB] Would send to {resident_phone}:")
        print(f"  Flat: {flat_no} ({resident_name})")
        print(f"  Visitor: {visitor_type} - {visitor_phone}")
        print(f"  Visitor ID: {visitor_id}")
        print(f"  Message: Reply YES/NO to approve/reject")


# Singleton instance
_visitor_service: Optional[VisitorService] = None


def get_visitor_service() -> VisitorService:
    """Get singleton VisitorService instance"""
    global _visitor_service
    if _visitor_service is None:
        _visitor_service = VisitorService()
    return _visitor_service
