"""
Complaint service for managing resident complaints
"""

import uuid
from datetime import datetime
from typing import Optional, Dict, List
from app.sheets.client import get_sheets_client
from app.config import settings
import logging

logger = logging.getLogger(__name__)


def get_complaint_service():
    """Get complaint service instance"""
    return ComplaintService()


class ComplaintService:
    """Service for complaint operations"""

    def __init__(self):
        self.sheets = get_sheets_client()

    def create_complaint(
        self,
        society_id: str,
        flat_no: str,
        resident_id: str,
        resident_name: str,
        title: str,
        description: str,
        category: str = "GENERAL",
    ) -> Dict:
        """
        Create a new complaint
        Returns the created complaint with complaint_id and created_at
        """
        try:
            complaint_id = str(uuid.uuid4())
            created_at = datetime.utcnow().isoformat() + "Z"
            status = "PENDING"

            # Prepare row data
            row_data = [
                complaint_id,
                society_id,
                flat_no,
                resident_id,
                resident_name,
                title,
                description,
                category,
                status,
                created_at,
                "",  # resolved_at
                "",  # resolved_by
                "",  # admin_response
            ]

            # Append to Complaints sheet
            self.sheets._append_to_sheet(settings.SHEET_COMPLAINTS, [row_data])

            return {
                "complaint_id": complaint_id,
                "society_id": society_id,
                "flat_no": flat_no,
                "resident_id": resident_id,
                "resident_name": resident_name,
                "title": title,
                "description": description,
                "category": category,
                "status": status,
                "created_at": created_at,
                "resolved_at": None,
                "resolved_by": None,
                "admin_response": None,
            }
        except Exception as e:
            logger.error(f"Error creating complaint: {e}")
            raise Exception(f"Failed to create complaint: {str(e)}")

    def get_resident_complaints(
        self,
        society_id: str,
        flat_no: str,
        resident_id: Optional[str] = None,
    ) -> List[Dict]:
        """Get complaints for a specific resident/flat"""
        try:
            rows = self.sheets._get_sheet_values(settings.SHEET_COMPLAINTS)
            if not rows or len(rows) < 2:
                return []

            headers = [str(h).strip().lower() for h in rows[0]]
            result = []

            for row in rows[1:]:
                if len(row) < len(headers):
                    row.extend([""] * (len(headers) - len(row)))

                complaint = dict(zip(headers, row))

                # Filter by society_id and flat_no
                if (complaint.get("society_id") or "").strip() != society_id:
                    continue

                # Normalize flat numbers for comparison (same logic as sheets client)
                complaint_flat = (complaint.get("flat_no") or "").strip().upper().replace(" ", "").replace("-", "")
                target_flat = flat_no.strip().upper().replace(" ", "").replace("-", "")
                if complaint_flat != target_flat:
                    continue

                # Optional: filter by resident_id
                if resident_id and (complaint.get("resident_id") or "").strip() != resident_id:
                    continue

                result.append(complaint)

            # Sort by created_at descending
            result.sort(
                key=lambda x: x.get("created_at") or "",
                reverse=True
            )

            return result
        except Exception as e:
            logger.error(f"Error getting resident complaints: {e}")
            return []

    def get_all_complaints(self, society_id: str, status: Optional[str] = None) -> List[Dict]:
        """Get all complaints for a society, optionally filtered by status"""
        try:
            rows = self.sheets._get_sheet_values(settings.SHEET_COMPLAINTS)
            if not rows or len(rows) < 2:
                return []

            headers = [str(h).strip().lower() for h in rows[0]]
            result = []

            for row in rows[1:]:
                if len(row) < len(headers):
                    row.extend([""] * (len(headers) - len(row)))

                complaint = dict(zip(headers, row))

                # Filter by society_id
                if (complaint.get("society_id") or "").strip() != society_id:
                    continue

                # Filter by status if provided
                if status:
                    complaint_status = (complaint.get("status") or "").strip().upper()
                    if complaint_status != status.upper():
                        continue

                result.append(complaint)

            # Sort by created_at descending
            result.sort(
                key=lambda x: x.get("created_at") or "",
                reverse=True
            )

            return result
        except Exception as e:
            logger.error(f"Error getting all complaints: {e}")
            return []

    def update_complaint_status(
        self,
        complaint_id: str,
        status: str,
        resolved_by: Optional[str] = None,
        admin_response: Optional[str] = None,
    ) -> Optional[Dict]:
        """
        Update complaint status (PENDING, IN_PROGRESS, RESOLVED, REJECTED)
        """
        try:
            rows = self.sheets._get_sheet_values(settings.SHEET_COMPLAINTS)
            if not rows or len(rows) < 2:
                return None

            headers = [str(h).strip().lower() for h in rows[0]]
            header_map = {h: i for i, h in enumerate(headers)}

            if "complaint_id" not in header_map:
                raise ValueError("Complaints sheet missing 'complaint_id' header")

            for idx, row in enumerate(rows[1:], start=2):
                if len(row) < len(headers):
                    row.extend([""] * (len(headers) - len(row)))

                complaint = dict(zip(headers, row))

                if (complaint.get("complaint_id") or "").strip() != complaint_id:
                    continue

                # Update status
                if "status" in header_map:
                    row[header_map["status"]] = status

                # Update resolved_at if status is RESOLVED
                if status.upper() == "RESOLVED" and "resolved_at" in header_map:
                    row[header_map["resolved_at"]] = datetime.utcnow().isoformat() + "Z"

                # Update resolved_by
                if resolved_by and "resolved_by" in header_map:
                    row[header_map["resolved_by"]] = resolved_by

                # Update admin_response
                if admin_response and "admin_response" in header_map:
                    row[header_map["admin_response"]] = admin_response

                # Update the row
                end_col_letter = chr(ord("A") + len(headers) - 1)
                range_name = f"A{idx}:{end_col_letter}{idx}"
                self.sheets._update_sheet(settings.SHEET_COMPLAINTS, range_name, [row])

                return dict(zip(headers, row))

            return None
        except Exception as e:
            logger.error(f"Error updating complaint status: {e}")
            raise Exception(f"Failed to update complaint: {str(e)}")
