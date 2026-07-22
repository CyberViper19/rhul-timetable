# 🎓 Royal Holloway Timetable App

[![Download APK](https://img.shields.io/badge/Android-Download%20APK-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://github.com/CyberViper19/rhul-timetable/releases/latest/download/app-release.apk)
[![Download IPA](https://img.shields.io/badge/iOS-Download%20IPA-000000?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/CyberViper19/rhul-timetable/releases/latest/download/app-release.ipa)
[![Latest Release](https://img.shields.io/github/v/release/CyberViper19/rhul-timetable?color=orange&label=Latest%20Release&style=for-the-badge)](https://github.com/CyberViper19/rhul-timetable/releases/latest)

A modern, platform-matched mobile application built with Flutter for Royal Holloway, University of London students. Automatically syncs class schedules, assessment deadlines, room locations, and sends push notifications for timetable changes.

---

## 📱 Quick Downloads

The app is automatically compiled and updated every time new features or bug fixes are committed to this repository.

| Platform | Direct Download Link | Format | CI/CD Status |
|---|---|---|---|
| 🤖 **Android** | [📥 **Download app-release.apk**](https://github.com/CyberViper19/rhul-timetable/releases/latest/download/app-release.apk) | `.apk` | ![Build Status](https://img.shields.io/github/actions/workflow/status/CyberViper19/rhul-timetable/build.yml?branch=main&label=Build%20APK) |
| 🍎 **iOS (iPhone/iPad)** | [📥 **Download app-release.ipa**](https://github.com/CyberViper19/rhul-timetable/releases/latest/download/app-release.ipa) | `.ipa` | ![Build Status](https://img.shields.io/github/actions/workflow/status/CyberViper19/rhul-timetable/build.yml?branch=main&label=Build%20IPA) |

> 🔗 **All Releases & Build Artifacts**: You can also browse past releases and builds on the [GitHub Releases Page](https://github.com/CyberViper19/rhul-timetable/releases/latest).

---

## ✨ Features

- 🏢 **Direct RHUL Campus Scraper**: Automatically logs in and scrapes your live timetable directly from the university portal.
- 🎨 **Customizable Themes**:
  - **RHUL Theme (Default)**: Royal Holloway Pitch Black (`#000000`) & Campus Orange (`#F97316`).
  - **Colourful**: Slate & Vibrant Indigo.
  - **System Default**: Automatically matches your phone's dark/light mode.
  - **Dark Mode**: Pitch black & monochrome white with blue lecture accents.
  - **Light Mode**: Crisp white background with dark slate typography.
  - **iOS Default**: Native Apple Cupertino dark style.
- 🏷️ **Categorized Session Color-Coding**:
  - 📘 **Lectures**: Blue (`#3B82F6`)
  - 🔮 **Tutorials, Workshops & Seminars**: Purple / Violet (`#A855F7`)
  - 🧪 **Practicals & Computer Labs**: Cyan / Teal (`#06B6D4`)
  - 📙 **Assessments & Exams**: Royal Holloway Orange (`#F97316`)
  - 🟢 **Optional & Drop-ins**: Emerald Green (`#10B981`)
- 🔔 **Background Push Notifications & Change Detection**: Instant alerts when a lecture is cancelled, rooms move, or times are rescheduled.
- ⏳ **Assessment Deadline Countdown**: Dedicated assessments screen with customizable reminder intervals (1 hr, 1 day, 1 week, etc.).
- 🗺️ **Interactive Google Maps Campus Preview**: Tap any location inside lecture details to view embedded building maps or launch Google Maps.
- 🔒 **Hardware-Backed Encrypted Vault**: Credentials stored locally in AES-256 GCM Android Keystore or Apple Keychain.

---

## 📲 How to Install

### 🤖 Android (.apk)
1. Tap [Download app-release.apk](https://github.com/CyberViper19/rhul-timetable/releases/latest/download/app-release.apk) on your Android device.
2. Open the downloaded `.apk` file.
3. If prompted, allow "Install from unknown sources" in your browser settings.
4. Tap **Install** and open the app!

### 🍎 iOS (.ipa)
1. Tap [Download app-release.ipa](https://github.com/CyberViper19/rhul-timetable/releases/latest/download/app-release.ipa) on your Mac or iPhone.
2. Install via **AltStore**, **Sideloadly**, **TrollStore**, or your preferred iOS signing tool / Xcode.

---

## 🛠️ Development & Building Locally

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (v3.27.x or higher)
- Android SDK & Platform Tools (`adb`)
- Xcode (for iOS builds on macOS)

### Run Locally
```bash
# Clone the repository
git clone https://github.com/CyberViper19/rhul-timetable.git
cd rhul_timetable

# Install dependencies
flutter pub get

# Run on connected device or emulator
flutter run
```

---

## 📄 License
This project is for educational and student support purposes for Royal Holloway students.
