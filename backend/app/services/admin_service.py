"""
Admin service for managing society operations
"""

from typing import Optional, Dict, List
from app.sheets.client import get_sheets_client
from app.config import settings
import logging

logger = logging.getLogger(__name__)


def get_admin_service():
    """Get admin service instance"""
    return AdminService()


class AdminService:
    """Service for admin operations"""

    def __init__(self):
        self.sheets = get_sheets_client()

    def authenticate(self, society_id: str, admin_id: str, pin: str) -> Optional[Dict]:
        """
        Authenticate admin using Admins sheet (admin_id + pin).
        Columns expected: admin_id, society_id, admin_name, phone, pin, role, active
        """
        try:
            admin_id_norm = (admin_id or "").strip()
            pin_norm = (pin or "").strip()
            logger.info(f"[ADMIN_AUTH] society_id={society_id} admin_id={admin_id} pin={pin}")

            admins = self.sheets.get_admins(society_id=society_id)
            logger.info(f"[ADMIN_AUTH] admins_found={len(admins)} sample={admins[:1]}")

            for a in admins:
                a_id = str(a.get("admin_id") or "").strip()
                a_pin = str(a.get("pin") or "").strip()

                if a_id == admin_id_norm and a_pin == pin_norm:
                    return {
                        "admin_id": a_id,
                        "admin_name": str(a.get("admin_name") or "Admin").strip(),
                        "society_id": str(a.get("society_id") or society_id).strip(),
                        "role": str(a.get("role") or "ADMIN").strip(),
                    }

            return None
        except Exception as e:
            logger.error(f"Admin authentication error: {e}")
            return None


    def get_dashboard_stats(self, society_id: str) -> Dict:
        """Get dashboard statistics"""
        try:
            # Get all residents
            residents = self.sheets.get_residents(society_id=society_id)
            total_residents = len(residents)

            # Get all guards
            guards = self.sheets.get_guards(society_id=society_id)
            total_guards = len(guards)

            # Get all flats
            flats = self.sheets.get_flats(society_id=society_id)
            total_flats = len(flats)

            # Get visitors today
            visitors = self.sheets.get_visitors(society_id=society_id)
            from datetime import datetime, date
            today = date.today()
            visitors_today = []
            for v in visitors:
                created_at = v.get("created_at")
                if created_at:
                    try:
                        # Try parsing ISO format
                        if "T" in str(created_at):
                            dt = datetime.fromisoformat(str(created_at).replace("Z", "+00:00"))
                        else:
                            dt = datetime.fromisoformat(str(created_at))
                        if dt.date() == today:
                            visitors_today.append(v)
                    except:
                        pass
            
            pending_approvals = len([v for v in visitors_today if (v.get("status") or "").upper() == "PENDING"])
            approved_today = len([v for v in visitors_today if (v.get("status") or "").upper() == "APPROVED"])

            return {
                "total_residents": total_residents,
                "total_guards": total_guards,
                "total_flats": total_flats,
                "visitors_today": len(visitors_today),
                "pending_approvals": pending_approvals,
                "approved_today": approved_today,
            }
        except Exception as e:
            logger.error(f"Error getting dashboard stats: {e}")
            return {
                "total_residents": 0,
                "total_guards": 0,
                "total_flats": 0,
                "visitors_today": 0,
                "pending_approvals": 0,
                "approved_today": 0,
            }

    def get_all_residents(self, society_id: str) -> List[Dict]:
        """Get all residents for society"""
        return self.sheets.get_residents(society_id=society_id)

    def get_all_guards(self, society_id: str) -> List[Dict]:
        """Get all guards for society"""
        return self.sheets.get_guards(society_id=society_id)

    def get_all_flats(self, society_id: str) -> List[Dict]:
        """Get all flats for society"""
        return self.sheets.get_flats(society_id=society_id)

    def get_all_visitors(self, society_id: str, limit: int = 100) -> List[Dict]:
        """Get all visitors for society"""
        visitors = self.sheets.get_visitors(society_id=society_id)
        # Sort by created_at descending and limit
        visitors.sort(
            key=lambda x: x.get("created_at") or "",
            reverse=True
        )
        return visitors[:limit]

    def create_admin(
        self,
        society_id: str,
        admin_id: str,
        admin_name: str,
        pin: str,
        phone: Optional[str] = None,
        role: str = "ADMIN",
    ) -> Dict:
        """
        Create a new admin account.
        """
        try:
            return self.sheets.create_admin(
                society_id=society_id,
                admin_id=admin_id,
                admin_name=admin_name,
                pin=pin,
                phone=phone,
                role=role,
            )
        except ValueError as e:
            logger.error(f"Error creating admin: {e}")
            raise
        except Exception as e:
            logger.error(f"Unexpected error creating admin: {e}")
            raise

    async def upload_profile_image(
        self,
        admin_id: str,
        society_id: str,
        file,
    ) -> Dict:
        """
        Upload admin profile image.
        For MVP, we'll store the file path/URL in the Admins sheet.
        """
        import os
        import uuid
        
        # Create uploads directory if it doesn't exist
        upload_dir = "uploads/admins"
        os.makedirs(upload_dir, exist_ok=True)
        
        # Generate unique filename
        file_ext = os.path.splitext(file.filename)[1] or ".jpg"
        filename = f"{admin_id}_{uuid.uuid4().hex[:8]}{file_ext}"
        file_path = os.path.join(upload_dir, filename)
        
        # Save file
        with open(file_path, "wb") as f:
            content = await file.read()
            f.write(content)
        
        # Update admin record with image path
        updated = self.sheets.update_admin_image(
            admin_id=admin_id,
            society_id=society_id,
            image_path=file_path,
        )
        
        if not updated:
            from fastapi import HTTPException
            raise HTTPException(status_code=404, detail="Admin not found")
        
        return {
            "ok": True,
            "image_path": file_path,
            "message": "Profile image uploaded successfully",
        }
