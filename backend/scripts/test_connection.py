#!/usr/bin/env python3
"""
Simple read-only test to verify Google Sheets connection
Tests access to the Flats sheet only
"""

import sys
import os

# Add parent directory to path to import app modules
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from app.sheets.client import get_sheets_client
from app.config import settings


def test_connection():
    """Test Google Sheets connection - read-only test for Flats sheet"""
    
    print("🔍 Testing Google Sheets Connection (Read-Only)...")
    print()
    
    # Check configuration
    print("📋 Configuration:")
    print(f"   Spreadsheet ID: {settings.SHEETS_SPREADSHEET_ID or 'NOT SET'}")
    print(f"   Credentials Path: {settings.GOOGLE_SHEETS_CREDENTIALS_PATH}")
    print(f"   Testing Sheet: {settings.SHEET_FLATS}")
    print()
    
    # Check credentials file
    if not os.path.exists(settings.GOOGLE_SHEETS_CREDENTIALS_PATH):
        print(f"❌ Credentials file not found: {settings.GOOGLE_SHEETS_CREDENTIALS_PATH}")
        print("   Please download the service account JSON key and save it as 'credentials.json'")
        return False
    
    print(f"✓ Credentials file found: {settings.GOOGLE_SHEETS_CREDENTIALS_PATH}")
    
    # Test connection
    try:
        client = get_sheets_client()
        print("✓ Successfully connected to Google Sheets API")
        
        # Test spreadsheet access
        print(f"\n📊 Testing spreadsheet access...")
        spreadsheet = client.service.spreadsheets().get(
            spreadsheetId=settings.SHEETS_SPREADSHEET_ID
        ).execute()
        print(f"✓ Spreadsheet found: {spreadsheet.get('properties', {}).get('title', 'Unknown')}")
        
        # Test reading Flats sheet (read-only)
        print(f"\n📋 Testing read access to '{settings.SHEET_FLATS}' sheet...")
        flats_data = client._get_sheet_values(settings.SHEET_FLATS)
        
        if not flats_data:
            print(f"   ⚠️  Sheet '{settings.SHEET_FLATS}' is empty (no data rows)")
        else:
            print(f"   ✓ Successfully read '{settings.SHEET_FLATS}' sheet")
            print(f"   ✓ Found {len(flats_data)} row(s) (including header)")
            if len(flats_data) > 1:
                print(f"   ✓ Found {len(flats_data) - 1} data row(s)")
        
        print("\n✅ Connection test successful!")
        return True
        
    except ValueError as e:
        print(f"\n❌ Configuration Error: {e}")
        return False
    except PermissionError as e:
        print(f"\n❌ Permission Error: {e}")
        return False
    except Exception as e:
        print(f"\n❌ Connection Error: {e}")
        return False


if __name__ == "__main__":
    success = test_connection()
    sys.exit(0 if success else 1)
