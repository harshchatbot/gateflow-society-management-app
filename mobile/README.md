# GateFlow Mobile (Guard App)

Flutter Android app for security guards to manage visitor entries.

## Setup

1. **Install Flutter dependencies:**
   ```bash
   cd mobile
   flutter pub get
   ```

2. **Configure API base URL:**
   - Copy `.env.example` to `.env` (if not exists)
   - Update `API_BASE_URL` in `.env` to match your backend URL
   - For Android emulator: `http://10.0.2.2:8000`
   - For physical device: `http://YOUR_COMPUTER_IP:8000`

3. **Run the app:**
   ```bash
   flutter run
   ```

## Features

- **Guard Login**: Society ID + PIN authentication
- **Session Persistence**: Guard session saved locally
- **New Visitor Entry**: Quick entry form (<15 seconds)
- **Visitor Types**: Guest, Delivery, Cab
- **Success Feedback**: Shows visitor ID and status after creation

## Project Structure

```
lib/
  main.dart                 # App entry point
  core/
    api_client.dart        # HTTP client (Dio)
    env.dart               # Environment variables
    storage.dart           # Local storage (SharedPreferences)
  models/
    guard.dart             # Guard model
    visitor.dart           # Visitor model
  screens/
    splash_screen.dart     # Initial screen (session check)
    guard_login_screen.dart # Login screen
    new_visitor_screen.dart # Visitor entry screen
```

## API Integration

- Uses Dio for HTTP requests
- Base URL from `.env` file
- Error handling with user-friendly messages
