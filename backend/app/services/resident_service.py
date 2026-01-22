import logging
from typing import Optional, List, Dict
from datetime import datetime, timezone
from fastapi import HTTPException

from app.sheets.client import get_sheets_client

logger = logging.getLogger(__name__)


class ResidentService:
    def __init__(self):
        self.sheets = get_sheets_client()

    def get_profile(self, society_id: str, flat_no: str, phone: Optional[str] = None) -> Dict:
        r = self.sheets.get_resident_by_flat_no(
            society_id=society_id,
            flat_no=flat_no,
            active_only=True,
            whatsapp_opt_in_only=False,
        )
        if not r:
            raise HTTPException(status_code=404, detail="Resident not found")

        if phone:
            p = phone.strip()
            sheet_phone = (r.get("resident_phone") or "").strip()
            alt_phone = (r.get("resident_alt_phone") or "").strip()
            if p and p != sheet_phone and p != alt_phone:
                raise HTTPException(status_code=401, detail="Phone mismatch")

        return {
            "resident_id": str(r.get("resident_id") or ""),
            "resident_name": str(r.get("resident_name") or ""),
            "society_id": str(r.get("society_id") or society_id),
            "flat_no": str(r.get("flat_no") or flat_no),
            "resident_phone": r.get("resident_phone") or "",
            "role": r.get("role") or "resident",
            "active": str(r.get("active") or "").strip().lower() == "true",
        }

    def pending_approvals(self, society_id: str, flat_no: str) -> List[Dict]:
        return self.sheets.get_visitors_by_flat(
            society_id=society_id,
            flat_no=flat_no,
            status="PENDING",
            limit=50,
        )

    def history(self, society_id: str, flat_no: str, limit: int = 50) -> List[Dict]:
        return self.sheets.get_visitors_by_flat(
            society_id=society_id,
            flat_no=flat_no,
            status="ALL_NON_PENDING",
            limit=limit,
        )

    def decide(
        self,
        society_id: str,
        flat_no: str,
        resident_id: str,
        visitor_id: str,
        decision: str,
        note: str = "",
    ) -> Dict:
        decision_up = decision.strip().upper()
        if decision_up not in ("APPROVED", "REJECTED"):
            raise HTTPException(status_code=400, detail="decision must be APPROVED or REJECTED")

        now = datetime.now(timezone.utc).isoformat()

        updated = self.sheets.update_visitor_status(
            visitor_id=visitor_id,
            status=decision_up,
            approved_at=now,
            approved_by=resident_id,
            note=note or "",
        )
        if not updated:
            raise HTTPException(status_code=404, detail="Visitor not found")

        return {"visitor_id": visitor_id, "status": decision_up, "updated": True}

    def save_fcm_token(self, society_id: str, flat_no: str, resident_id: str, fcm_token: str) -> None:
        ok = self.sheets.upsert_resident_fcm_token(
            society_id=society_id,
            flat_no=flat_no,
            resident_id=resident_id,
            fcm_token=fcm_token,
        )
        if not ok:
            raise HTTPException(status_code=400, detail="Unable to save fcm_token")



    def login_with_pin(self, society_id: str, phone: str, pin: str) -> Dict:
        """
        PIN-based resident login (MVP).
        Matches resident using society_id + phone + resident_pin in Residents sheet.
        Returns a payload compatible with ResidentLoginResponse.
        """
        society_id = (society_id or "").strip()
        phone = (phone or "").strip()
        pin = (pin or "").strip()

        if not society_id or not phone or not pin:
            raise HTTPException(status_code=400, detail="society_id, phone, pin are required")

        r = self.sheets.get_resident_by_phone_and_pin(
            society_id=society_id,
            phone=phone,
            pin=pin,
            active_only=True,
        )

        if not r:
            raise HTTPException(status_code=401, detail="Invalid credentials")

        # headers in get_residents are normalized to lowercase in your client
        return {
            "resident_id": str(r.get("resident_id") or "").strip() or "RESIDENT",
            "resident_name": str(r.get("resident_name") or "").strip() or "Resident",
            "society_id": str(r.get("society_id") or society_id).strip(),
            "flat_id": (str(r.get("flat_id") or "").strip() or None),
            "flat_no": (str(r.get("flat_no") or "").strip() or None),
            # Support both resident_phone and phone column names
            "phone": (str(r.get("resident_phone") or r.get("phone") or phone).strip() or None),
            "token": None,
        }




# Singleton instance + getter (no imports needed)
_resident_service = ResidentService()

def get_resident_service() -> ResidentService:
    return _resident_service
