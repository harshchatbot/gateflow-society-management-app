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
- **Confetti on Success**: Subtle burst on visitor creation

## Project Structure

```
lib/
  main.dart                 # App entry point
  core/
    api_client.dart        # HTTP client (Dio)
    env.dart               # Environment variables
    storage.dart           # Local storage (SharedPreferences)
    app_logger.dart        # Centralized logging
    app_error.dart         # Error mapping and user messages
    result.dart            # Lightweight Result<T> wrapper
  models/
    guard.dart             # Guard model
    visitor.dart           # Visitor model
  services/
    auth_service.dart      # Guard login service
    visitor_service.dart   # Visitor creation service
  screens/
    splash_screen.dart     # Initial screen (session check)
    guard_login_screen.dart # Login screen
    new_visitor_screen.dart # Visitor entry screen
  widgets/
    primary_button.dart    # Primary CTA with loading
    app_text_field.dart    # Reusable text field
    section_card.dart      # Card container
    status_chip.dart       # Status display
```

## API Integration

- Uses Dio for HTTP requests
- Base URL from `.env` file
- Error handling with user-friendly messages

## CHANGELOG (recent)

- Added centralized logging via `AppLogger` (uses `logger` package).
- Added `AppError` and `Result<T>` for consistent error handling and typed results.
- Upgraded UI with Material 3 theme, reusable widgets, segmented visitor type control.
- Added subtle confetti on successful visitor creation (uses `confetti` package).
- Improved snackbars with actionable, friendly messages; technical details stay in logs.
- Services layer (`auth_service`, `visitor_service`) now logs requests/responses and map errors to user messages.

### Debugging tips
- Ensure `.env` has `API_BASE_URL` and is bundled as an asset.
- Check logs (debug build) for request/response and error details.
- Network errors surface as friendly snackbars; inspect console logs for stack traces.
