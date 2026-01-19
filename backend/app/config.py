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

    GOOGLE_SERVICE_ACCOUNT_FILE: str = "credentials.json"

    
    # API Settings
    API_V1_PREFIX: str = "/api/v1"
    
    class Config:
        env_file = ".env"
        case_sensitive = True


settings = Settings()
