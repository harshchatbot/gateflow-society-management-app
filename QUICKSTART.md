# Sentinel Quickstart (Copy/Paste)

## 1) Backend - Run

```bash
cd /Users/harshveersinghnirwan/Downloads/gateflow/backend
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## 2) Mobile - Run

```bash
cd /Users/harshveersinghnirwan/Downloads/gateflow/mobile
flutter pub get
flutter run
```

## 3) Analyze / Test

```bash
cd /Users/harshveersinghnirwan/Downloads/gateflow/mobile
flutter analyze
flutter test
```

## 4) Firestore Rules / Indexes Deploy

```bash
cd /Users/harshveersinghnirwan/Downloads/gateflow/mobile
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
```

## 5) Regenerate App Icons

```bash
cd /Users/harshveersinghnirwan/Downloads/gateflow/mobile
flutter pub run flutter_launcher_icons
```

## 6) Android Release Build

```bash
cd /Users/harshveersinghnirwan/Downloads/gateflow/mobile
flutter build appbundle --release
```

APK build:

```bash
cd /Users/harshveersinghnirwan/Downloads/gateflow/mobile
flutter build apk --release
```

## 7) iOS Release Build

```bash
cd /Users/harshveersinghnirwan/Downloads/gateflow/mobile
flutter build ios --release
```

## 8) Bulk Upload Units (Backend API)

```bash
TOKEN="<FIREBASE_ID_TOKEN>"
curl -X POST "https://gateflow-society-management-app.onrender.com/admin/units/bulk-create" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  --data-binary @/Users/harshveersinghnirwan/Downloads/gateflow/backend/villa_units_L_01_80.json
```

## 9) Get Super Admin Token (temporary debug line)

Add in `PlatformSuperAdminConsoleScreen`:

```dart
final token = await FirebaseAuth.instance.currentUser?.getIdToken(true);
debugPrint('SUPER_ADMIN_ID_TOKEN=$token');
```

Then:

```bash
cd /Users/harshveersinghnirwan/Downloads/gateflow/mobile
flutter logs
```

Remove the debug token line after use.
