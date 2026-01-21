"""
Google Sheets client for GateFlow
Handles all interactions with Google Sheets
"""

import os
from typing import List, Dict, Optional

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

from app.config import settings

settings.GOOGLE_SERVICE_ACCOUNT_FILE


class SheetsClient:
    """Google Sheets client wrapper"""

    def __init__(self):
        self.service = None
        self.spreadsheet_id = settings.SHEETS_SPREADSHEET_ID

        # Validate configuration
        if not self.spreadsheet_id:
            raise ValueError(
                "SHEETS_SPREADSHEET_ID is not set. "
                "Please set it in .env file or environment variable."
            )

        self._initialize_service()
        self._validate_connection()

    def _initialize_service(self):
        """Initialize Google Sheets API service"""
        try:
            creds_path = settings.GOOGLE_SHEETS_CREDENTIALS_PATH
            if not os.path.exists(creds_path):
                raise FileNotFoundError(
                    f"Google Sheets credentials file not found: {creds_path}\n"
                    f"Please download the service account JSON key and save it as '{creds_path}'"
                )

            credentials = service_account.Credentials.from_service_account_file(
                creds_path,
                scopes=["https://www.googleapis.com/auth/spreadsheets"],
            )

            self.service = build("sheets", "v4", credentials=credentials)
        except FileNotFoundError:
            raise
        except Exception as e:
            raise Exception(
                f"Failed to initialize Google Sheets service: {str(e)}\n"
                f"Please check that credentials.json is valid and Google Sheets API is enabled."
            )

    def _validate_connection(self):
        """Validate that we can access the spreadsheet"""
        try:
            self.service.spreadsheets().get(spreadsheetId=self.spreadsheet_id).execute()
        except HttpError as e:
            if e.resp.status == 404:
                raise ValueError(
                    f"Spreadsheet not found. Check that SHEETS_SPREADSHEET_ID "
                    f"is correct: {self.spreadsheet_id}"
                )
            elif e.resp.status == 403:
                raise PermissionError(
                    f"Permission denied. Make sure the spreadsheet is shared with "
                    f"the service account email (check credentials.json for 'client_email')"
                )
            else:
                raise Exception(f"Error accessing spreadsheet: {str(e)}")

    def _get_sheet_values(self, sheet_name: str, range_name: str = None) -> List[List]:
        """Get values from a sheet"""
        try:
            if range_name:
                range_str = f"{sheet_name}!{range_name}"
            else:
                range_str = sheet_name

            result = (
                self.service.spreadsheets()
                .values()
                .get(spreadsheetId=self.spreadsheet_id, range=range_str)
                .execute()
            )

            return result.get("values", [])
        except HttpError as e:
            raise Exception(f"Error reading from sheet {sheet_name}: {str(e)}")

    def _append_to_sheet(self, sheet_name: str, values: List[List]) -> Dict:
        """Append values to a sheet"""
        try:
            body = {"values": values}
            result = (
                self.service.spreadsheets()
                .values()
                .append(
                    spreadsheetId=self.spreadsheet_id,
                    range=f"{sheet_name}!A:Z",
                    valueInputOption="RAW",
                    insertDataOption="INSERT_ROWS",
                    body=body,
                )
                .execute()
            )
            return result
        except HttpError as e:
            raise Exception(f"Error appending to sheet {sheet_name}: {str(e)}")

    def _update_sheet(self, sheet_name: str, range_name: str, values: List[List]) -> Dict:
        """Update values in a sheet"""
        try:
            body = {"values": values}
            result = (
                self.service.spreadsheets()
                .values()
                .update(
                    spreadsheetId=self.spreadsheet_id,
                    range=f"{sheet_name}!{range_name}",
                    valueInputOption="RAW",
                    body=body,
                )
                .execute()
            )
            return result
        except HttpError as e:
            raise Exception(f"Error updating sheet {sheet_name}: {str(e)}")

    # Flats operations
    def get_flats(self, society_id: Optional[str] = None) -> List[Dict]:
        """Get all flats, optionally filtered by society_id"""
        rows = self._get_sheet_values(settings.SHEET_FLATS)
        if not rows:
            return []

        headers = rows[0]
        flats = []

        for row in rows[1:]:
            if len(row) < len(headers):
                row.extend([""] * (len(headers) - len(row)))

            flat = dict(zip(headers, row))

            if society_id and flat.get("society_id") != society_id:
                continue

            if flat.get("active", "").lower() != "true":
                continue

            flats.append(flat)

        return flats

    def get_flat_by_id(self, flat_id: str, active_only: bool = False) -> Optional[Dict]:
        """
        Get a flat by flat_id
        """
        rows = self._get_sheet_values(settings.SHEET_FLATS)
        if not rows:
            return None

        headers = rows[0]

        for row in rows[1:]:
            if len(row) < len(headers):
                row.extend([""] * (len(headers) - len(row)))

            flat = dict(zip(headers, row))

            if flat.get("flat_id") == flat_id:
                if active_only and flat.get("active", "").lower() != "true":
                    return None
                return flat

        return None

    # Guards operations

    # Guards operations in client.py
    def get_guards(self, society_id: Optional[str] = None) -> List[Dict]:
        """Get all guards, optionally filtered by society_id"""
        try:
            rows = self._get_sheet_values(settings.SHEET_GUARDS)
            if not rows or len(rows) < 2:
                return []

            headers = [str(h).strip().lower() for h in rows[0]] # Normalize headers
            guards = []

            for row in rows[1:]:
                # Pad row to match headers length
                if len(row) < len(headers):
                    row.extend([""] * (len(headers) - len(row)))

                guard = dict(zip(headers, row))

                # SOCIETY FILTER
                if society_id and guard.get("society_id") != society_id:
                    continue

                # ✅ SAFE ACTIVE CHECK: Converts None to "" to prevent .lower() crash
                active_val = str(guard.get("active") or "").lower().strip()
                if active_val != "true":
                    continue

                guards.append(guard)

            return guards
        except Exception as e:
            print(f"ERROR in get_guards: {e}")
            return []

    def get_guard_by_id(self, guard_id: str) -> Optional[Dict]:
        """Get a guard by guard_id specifically"""
        # We call the sheet values directly to avoid double-filtering
        rows = self._get_sheet_values(settings.SHEET_GUARDS)
        if not rows or len(rows) < 2:
            return None

        headers = [str(h).strip().lower() for h in rows[0]]
        
        for row in rows[1:]:
            if len(row) < len(headers):
                row.extend([""] * (len(headers) - len(row)))
            
            guard = dict(zip(headers, row))
            
            # Check ID and Active status
            if str(guard.get("guard_id")).strip() == str(guard_id).strip():
                active_val = str(guard.get("active") or "").lower().strip()
                if active_val == "true":
                    return guard
        return None

    def get_guard_by_pin(self, society_id: str, pin: str) -> Optional[Dict]:
        """Get a guard by society_id and PIN"""
        guards = self.get_guards(society_id=society_id)
        for guard in guards:
            if guard.get("pin") == pin:
                return guard
        return None

    # Visitors operations
    def create_visitor(self, visitor_data: Dict) -> Dict:
        """
        Create a new visitor entry (append-only)

        ✅ IMPORTANT:
        Writes the row using the Visitors sheet headers order.
        This makes it safe even if columns are added/reordered (like flat_no).
        """
        
        rows = self._get_sheet_values(settings.SHEET_VISITORS)

        if not rows:
            raise ValueError(
                f"Sheet '{settings.SHEET_VISITORS}' is empty or headers are missing. "
                f"Please ensure the sheet exists with proper headers."
            )

        headers = rows[0]

        # Build row in exact header order
        row = []
        for h in headers:
            key = (h or "").strip()
            row.append(visitor_data.get(key, ""))

        self._append_to_sheet(settings.SHEET_VISITORS, [row])
        return visitor_data

    

    def get_visitors(
        self,
        society_id: Optional[str] = None,
        flat_id: Optional[str] = None,
        flat_no: Optional[str] = None,
        guard_id: Optional[str] = None,
        date_filter: Optional[str] = None,
    ) -> List[Dict]:

        rows = self._get_sheet_values(settings.SHEET_VISITORS)
        if not rows:
            return []

        headers = rows[0]
        visitors = []

        flat_no_norm = (flat_no or "").strip() if flat_no else None

        for row in rows[1:]:
            if len(row) < len(headers):
                row.extend([''] * (len(headers) - len(row)))

            visitor = dict(zip(headers, row))

            # society filter
            if society_id and visitor.get("society_id") != society_id:
                continue

            # guard filter
            if guard_id and visitor.get("guard_id") != guard_id:
                continue

            # flat_id filter
            if flat_id and visitor.get("flat_id") != flat_id:
                continue

            # ✅ flat_no filter (tolerant)
            if flat_no_norm:
                target = self._normalize_flat_no(flat_no_norm)
                v_flat_no = self._normalize_flat_no(visitor.get("flat_no") or "")
                if v_flat_no != target:
                    continue

            visitors.append(visitor)

        visitors.sort(key=lambda x: x.get("created_at", ""), reverse=True)
        return visitors



    def _normalize_flat_no(self, flat_no: str) -> str:
        """
        Normalize flat numbers for tolerant matching.
        Examples:
          "A-101" -> "A101"
          "a 101" -> "A101"
          "FLAT_101" -> "101"
          "flat- A-101" -> "A101"
        """
        s = (flat_no or "").strip().upper()
        s = s.replace("FLAT", "")
        s = s.replace("_", "")
        s = s.replace("-", "")
        s = s.replace(" ", "")
        return s

    def get_flat_by_no(self, society_id: str, flat_no: str, active_only: bool = False) -> Optional[Dict]:
        """
        Get a flat by society_id + flat_no (case-insensitive, trimmed)
        """
        rows = self._get_sheet_values(settings.SHEET_FLATS)
        if not rows:
            return None

        headers = rows[0]
        target = (flat_no or "").strip().upper()

        for row in rows[1:]:
            if len(row) < len(headers):
                row.extend([""] * (len(headers) - len(row)))

            flat = dict(zip(headers, row))

            if society_id and (flat.get("society_id", "") or "") != society_id:
                continue

            sheet_flat_no = (flat.get("flat_no", "") or "").strip().upper()

            if sheet_flat_no == target:
                if active_only:
                    if (flat.get("active", "") or "").strip().lower() != "true":
                        return None
                return flat

        return None



    def update_visitor_status(
        self,
        visitor_id: str,
        status: str,
        approved_at: str,
        approved_by: str,
        note: str = "",
    ) -> Optional[Dict]:
        """
        Update an existing visitor row by visitor_id.
        Assumes sheet headers include: visitor_id, status, approved_at, approved_by
        and optionally note.
        """
        rows = self._get_sheet_values(settings.SHEET_VISITORS)
        if not rows:
            return None

        headers = rows[0]
        header_map = {h: i for i, h in enumerate(headers)}

        if "visitor_id" not in header_map:
            raise ValueError("Visitors sheet missing 'visitor_id' header")

        # columns we want to update (only if present)
        status_col = header_map.get("status")
        approved_at_col = header_map.get("approved_at")
        approved_by_col = header_map.get("approved_by")
        note_col = header_map.get("note")  # optional

        # find row index
        for idx, row in enumerate(rows[1:], start=2):  # sheet rows are 1-based; + header => start=2
            # pad row
            if len(row) < len(headers):
                row.extend([""] * (len(headers) - len(row)))

            if row[header_map["visitor_id"]] == visitor_id:
                # update local row values
                if status_col is not None:
                    row[status_col] = status
                if approved_at_col is not None:
                    row[approved_at_col] = approved_at
                if approved_by_col is not None:
                    row[approved_by_col] = approved_by
                if note_col is not None:
                    row[note_col] = note

                # write whole row back
                range_name = f"A{idx}:"
                end_col_letter = chr(ord("A") + len(headers) - 1)
                range_name = f"A{idx}:{end_col_letter}{idx}"

                self._update_sheet(settings.SHEET_VISITORS, range_name, [row])

                return dict(zip(headers, row))

        return None



# Singleton instance
_sheets_client: Optional[SheetsClient] = None


def get_sheets_client() -> SheetsClient:
    """Get singleton SheetsClient instance"""
    global _sheets_client
    if _sheets_client is None:
        _sheets_client = SheetsClient()
    return _sheets_client
