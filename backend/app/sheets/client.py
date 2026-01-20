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
                scopes=['https://www.googleapis.com/auth/spreadsheets']
            )
            
            self.service = build('sheets', 'v4', credentials=credentials)
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
            # Try to get spreadsheet metadata
            self.service.spreadsheets().get(
                spreadsheetId=self.spreadsheet_id
            ).execute()
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
            
            result = self.service.spreadsheets().values().get(
                spreadsheetId=self.spreadsheet_id,
                range=range_str
            ).execute()
            
            return result.get('values', [])
        except HttpError as e:
            raise Exception(f"Error reading from sheet {sheet_name}: {str(e)}")
    
    def _append_to_sheet(self, sheet_name: str, values: List[List]) -> Dict:
        """Append values to a sheet"""
        try:
            body = {'values': values}
            result = self.service.spreadsheets().values().append(
                spreadsheetId=self.spreadsheet_id,
                range=f"{sheet_name}!A:Z",
                valueInputOption='RAW',
                insertDataOption='INSERT_ROWS',
                body=body
            ).execute()
            return result
        except HttpError as e:
            raise Exception(f"Error appending to sheet {sheet_name}: {str(e)}")
    
    def _update_sheet(self, sheet_name: str, range_name: str, values: List[List]) -> Dict:
        """Update values in a sheet"""
        try:
            body = {'values': values}
            result = self.service.spreadsheets().values().update(
                spreadsheetId=self.spreadsheet_id,
                range=f"{sheet_name}!{range_name}",
                valueInputOption='RAW',
                body=body
            ).execute()
            return result
        except HttpError as e:
            raise Exception(f"Error updating sheet {sheet_name}: {str(e)}")
    
    # Flats operations
    def get_flats(self, society_id: Optional[str] = None) -> List[Dict]:
        """Get all flats, optionally filtered by society_id"""
        rows = self._get_sheet_values(settings.SHEET_FLATS)
        if not rows:
            return []
        
        # First row is header
        headers = rows[0]
        flats = []
        
        for row in rows[1:]:
            if len(row) < len(headers):
                row.extend([''] * (len(headers) - len(row)))
            
            flat = dict(zip(headers, row))
            
            # Filter by society_id if provided
            if society_id and flat.get('society_id') != society_id:
                continue
            
            # Only return active flats
            if flat.get('active', '').lower() != 'true':
                continue
            
            flats.append(flat)
        
        return flats
    
    def get_flat_by_id(self, flat_id: str, active_only: bool = False) -> Optional[Dict]:
        """
        Get a flat by flat_id
        
        Args:
            flat_id: The flat ID to search for
            active_only: If True, only return if flat is active. If False, return regardless of active status.
        """
        rows = self._get_sheet_values(settings.SHEET_FLATS)
        if not rows:
            return None
        
        headers = rows[0]
        
        for row in rows[1:]:
            if len(row) < len(headers):
                row.extend([''] * (len(headers) - len(row)))
            
            flat = dict(zip(headers, row))
            
            if flat.get('flat_id') == flat_id:
                # If active_only is True, check active status
                if active_only:
                    if flat.get('active', '').lower() != 'true':
                        return None
                return flat
        
        return None
    
    # Guards operations
    def get_guards(self, society_id: Optional[str] = None) -> List[Dict]:
        """Get all guards, optionally filtered by society_id"""
        rows = self._get_sheet_values(settings.SHEET_GUARDS)
        if not rows:
            return []
        
        headers = rows[0]
        guards = []
        
        for row in rows[1:]:
            if len(row) < len(headers):
                row.extend([''] * (len(headers) - len(row)))
            
            guard = dict(zip(headers, row))
            
            # Filter by society_id if provided
            if society_id and guard.get('society_id') != society_id:
                continue
            
            # Only return active guards
            if guard.get('active', '').lower() != 'true':
                continue
            
            guards.append(guard)
        
        return guards
    
    def get_guard_by_id(self, guard_id: str) -> Optional[Dict]:
        """Get a guard by guard_id"""
        guards = self.get_guards()
        for guard in guards:
            if guard.get('guard_id') == guard_id:
                return guard
        return None
    
    def get_guard_by_pin(self, society_id: str, pin: str) -> Optional[Dict]:
        """Get a guard by society_id and PIN"""
        guards = self.get_guards(society_id=society_id)
        for guard in guards:
            if guard.get('pin') == pin:
                return guard
        return None
    
    # Visitors operations
    def create_visitor(self, visitor_data: Dict) -> Dict:
        """Create a new visitor entry (append-only)"""
        rows = self._get_sheet_values(settings.SHEET_VISITORS)
        
        # Headers must already exist in the sheet
        if not rows:
            raise ValueError(
                f"Sheet '{settings.SHEET_VISITORS}' is empty or headers are missing. "
                f"Please ensure the sheet exists with proper headers."
            )
        
        headers = rows[0]
        
        # Prepare row data in correct order
        row = [
            visitor_data.get('visitor_id', ''),
            visitor_data.get('society_id', ''),
            visitor_data.get('flat_id', ''),
            visitor_data.get('visitor_type', ''),
            visitor_data.get('visitor_phone', ''),
            visitor_data.get('status', 'PENDING'),
            visitor_data.get('created_at', ''),
            visitor_data.get('approved_at', ''),
            visitor_data.get('approved_by', ''),
            visitor_data.get('guard_id', ''),
        ]
        
        self._append_to_sheet(settings.SHEET_VISITORS, [row])
        return visitor_data
    
    def get_visitors(
        self,
        society_id: Optional[str] = None,
        flat_id: Optional[str] = None,
        guard_id: Optional[str] = None,
        date_filter: Optional[str] = None  # Format: YYYY-MM-DD
    ) -> List[Dict]:
        """Get visitors with optional filters"""
        rows = self._get_sheet_values(settings.SHEET_VISITORS)
        if not rows:
            return []
        
        headers = rows[0]
        visitors = []
        
        for row in rows[1:]:
            if len(row) < len(headers):
                row.extend([''] * (len(headers) - len(row)))
            
            visitor = dict(zip(headers, row))
            
            # Apply filters
            if society_id and visitor.get('society_id') != society_id:
                continue
            
            if flat_id and visitor.get('flat_id') != flat_id:
                continue
            
            if guard_id and visitor.get('guard_id') != guard_id:
                continue
            
            # Date filter (check if created_at starts with date_filter)
            if date_filter and visitor.get('created_at'):
                if not visitor.get('created_at', '').startswith(date_filter):
                    continue
            
            visitors.append(visitor)
        
        # Sort by created_at descending (most recent first)
        visitors.sort(key=lambda x: x.get('created_at', ''), reverse=True)
        
        return visitors


# Singleton instance
_sheets_client: Optional[SheetsClient] = None


def get_sheets_client() -> SheetsClient:
    """Get singleton SheetsClient instance"""
    global _sheets_client
    if _sheets_client is None:
        _sheets_client = SheetsClient()
    return _sheets_client
