# Contributing to Nav2 Mission Planner

Thank you for your interest in contributing to Nav2 Mission Planner! This document provides guidelines and instructions for contributing.

## Code of Conduct

By participating in this project, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

## How to Contribute

### Reporting Bugs

1. Check if the bug has already been reported in [Issues](https://github.com/yourusername/nav2_mission_planner/issues)
2. If not, create a new issue with:
   - Clear, descriptive title
   - Steps to reproduce
   - Expected vs actual behavior
   - Device/OS information
   - Relevant logs or screenshots

### Suggesting Features

1. Check existing feature requests in [Issues](https://github.com/yourusername/nav2_mission_planner/issues)
2. Create a new issue with:
   - Clear description of the feature
   - Use case and motivation
   - Proposed implementation (if you have ideas)

### Pull Requests

1. **Fork the repository**
2. **Create a feature branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Make your changes**:
   - Follow the code style guidelines
   - Write or update tests if applicable
   - Update documentation as needed
4. **Commit your changes**:
   ```bash
   git commit -m "Add: Description of your changes"
   ```
   Use clear, descriptive commit messages.
5. **Push to your fork**:
   ```bash
   git push origin feature/your-feature-name
   ```
6. **Create a Pull Request**:
   - Provide a clear description of changes
   - Reference any related issues
   - Include screenshots for UI changes

## Development Setup

### Prerequisites

- Flutter SDK 3.6.1 or later
- Dart SDK (comes with Flutter)
- Android Studio or VS Code with Flutter extensions
- Android SDK (API 24 or higher)

### Setup Steps

1. **Clone your fork**:
   ```bash
   git clone https://github.com/yourusername/nav2_mission_planner.git
   cd nav2_mission_planner
   ```

2. **Add upstream remote**:
   ```bash
   git remote add upstream https://github.com/originalowner/nav2_mission_planner.git
   ```

3. **Install dependencies**:
   ```bash
   flutter pub get
   ```

4. **Run the app**:
   ```bash
   flutter run
   ```

## Code Style Guidelines

### Dart/Flutter Style

- Follow the [Effective Dart](https://dart.dev/guides/language/effective-dart) style guide
- Use `dart format` to format code
- Run `flutter analyze` before committing

### Naming Conventions

- **Files**: Use snake_case (e.g., `connection_screen.dart`)
- **Classes**: Use PascalCase (e.g., `ConnectionScreen`)
- **Variables/Functions**: Use camelCase (e.g., `connectToRobot`)
- **Constants**: Use lowerCamelCase (e.g., `defaultPort`)

### Code Organization

- Keep files focused and single-purpose
- Use meaningful variable and function names
- Add comments for complex logic
- Keep functions small and focused

### Widget Structure

- Extract reusable widgets into separate files
- Use `const` constructors where possible
- Prefer composition over inheritance

## Testing

- Write tests for new features when possible
- Test on physical devices when possible
- Test with different ROS2 configurations
- Verify backward compatibility

## Documentation

- Update README.md for user-facing changes
- Add code comments for complex logic
- Update inline documentation for public APIs
- Keep CHANGELOG.md updated

## Pull Request Process

1. Ensure your code follows style guidelines
2. Run `flutter analyze` and fix any issues
3. Test your changes thoroughly
4. Update documentation as needed
5. Ensure all CI checks pass
6. Request review from maintainers

## Review Process

- Maintainers will review your PR
- Address any feedback or requested changes
- Once approved, your PR will be merged

## Questions?

If you have questions, feel free to:
- Open a discussion on GitHub
- Ask in an issue
- Contact maintainers

Thank you for contributing to Nav2 Mission Planner!

