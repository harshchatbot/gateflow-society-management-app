"""
Configuration settings for GateFlow backend
"""

from typing import Optional
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings"""
    
    # Google Sheets Configuration
    GOOGLE_SHEETS_CREDENTIALS_PATH: str = "credentials.json"
    SHEETS_SPREADSHEET_ID: str = ""
    
    # Sheet Names (must match existing sheet names exactly)
    SHEET_FLATS: str = "Flats"
    SHEET_GUARDS: str = "Guards"
    SHEET_VISITORS: str = "Visitors"
    SHEET_RESIDENTS: str = "Residents"
    SHEET_ADMINS: str = "Admins"
    SHEET_COMPLAINTS: str = "Complaints"
    SHEET_NOTICES: str = "Notices"

    GOOGLE_SERVICE_ACCOUNT_FILE: str = "credentials.json"

    
    # API Settings
    API_V1_PREFIX: str = "/api/v1"
    
    class Config:
        env_file = ".env"
        case_sensitive = True


    # ✅ Add WhatsApp fields (so env vars are accepted)
    WHATSAPP_TOKEN: Optional[str] = None
    WHATSAPP_PHONE_NUMBER_ID: Optional[str] = None
    WHATSAPP_API_VERSION: Optional[str] = "v21.0"
    WHATSAPP_WABA: Optional[str] = None
    WHATSAPP_VERIFY_TOKEN: Optional[str] = None    


settings = Settings()
