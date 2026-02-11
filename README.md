# Sentinel (GateFlow) Monorepo Guide

Sentinel is a role-based society/apartment management app with Flutter mobile + FastAPI backend + Firebase.

## Repo Structure

```
gateflow/
  backend/   # FastAPI + Firebase Admin services
  mobile/    # Flutter app (Android + iOS)
  docs/      # product/engineering docs
```

## Core Functionalities

### Roles
- `Platform Super Admin` (global): approve/reject society creation requests.
- `Society Admin / Owner`: manage residents, guards, join requests, notices, complaints, SOS.
- `Resident`: approvals, visitor history, complaints, notices, SOS, profile.
- `Guard`: visitor entries, history, violations, directory lookups.

### Key Flows
- Phone OTP login for all user types.
- Moderated society creation (`society_creation_requests` -> backend approval).
- Resident/Admin join requests via `public_societies/.../join_requests`.
- Role-based dashboards and notification bell/drawer.
- FCM mobile notifications for supported scenarios.
- Units-based resident onboarding (`public_societies/{societyId}/units`).

## Prerequisites

- Flutter SDK (matching project constraints)
- Java 17 for Android builds
- Xcode (for iOS/macOS builds)
- Python 3.11+ (backend)
- Firebase project configured for app + backend

## Mobile (Flutter) - Run Commands

```bash
cd /Users/harshveersinghnirwan/Downloads/gateflow/mobile
flutter pub get
flutter run
```

Useful commands:

```bash
flutter analyze
flutter test
flutter clean
```

Android release build:

```bash
flutter build appbundle --release
# or
flutter build apk --release
```

iOS release build:

```bash
flutter build ios --release
```

Launcher icon regen:

```bash
flutter pub run flutter_launcher_icons
```

## Backend (FastAPI) - Run Commands

```bash
cd /Users/harshveersinghnirwan/Downloads/gateflow/backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

API docs:
- Swagger: `http://localhost:8000/docs`
- ReDoc: `http://localhost:8000/redoc`

## Firebase / Rules Commands

From `mobile/`:

```bash
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
```

## Units Upload (for resident unit dropdown)

Units are expected at:
- `public_societies/{societyId}/units/{unitId}`

Backend endpoint:
- `POST /admin/units/bulk-create` (super-admin token required)

Example:

```bash
curl -X POST "https://gateflow-society-management-app.onrender.com/admin/units/bulk-create" \
  -H "Authorization: Bearer <FIREBASE_ID_TOKEN>" \
  -H "Content-Type: application/json" \
  --data-binary @villa_units_L_01_80.json
```

## Android Keystore / Signing

Current Android signing is read from:
- `mobile/android/key.properties`
- `mobile/android/app/build.gradle` -> `signingConfigs.release`

Expected `key.properties` keys:

```properties
storePassword=...
keyPassword=...
keyAlias=...
storeFile=...
```

Create keystore (if needed):

```bash
keytool -genkey -v \
  -keystore /absolute/path/gateflow-release.keystore \
  -alias gateflow \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000
```

Recommended:
- Keep keystore files and `key.properties` out of git.
- Keep an encrypted backup of keystore + alias/password metadata.
- If any signing secret was exposed, rotate and replace keystore credentials.

## iOS Signing (High-Level)

- Open: `mobile/ios/Runner.xcworkspace`
- Set Team + Bundle ID in Xcode Signing & Capabilities.
- Use Apple certificates/profiles for release/TestFlight.

## Operational Notes

- Platform super admin identity should be managed from backend only via `platform_admins/{uid}`.
- Do not grant client write access to platform admin roots.
- Society creation should remain moderated through backend approval APIs.

## Related Docs

- `/Users/harshveersinghnirwan/Downloads/gateflow/docs/UNITS_BULK_UPLOAD.md`
- `/Users/harshveersinghnirwan/Downloads/gateflow/docs/NOTIFICATIONS_SETUP.md`
- `/Users/harshveersinghnirwan/Downloads/gateflow/mobile/FIRESTORE_INDEXES.md`
- `/Users/harshveersinghnirwan/Downloads/gateflow/backend/README.md`
- `/Users/harshveersinghnirwan/Downloads/gateflow/mobile/README.md`
