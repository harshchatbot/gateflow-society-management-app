# GateFlow Backend

FastAPI backend for GateFlow - Guard-first visitor management system.

## Setup

1. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

2. **Set up Google Sheets Service Account:**
   📖 **Follow the detailed guide:** [docs/GOOGLE_SHEETS_SETUP.md](docs/GOOGLE_SHEETS_SETUP.md)
   
   Quick steps:
   - Create Google Cloud project
   - Enable Google Sheets API
   - Create Service Account and download `credentials.json`
   - Place `credentials.json` in `backend/` directory
   - Create a Google Spreadsheet and share it with service account email

3. **Configure environment:**
   Create `.env` file in `backend/` directory:
   ```env
   SHEETS_SPREADSHEET_ID=your_spreadsheet_id_here
   GOOGLE_SHEETS_CREDENTIALS_PATH=credentials.json
   ```

4. **Test Connection:**
   ```bash
   python3 scripts/test_connection.py
   ```

5. **Run the server:**
   ```bash
   uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
   ```
   Or use the startup script:
   ```bash
   ./run.sh
   ```

## API Endpoints

### Guards
- `POST /api/guards/login` - Guard login (society_id + PIN)
- `GET /api/guards/{guard_id}/flats` - Get flats for guard's society

### Visitors
- `POST /api/visitors` - Create visitor entry
- `GET /api/visitors/today/{guard_id}` - Get today's visitors for a guard

## API Documentation

Once the server is running, visit:
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc
