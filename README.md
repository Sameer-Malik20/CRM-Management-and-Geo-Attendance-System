# SusaGeo - CRM Management and Geo Attendance System

SusaGeo is a Flutter-based workforce attendance and leave management application built for Android and iOS. It combines geo-fencing, selfie attendance, admin controls, and attendance history in a single mobile app experience for field teams, site workers, and managers.

Last built by: Sameer Malik

## Core Highlights

- Flutter mobile app with one shared codebase for Android and iOS
- Firebase Authentication and Firebase Realtime Database integration
- Geo-fenced attendance based on allocated work sites
- Selfie-based face registration and face verification before attendance
- Render-hosted face backend with warm-up status handling for free-tier sleep
- Admin and super admin management tools
- Leave application, approval, rejection, and withdrawal tracking
- Attendance history with day view and date-range view

## Features Included

### Employee Features

- Employee login using Employee ID
- Super admin login using email and password
- Location-aware attendance marking
- Selfie attendance with face verification before `IN` and `OUT`
- Automatic `IN` / `OUT` validation to prevent duplicate marking
- Today attendance summary with first `IN`, last `OUT`, and timeline
- Attendance history that auto-loads today's records
- Date-based and date-range attendance history
- Leave application and leave status tracking
- Profile editing
- Password change from profile
- Profile photo upload from camera or gallery
- Face registration and face update from profile

### Admin Features

- Admin drawer with attendance and user-management tools
- Create employee credentials with password
- Optional email generation for workers without smartphones
- Edit employee profiles
- Reset face registration state
- Delete users from app data records
- Allocate sites with latitude, longitude, and attendance radius
- Single-photo admin attendance for any worker
- Group-photo admin attendance for up to 10 workers
- Auto-detect group photo mode for recognized workers
- Face registration by admin for workers
- Leave review with withdrawn leave visibility

### Super Admin Features

- Super admin login through email and password
- Create and manage other admins
- Full access across users, sites, attendance, and leave workflows
- CSV export of full users, sites, attendance, and leave data

### Face Attendance Features

- Face registration flow for employees and admin-assisted onboarding
- Face verification before selfie attendance
- Render-hosted backend status banner
- Warm-up indicator for sleeping Render free-tier server
- Green ready state when the face backend becomes available

## Current Selfie Attendance Flow

1. Register face from `Profile -> Register Face`
2. Open `Attendance Recorder`
3. Stay inside the allocated site radius
4. Selfie verification runs before marking attendance
5. `IN` is disabled if the user is already `IN`
6. `OUT` is disabled if the user is already `OUT`

## Admin Attendance Flow

### Single Photo

- Enter employee ID
- Load the worker profile
- Register face or mark attendance manually

### Group Photo

- Manual mode: select up to 10 workers, then capture
- Auto-detect mode: capture a group photo and let the backend identify recognized workers automatically

## Face Backend

The face backend lives in [face_backend/app.py](face_backend/app.py).

### Local Run

```bash
cd face_backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
python app.py
```

### Deployed Backend

- Render URL: `https://susageo-face-backend.onrender.com`
- Health check: `https://susageo-face-backend.onrender.com/health`

### App-to-Backend Configuration

- Default app backend URL is the deployed Render backend
- You can override it at build/run time:

```bash
flutter run --dart-define=FACE_API_BASE_URL=https://susageo-face-backend.onrender.com
```

For local testing on a physical device:

```bash
flutter run --dart-define=FACE_API_BASE_URL=http://YOUR_PC_IP:5050
```

## Firebase Setup

Add or replace `google-services.json` in `android/app/`.

This project uses Firebase Realtime Database and Firebase Authentication. The current data model expects:

- `EmployeeID/<employeeId> -> email`
- `users/<uid>` for profile, site allocation, and role flags
- `location/<siteKey>` for latitude, longitude, name, and radius
- `Attendance/<uid>` for attendance records
- `leaves/<uid>` for leave records

Enable Email/Password authentication in Firebase Auth.

Sample seed data is available in:

- [location-based-attendance-export.json](location-based-attendance-export.json)

## Running the Project

```bash
flutter pub get
flutter run
```

For Android debug build:

```bash
flutter build apk --debug --dart-define=FACE_API_BASE_URL=https://susageo-face-backend.onrender.com
```

## Technology Stack

- Flutter
- Dart
- Firebase Auth
- Firebase Realtime Database
- Google Maps
- Location / Geofencing
- Flask
- OpenCV
- Render

## Recent Additions In This Build

- SusaGeo branding
- Super admin flow
- Face backend deployment support
- Render warm-up status UI
- Selfie attendance verification
- Profile photo upload
- Admin attendance tools
- Auto group face detection
- CSV export for super admin
- Improved attendance history
- Better admin role separation

## New Updated Legacy Project Credits

- <a href="https://github.com/Sameer-Malik20">Sameer Malik</a>

