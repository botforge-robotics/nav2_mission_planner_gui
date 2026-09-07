# NavPro Mini GUI — Release & Deployment Guide

This document defines the strict versioning, release procedures, and multi-platform build workflow for the **NavPro Mini GUI** (`nav2_mission_planner_gui`). All future AI agents and developers MUST follow these guidelines.

---

## 1. Versioning Specification

NavPro Mini follows [Semantic Versioning 2.0.0](https://semver.org/):
```
v<MAJOR>.<MINOR>.<PATCH>
```
- **MAJOR**: Breaking changes to API bindings, core communications, or architecture.
- **MINOR**: New features, new cockpit panels, or enhancements (backwards compatible).
- **PATCH**: Bug fixes, styling refinements, and stability improvements.

### Single Source of Truth for Versioning
When bumping the version, you MUST update:
1. `pubspec.yaml`:
   ```yaml
   version: X.Y.Z+BUILD_NUMBER
   ```
2. `android/app/build.gradle`:
   ```groovy
   defaultConfig {
       applicationId = "com.botforge.navpromini"
       versionCode = BUILD_NUMBER
       versionName = "X.Y.Z"
   }
   ```

---

## 2. Supported Target Platforms & Artifacts

| Platform | Target Output | Artifact Name in Release |
|---|---|---|
| **Android** | Release APK | `NavProMini-Android.apk` |
| **Linux Desktop** | x86_64 tarball | `NavProMini-Linux-x86_64.tar.gz` |
| **Windows Desktop** | x64 ZIP | `NavProMini-Windows-x64.zip` |
| **Web (PWA)** | Web Bundle | GitHub Pages (`/nav2_mission_planner_gui/`) |

### Identity Constants
- **Android Package / Application ID**: `com.botforge.navpromini`
- **Application Label / Window Title**: `NavPro Mini`

---

## 3. Branching & Deployment Strategy

To ensure client and robot stability:
- **`dev` (Internal Development)**:
  - All day-to-day feature development, experimentation, and internal company testing occur on `dev`.
  - Work-in-progress code remains on `dev` and is never pushed directly to the public release branch.
- **`navpro-mini` (Public Production)**:
  - This is the official public release branch.
  - When changes are fully tested and ready for release, merge `dev` into `navpro-mini`:
    ```bash
    git checkout navpro-mini
    git merge dev --ff-only
    git push origin navpro-mini
    ```
- **Release Tags (`v*`)**:
  - Tags (`vX.Y.Z`) are cut strictly from `navpro-mini` to trigger the automated GitHub Actions CI/CD release workflow.

---

## 4. How to Trigger an Automated Multi-Platform Release

The repository uses GitHub Actions (`.github/workflows/release.yml`) to automatically compile Linux, Android, and Windows binaries and attach them to a GitHub Release.

### Step-by-Step Release Procedure
1. Ensure the working tree is clean and all tests/analysis pass:
   ```bash
   flutter analyze
   ```
2. Bump the version in `pubspec.yaml` and `android/app/build.gradle`.
3. Commit and push changes to `navpro-mini`:
   ```bash
   git add pubspec.yaml android/app/build.gradle
   git commit -m "chore(release): bump version to vX.Y.Z"
   git push origin navpro-mini
   ```
4. Create and push a Git release tag:
   ```bash
   git tag -a vX.Y.Z -m "NavPro Mini Release vX.Y.Z"
   git push origin vX.Y.Z
   ```
5. GitHub Actions will trigger automatically:
   - Compiles `NavProMini-Android.apk`
   - Compiles `NavProMini-Linux-x86_64.tar.gz`
   - Compiles `NavProMini-Windows-x64.zip`
   - Publishes GitHub Release under tag `vX.Y.Z` with auto-generated release notes and attached assets.
6. The in-app `SoftwareUpdateScreen` will instantly discover the new version and provide direct one-tap download buttons for all platforms!

---

## 5. Local Build Commands

To build artifacts locally without CI:

### Android APK
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### Linux Desktop
```bash
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
flutter build linux --release
# Output: build/linux/x64/release/bundle/
```

### Windows Desktop (On Windows machine)
```powershell
flutter build windows --release
# Output: build\windows\x64\runner\Release\
```

### Web
```bash
flutter build web --release --base-href /nav2_mission_planner_gui/
# Output: build/web/
```
