"""
Notice service for managing society notices/announcements
"""

import uuid
from datetime import datetime
from typing import Optional, Dict, List
from app.sheets.client import get_sheets_client
from app.config import settings
import logging

logger = logging.getLogger(__name__)


def get_notice_service():
    """Get notice service instance"""
    return NoticeService()


class NoticeService:
    """Service for notice operations"""

    def __init__(self):
        self.sheets = get_sheets_client()

    def create_notice(
        self,
        society_id: str,
        admin_id: str,
        admin_name: str,
        title: str,
        content: str,
        notice_type: str = "GENERAL",
        priority: str = "NORMAL",
        expiry_date: Optional[str] = None,
    ) -> Dict:
        """
        Create a new notice
        Returns the created notice with notice_id and created_at
        
        ✅ IMPORTANT:
        Writes the row using the Notices sheet headers order.
        This makes it safe even if columns are added/reordered.
        """
        try:
            notice_id = str(uuid.uuid4())
            created_at = datetime.utcnow().isoformat() + "Z"
            is_active = "TRUE"  # For "is_active" field
            status_active = "ACTIVE"  # For "status" field (alternative header name)

            # Read headers first to get the correct column order
            try:
                rows = self.sheets._get_sheet_values(settings.SHEET_NOTICES)
            except Exception as e:
                logger.error(f"Error reading Notices sheet: {e}")
                raise ValueError(
                    f"Failed to read sheet '{settings.SHEET_NOTICES}'. "
                    f"Please ensure the sheet exists. Error: {str(e)}"
                )
            
            if not rows:
                raise ValueError(
                    f"Sheet '{settings.SHEET_NOTICES}' is empty or headers are missing. "
                    f"Please ensure the sheet exists with proper headers."
                )

            headers = rows[0]
            logger.info(f"Notices sheet headers: {headers}")

            # Build notice data dict (keys should match sheet headers)
            # Common header formats: "notice_id", "Notice ID", "Notice_ID", etc.
            # Default values for missing fields
            pinned_value = "FALSE"  # Default to not pinned
            status_value = "ACTIVE"  # Default status
            
            notice_data = {
                "notice_id": notice_id,
                "society_id": society_id,
                "admin_id": admin_id,
                "admin_name": admin_name,
                "created_by": admin_id,  # Also add created_by (alternative header name)
                "created_by_name": admin_name,  # Also add created_by_name
                "title": title,
                "content": content,
                "notice_type": notice_type,
                "priority": priority,
                "is_active": is_active,
                "status": status_value,  # Add status field
                "pinned": pinned_value,  # Add pinned field
                "created_at": created_at,
                "expiry_date": expiry_date or "",
            }
            
            # Also add variations for common header formats
            # Add space-separated versions
            notice_data["Notice ID"] = notice_id
            notice_data["Society ID"] = society_id
            notice_data["Admin ID"] = admin_id
            notice_data["Admin Name"] = admin_name
            notice_data["Created By"] = admin_id
            notice_data["Created By Name"] = admin_name
            notice_data["Notice Type"] = notice_type
            notice_data["Is Active"] = is_active
            notice_data["Status"] = status_value
            notice_data["Pinned"] = pinned_value
            notice_data["Created At"] = created_at
            notice_data["Expiry Date"] = expiry_date or ""
            
            logger.info(f"Notice data keys being prepared: {list(notice_data.keys())}")

            # Build row in exact header order (matching visitor creation pattern)
            row = []
            for h in headers:
                key = (h or "").strip()
                value = None
                
                # Try multiple matching strategies
                # 1. Exact match
                value = notice_data.get(key)
                
                # 2. Case-insensitive match
                if value is None:
                    for k, v in notice_data.items():
                        if str(k).strip().lower() == key.lower():
                            value = v
                            break
                
                # 3. Try with spaces replaced by underscores (and vice versa)
                if value is None:
                    key_variations = [
                        key.replace(" ", "_"),
                        key.replace("_", " "),
                        key.replace(" ", "_").lower(),
                        key.replace("_", " ").lower(),
                    ]
                    for var_key in key_variations:
                        if var_key in notice_data:
                            value = notice_data[var_key]
                            break
                
                # 4. Try title case and other case variations
                if value is None:
                    key_variations = [
                        key.title(),
                        key.upper(),
                        key.lower(),
                        key.capitalize(),
                    ]
                    for var_key in key_variations:
                        if var_key in notice_data:
                            value = notice_data[var_key]
                            break
                
                # 5. Special handling for common field name variations
                if value is None:
                    # Map common variations
                    field_mapping = {
                        "created_by": ["admin_id", "created_by", "admin id", "created by"],
                        "created_by_name": ["admin_name", "created_by_name", "admin name", "created by name"],
                        "pinned": ["pinned", "is_pinned", "is pinned"],
                        "status": ["status", "is_active", "is active", "state"],
                        "expiry_date": ["expiry_date", "expiry date", "expirydate", "expires_at", "expires at"],
                    }
                    
                    key_lower = key.lower().replace(" ", "_")
                    for mapped_key, variations in field_mapping.items():
                        if key_lower in variations:
                            for var_key in variations:
                                if var_key in notice_data:
                                    value = notice_data[var_key]
                                    break
                            if value:
                                break
                
                if value is None:
                    # Log missing header for debugging
                    logger.warning(
                        f"Notice header '{key}' not found in notice_data. "
                        f"Available keys: {list(notice_data.keys())}"
                    )
                    value = ""  # Default to empty string
                
                row.append(str(value) if value is not None else "")

            # Log the row being written for debugging
            logger.info(f"Writing notice row with {len(row)} columns")
            logger.info(f"Row data: {row}")
            logger.info(f"Header-to-value mapping:")
            for i, h in enumerate(headers):
                if i < len(row):
                    logger.info(f"  {h} = {row[i]}")
            
            # Append to Notices sheet
            try:
                self.sheets._append_to_sheet(settings.SHEET_NOTICES, [row])
                logger.info(f"Successfully created notice: {notice_id}")
            except Exception as e:
                logger.error(f"Error appending to Notices sheet: {e}")
                logger.error(f"Row data: {row}")
                logger.error(f"Headers: {headers}")
                raise Exception(f"Failed to append notice to sheet: {str(e)}")

            return notice_data
        except ValueError as e:
            # Re-raise ValueError as-is (sheet doesn't exist, etc.)
            raise
        except Exception as e:
            logger.error(f"Error creating notice: {e}", exc_info=True)
            raise Exception(f"Failed to create notice: {str(e)}")

    def get_all_notices(
        self,
        society_id: str,
        active_only: bool = True,
    ) -> List[Dict]:
        """Get all notices for a society"""
        try:
            rows = self.sheets._get_sheet_values(settings.SHEET_NOTICES)
            if not rows or len(rows) < 2:
                logger.info(f"No notices found in sheet (rows: {len(rows) if rows else 0})")
                return []

            # Normalize headers: convert to lowercase and replace spaces with underscores
            # This handles "Society ID" -> "society_id", "Notice ID" -> "notice_id", etc.
            original_headers = rows[0]
            headers = []
            for h in original_headers:
                header = str(h).strip()
                # Normalize: lowercase and replace spaces with underscores
                normalized = header.lower().replace(" ", "_")
                headers.append(normalized)
            
            logger.info(f"Reading notices with headers: {original_headers} -> normalized: {headers}")
            result = []

            for idx, row in enumerate(rows[1:], start=2):
                if len(row) < len(headers):
                    row.extend([""] * (len(headers) - len(row)))

                notice = dict(zip(headers, row))
                
                # Get society_id with multiple key variations
                notice_society_id = (
                    notice.get("society_id") or 
                    notice.get("society id") or
                    notice.get("societyid") or
                    ""
                ).strip()
                
                logger.debug(f"Row {idx}: notice_society_id='{notice_society_id}', looking for '{society_id}'")

                # Filter by society_id
                if notice_society_id != society_id:
                    logger.debug(f"Row {idx}: Skipping - society_id mismatch")
                    continue

                # Filter by active status if requested
                # Handle both "is_active" and "status" field names
                if active_only:
                    # Try multiple field name variations
                    status_value = (
                        notice.get("status") or  # Check "status" field first (your sheet uses this)
                        notice.get("Status") or
                        notice.get("is_active") or 
                        notice.get("is active") or
                        notice.get("isactive") or
                        ""
                    ).strip().upper()
                    
                    # Check if active: "TRUE" or "ACTIVE" both mean active
                    # If status is empty or not active, skip it
                    if status_value not in ["TRUE", "ACTIVE"]:
                        logger.debug(f"Row {idx}: Skipping - not active (status='{status_value}')")
                        continue
                else:
                    # When active_only=False, include all notices regardless of status
                    logger.debug(f"Row {idx}: Including notice (active_only=False, status='{notice.get('status') or notice.get('is_active')}')")
                
                # Check expiry date if active_only=True (only filter expired when showing active notices)
                # When active_only=False, show all notices including expired ones
                if active_only:
                    expiry_date = (
                        notice.get("expiry_date") or 
                        notice.get("expiry date") or
                        notice.get("expirydate") or
                        ""
                    )
                    if expiry_date and expiry_date.strip():
                        try:
                            expiry = datetime.fromisoformat(expiry_date.strip().replace("Z", "+00:00"))
                            if datetime.utcnow() > expiry:
                                logger.debug(f"Row {idx}: Skipping - expired")
                                continue  # Skip expired notices
                        except Exception as e:
                            logger.warning(f"Row {idx}: Error parsing expiry_date '{expiry_date}': {e}")
                            pass  # If date parsing fails, include the notice

                logger.info(f"Row {idx}: Including notice: {notice.get('title', 'Untitled')}")
                result.append(notice)

            logger.info(f"Found {len(result)} notices for society_id={society_id}, active_only={active_only}")

            # Sort by created_at descending (newest first)
            result.sort(
                key=lambda x: x.get("created_at") or x.get("created at") or "",
                reverse=True
            )

            return result
        except Exception as e:
            logger.error(f"Error getting notices: {e}", exc_info=True)
            return []

    def update_notice_status(
        self,
        notice_id: str,
        is_active: bool,
    ) -> Optional[Dict]:
        """
        Update notice active status (activate/deactivate)
        """
        try:
            rows = self.sheets._get_sheet_values(settings.SHEET_NOTICES)
            if not rows or len(rows) < 2:
                return None

            headers = [str(h).strip().lower() for h in rows[0]]
            header_map = {h: i for i, h in enumerate(headers)}

            if "notice_id" not in header_map:
                raise ValueError("Notices sheet missing 'notice_id' header")

            for idx, row in enumerate(rows[1:], start=2):
                if len(row) < len(headers):
                    row.extend([""] * (len(headers) - len(row)))

                notice = dict(zip(headers, row))

                if (notice.get("notice_id") or "").strip() != notice_id:
                    continue

                # Update is_active
                if "is_active" in header_map:
                    row[header_map["is_active"]] = "TRUE" if is_active else "FALSE"

                # Update the row
                end_col_letter = chr(ord("A") + len(headers) - 1)
                range_name = f"A{idx}:{end_col_letter}{idx}"
                self.sheets._update_sheet(settings.SHEET_NOTICES, range_name, [row])

                return dict(zip(headers, row))

            return None
        except Exception as e:
            logger.error(f"Error updating notice status: {e}")
            raise Exception(f"Failed to update notice: {str(e)}")

    def delete_notice(self, notice_id: str) -> bool:
        """
        Delete a notice by removing the row from Google Sheets
        """
        try:
            rows = self.sheets._get_sheet_values(settings.SHEET_NOTICES)
            if not rows or len(rows) < 2:
                logger.warning(f"No notices found in sheet")
                return False

            headers = rows[0]
            
            # Find the row index of the notice to delete
            for idx, row in enumerate(rows[1:], start=2):  # start=2 because row 1 is header, row 2 is first data
                if len(row) < len(headers):
                    row.extend([""] * (len(headers) - len(row)))
                
                # Try to find notice_id in various header formats
                notice_id_col_idx = None
                for col_idx, header in enumerate(headers):
                    header_lower = str(header).strip().lower()
                    if header_lower in ["notice_id", "notice id", "noticeid"]:
                        notice_id_col_idx = col_idx
                        break
                
                if notice_id_col_idx is None:
                    logger.error("Could not find 'notice_id' column in Notices sheet")
                    return False
                
                # Check if this row matches the notice_id
                row_notice_id = (row[notice_id_col_idx] if notice_id_col_idx < len(row) else "").strip()
                
                if row_notice_id == notice_id:
                    # Found the notice, delete the row
                    logger.info(f"Deleting notice {notice_id} at row {idx}")
                    self.sheets._delete_row(settings.SHEET_NOTICES, idx)
                    logger.info(f"Successfully deleted notice {notice_id}")
                    return True
            
            logger.warning(f"Notice {notice_id} not found in sheet")
            return False
        except Exception as e:
            logger.error(f"Error deleting notice: {e}", exc_info=True)
            raise Exception(f"Failed to delete notice: {str(e)}")
