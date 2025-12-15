# Changelog

All notable changes to Nav2 Mission Planner will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2025-01-XX

### Added
- Open source release under MIT License
- Comprehensive documentation (README, CONTRIBUTING, CODE_OF_CONDUCT)
- Direct connection screen on app launch (no authentication required)

### Changed
- **BREAKING**: Removed Firebase authentication requirement
- **BREAKING**: Removed licensing and trial system
- **BREAKING**: Removed in-app purchase functionality
- Simplified app entry flow - users go directly to connection screen
- Updated version to 2.0.0 to reflect major architectural changes

### Removed
- Firebase authentication and services
- Google Sign-In integration
- License management system
- Trial and purchase screens
- In-app purchase dependencies
- Play Integrity checks
- Device registration for licensing

### Fixed
- App now launches directly without authentication barriers
- Simplified user experience for connecting to robots

## [1.7.0] - Previous Version

### Added
- Trial reset functionality for existing users
- Migration system for trial resets
- App usage tracking
- Enhanced robot setup wizard with TF frame configuration

### Changed
- Improved trial flow - trial starts only after first robot connection and teleop usage
- Updated trial reset popup with loading UI

---

For earlier versions, see git history.

