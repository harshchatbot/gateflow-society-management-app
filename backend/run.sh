#!/bin/bash

# GateFlow Backend Startup Script

echo "Starting GateFlow Backend..."
echo "Make sure you have:"
echo "  1. Created .env file with SHEETS_SPREADSHEET_ID"
echo "  2. Placed credentials.json in backend directory"
echo "  3. Set up Google Sheets with Flats, Guards, and Visitors sheets"
echo ""

uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
