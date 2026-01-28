import logging
from typing import Optional, List, Dict
from datetime import datetime, timezone
from fastapi import HTTPException

from app.sheets.client import get_sheets_client
from app.services.notification_service import get_notification_service

logger = logging.getLogger(__name__)


class ResidentService:
    def __init__(self):
        """
        Initialize resident service.

        In older deployments this always created a Google Sheets client and
        crashed the app if SHEETS_SPREADSHEET_ID / credentials were missing.
        To allow running without Sheets (Firebase-only mode), we now make the
        Sheets client **optional**:
        - If configuration is present → self.sheets is a real SheetsClient.
        - If configuration is missing → self.sheets is None and any Sheets-
          backed methods will fail at call time instead of preventing startup.
        """
        try:
            self.sheets = get_sheets_client()
        except Exception as e:
            logger.warning(
                "Google Sheets client not configured for ResidentService; "
                "Sheets-based endpoints will be unavailable. %s",
                e,
            )
            self.sheets = None

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

    def get_resident_profile(self, society_id: str, flat_no: str, phone: Optional[str] = None) -> Dict:
        """Alias for get_profile for router compatibility"""
        return self.get_profile(society_id=society_id, flat_no=flat_no, phone=phone)

    def get_pending_approvals(self, society_id: str, flat_no: str) -> List[Dict]:
        """Get pending approvals for a flat"""
        return self.pending_approvals(society_id=society_id, flat_no=flat_no)

    def decide_visitor(self, payload) -> Dict:
        """Approve/reject visitor - wrapper for decide method"""
        return self.decide(
            society_id=payload.society_id,
            flat_no=payload.flat_no,
            resident_id=payload.resident_id,
            visitor_id=payload.visitor_id,
            decision=payload.decision,
            note=payload.note or "",
        )

    def upsert_fcm_token(self, payload) -> None:
        """Upsert FCM token - wrapper for save_fcm_token"""
        return self.save_fcm_token(
            society_id=payload.society_id,
            flat_no=payload.flat_no,
            resident_id=payload.resident_id,
            fcm_token=payload.fcm_token,
        )

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

    def get_history(self, society_id: str, flat_no: str, limit: int = 50) -> List[Dict]:
        """Alias for history"""
        return self.history(society_id=society_id, flat_no=flat_no, limit=limit)

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

    def send_sos_alert(
        self,
        society_id: str,
        flat_no: str,
        resident_name: Optional[str],
        resident_phone: Optional[str],
        sos_id: Optional[str] = None,
    ) -> None:
        """
        Send SOS alert notification to all staff (guards/admins) in a society.
        Uses FCM topic `society_{society_id}_staff` which guards/admins subscribe to in the mobile app.
        """
        topic = f"society_{society_id}_staff"

        safe_name = (resident_name or "Resident").strip() or "Resident"
        safe_flat = (flat_no or "Unknown").strip() or "Unknown"
        safe_phone = (resident_phone or "Not available").strip() or "Not available"

        title = "🚨 SOS Alert"
        body = f"{safe_name} from Flat {safe_flat} needs help. Phone: {safe_phone}"

        svc = get_notification_service()
        ok = svc.send_to_topic(
            topic=topic,
            title=title,
            body=body,
            data={
                "type": "sos",
                "society_id": society_id,
                "flat_no": safe_flat,
                "resident_name": safe_name,
                "resident_phone": safe_phone,
                **({"sos_id": sos_id} if sos_id else {}),
            },
            sound="notification_sound",
        )

        if not ok:
            logger.warning("Failed to send SOS alert via FCM", extra={"topic": topic})



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

    def update_profile(
        self,
        resident_id: str,
        society_id: str,
        flat_no: str,
        resident_name: Optional[str] = None,
        resident_phone: Optional[str] = None,
    ) -> Dict:
        """
        Update resident profile information (name, phone).
        """
        updated = self.sheets.update_resident_profile(
            resident_id=resident_id,
            society_id=society_id,
            flat_no=flat_no,
            resident_name=resident_name,
            resident_phone=resident_phone,
        )
        
        if not updated:
            raise HTTPException(status_code=404, detail="Resident not found")
        
        # Return updated profile
        return self.get_profile(society_id=society_id, flat_no=flat_no)

    async def upload_profile_image(
        self,
        resident_id: str,
        society_id: str,
        flat_no: str,
        file,
    ) -> Dict:
        """
        Upload resident profile image.
        For MVP, we'll store the file path/URL in the Residents sheet.
        """
        import os
        import uuid
        from datetime import datetime
        
        # Create uploads directory if it doesn't exist
        upload_dir = "uploads/residents"
        os.makedirs(upload_dir, exist_ok=True)
        
        # Generate unique filename
        file_ext = os.path.splitext(file.filename)[1] or ".jpg"
        filename = f"{resident_id}_{uuid.uuid4().hex[:8]}{file_ext}"
        file_path = os.path.join(upload_dir, filename)
        
        # Save file
        with open(file_path, "wb") as f:
            content = await file.read()
            f.write(content)
        
        # Update resident record with image path
        updated = self.sheets.update_resident_image(
            resident_id=resident_id,
            society_id=society_id,
            flat_no=flat_no,
            image_path=file_path,
        )
        
        if not updated:
            raise HTTPException(status_code=404, detail="Resident not found")
        
        return {
            "ok": True,
            "image_path": file_path,
            "message": "Profile image uploaded successfully",
        }




# Singleton instance + getter (no imports needed)
_resident_service = ResidentService()

def get_resident_service() -> ResidentService:
    return _resident_service
