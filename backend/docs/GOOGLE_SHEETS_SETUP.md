# Google Sheets Service Account Setup Guide

This guide will help you set up Google Sheets as the database for GateFlow.

## Step 1: Create Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Click "Select a project" → "New Project"
3. Name it `gateflow` (or any name you prefer)
4. Click "Create"

## Step 2: Enable Google Sheets API

1. In your project, go to **APIs & Services** → **Library**
2. Search for "Google Sheets API"
3. Click on it and press **Enable**

## Step 3: Create Service Account

1. Go to **APIs & Services** → **Credentials**
2. Click **Create Credentials** → **Service Account**
3. Fill in:
   - **Service account name**: `gateflow-sheets`
   - **Service account ID**: `gateflow-sheets` (auto-filled)
   - **Description**: "Service account for GateFlow Google Sheets access"
4. Click **Create and Continue**
5. Skip the optional steps (Grant access, Grant users access)
6. Click **Done**

## Step 4: Create and Download Service Account Key

1. In the **Credentials** page, find your service account
2. Click on the service account email
3. Go to the **Keys** tab
4. Click **Add Key** → **Create new key**
5. Select **JSON** format
6. Click **Create**
7. A JSON file will download - **save this as `credentials.json`**
8. **Move `credentials.json` to the `backend/` directory**

⚠️ **Important**: Never commit `credentials.json` to git (it's already in `.gitignore`)

## Step 5: Create Google Spreadsheet

1. Go to [Google Sheets](https://sheets.google.com/)
2. Create a new blank spreadsheet
3. Name it "GateFlow Database" (or any name)
4. **Copy the Spreadsheet ID** from the URL:
   ```
   https://docs.google.com/spreadsheets/d/SPREADSHEET_ID_HERE/edit
   ```
   The `SPREADSHEET_ID_HERE` is what you need.

## Step 6: Share Spreadsheet with Service Account

1. In your Google Sheet, click **Share** button (top right)
2. Get the service account email from `credentials.json`:
   - Open `credentials.json`
   - Find the `client_email` field (looks like: `gateflow-sheets@project-id.iam.gserviceaccount.com`)
3. Paste the service account email in the "Add people" field
4. Give it **Editor** permissions
5. Uncheck "Notify people" (service accounts don't need notifications)
6. Click **Share**

## Step 7: Create Sheets Structure

Create three sheets in your spreadsheet with these exact headers:

### Sheet 1: "Flats"
| flat_id | society_id | flat_no | resident_name | resident_phone | resident_alt_phone | role | active |
|---------|------------|---------|---------------|----------------|-------------------|------|--------|

### Sheet 2: "Guards"
| guard_id | society_id | guard_name | pin | active |
|----------|------------|------------|-----|--------|

### Sheet 3: "Visitors"
| visitor_id | society_id | flat_id | visitor_type | visitor_phone | status | created_at | approved_at | approved_by | guard_id |
|------------|------------|---------|--------------|---------------|--------|------------|-------------|-------------|----------|

## Step 8: Configure Environment

1. Create `.env` file in `backend/` directory:
   ```bash
   cd backend
   cp .env.example .env  # if .env.example exists
   ```

2. Add your spreadsheet ID:
   ```env
   SHEETS_SPREADSHEET_ID=544872854
   GOOGLE_SHEETS_CREDENTIALS_PATH=credentials.json
   ```

## Step 9: Test the Connection

Run the backend server:
```bash
cd backend
uvicorn app.main:app --reload
```

If everything is set up correctly, the server should start without errors.

## Troubleshooting

### Error: "FileNotFoundError: credentials.json"
- Make sure `credentials.json` is in the `backend/` directory
- Check the file path in `.env` matches your file location

### Error: "Permission denied" or "Insufficient permissions"
- Make sure you shared the spreadsheet with the service account email
- Verify the service account has **Editor** permissions (not Viewer)

### Error: "Spreadsheet not found"
- Verify `SHEETS_SPREADSHEET_ID` in `.env` is correct
- Make sure the spreadsheet ID is from the URL (not the full URL)

### Error: "Sheet not found"
- Make sure sheet names match exactly: "Flats", "Guards", "Visitors" (case-sensitive)
- Ensure all three sheets exist in your spreadsheet with proper headers

## Security Notes

- ✅ `credentials.json` is in `.gitignore` - never commit it
- ✅ Service account has minimal permissions (only Sheets API)
- ✅ Spreadsheet is private by default (only shared with service account)
- ⚠️ Keep `credentials.json` secure - treat it like a password
