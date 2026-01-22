# Push Notifications Setup Guide

This guide explains how to set up push notifications with sound for GateFlow.

## Overview

GateFlow uses Firebase Cloud Messaging (FCM) to send push notifications with sound when:
- **Admin creates a new notice** → All users (guards, residents, admins) receive notification
- **Guard creates a visitor entry** → Resident receives notification

## Prerequisites

1. Firebase project
2. Android app registered in Firebase Console
3. iOS app registered in Firebase Console (if supporting iOS)

## Setup Steps

### 1. Firebase Console Setup

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project or select existing project
3. Add Android app:
   - Package name: `com.gateflow.app` (or your package name)
   - Download `google-services.json`
   - Place it in `mobile/android/app/`
4. Add iOS app (if needed):
   - Bundle ID: `com.gateflow.app` (or your bundle ID)
   - Download `GoogleService-Info.plist`
   - Place it in `mobile/ios/Runner/`

### 2. Backend Setup

1. **Get Firebase Admin SDK credentials:**
   - In Firebase Console → Project Settings → Service Accounts
   - Click "Generate New Private Key"
   - Save the JSON file as `firebase_service_account.json` in `backend/` directory

2. **Update `.env` file:**
   ```env
   FIREBASE_SERVICE_ACCOUNT_PATH=firebase_service_account.json
   ```

3. **Install dependencies:**
   ```bash
   cd backend
   pip install -r requirements.txt
   ```

### 3. Flutter App Setup

1. **Install dependencies:**
   ```bash
   cd mobile
   flutter pub get
   ```

2. **Android Configuration:**

   Add to `mobile/android/app/build.gradle`:
   ```gradle
   dependencies {
       // ... existing dependencies
       implementation platform('com.google.firebase:firebase-bom:32.7.0')
       implementation 'com.google.firebase:firebase-messaging'
   }
   ```

   Add notification sound file:
   - Create `mobile/android/app/src/main/res/raw/notification_sound.mp3`
   - Add your notification sound file (e.g., a short beep or chime)

3. **iOS Configuration (if supporting iOS):**

   Add to `mobile/ios/Podfile`:
   ```ruby
   pod 'Firebase/Messaging'
   ```

   Add notification sound file:
   - Create `mobile/ios/Runner/notification_sound.caf`
   - Convert your sound file to `.caf` format

### 4. Notification Sound Files

**Android:**
- Format: MP3 or OGG
- Location: `mobile/android/app/src/main/res/raw/notification_sound.mp3`
- Recommended: Short, pleasant sound (1-2 seconds)

**iOS:**
- Format: CAF (Core Audio Format)
- Location: `mobile/ios/Runner/notification_sound.caf`
- Convert MP3 to CAF:
  ```bash
  afconvert notification_sound.mp3 notification_sound.caf -d ima4 -f caff -v
  ```

### 5. Testing

1. **Test notice notification:**
   - Login as admin
   - Create a new notice
   - All users should receive notification with sound

2. **Test visitor notification:**
   - Login as guard
   - Create a new visitor entry
   - Resident should receive notification with sound

## Notification Topics

The app uses FCM topics for broadcasting:

- **Society-wide notices:** `society_{society_id}`
  - Example: `society_soc_ajmer_01`
  - All users in a society subscribe to this topic

- **Flat-specific visitors:** `flat_{flat_id}`
  - Example: `flat_flat_001`
  - Residents subscribe to their flat's topic

## Troubleshooting

### Notifications not received:

1. **Check Firebase initialization:**
   - Verify `google-services.json` is in correct location
   - Check backend logs for Firebase initialization errors

2. **Check FCM token:**
   - Check Flutter logs for FCM token
   - Verify token is being generated

3. **Check notification permissions:**
   - Ensure app has notification permissions
   - Check device notification settings

4. **Check backend logs:**
   - Look for notification sending errors
   - Verify Firebase service account file exists

### Sound not playing:

1. **Android:**
   - Verify sound file is in `res/raw/` directory
   - Check file name matches exactly: `notification_sound.mp3`
   - Ensure notification channel has sound enabled

2. **iOS:**
   - Verify sound file is in `Runner/` directory
   - Check file format is `.caf`
   - Ensure notification permissions include sound

## Security Notes

- Keep `firebase_service_account.json` secure (add to `.gitignore`)
- Never commit Firebase credentials to version control
- Use environment variables for sensitive configuration

## Future Enhancements

- Store FCM tokens in database for targeted notifications
- Add notification preferences per user
- Support for notification actions (approve/reject from notification)
- Rich notifications with images
