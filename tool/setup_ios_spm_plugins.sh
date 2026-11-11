#!/usr/bin/env bash
# Sets up Swift Package Manager (SPM) Package.swift manifests for plugins
# that only ship CocoaPods podspecs by default, enabling xcross Linux cross-compilation
# without affecting Android, Linux, macOS, or Windows builds.

set -e

PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Setting up SPM support for iOS plugins..."

# 1. image_gallery_saver (project-local plugin)
IGS_DIR="$PROJECT_ROOT/lib/plugins/image_gallery_saver-2.0.3"
if [ -d "$IGS_DIR" ]; then
  mkdir -p "$IGS_DIR/ios/image_gallery_saver/Sources/image_gallery_saver"
  cp -f "$IGS_DIR/ios/Classes/SwiftImageGallerySaverPlugin.swift" "$IGS_DIR/ios/image_gallery_saver/Sources/image_gallery_saver/"
  echo "public typealias ImageGallerySaverPlugin = SwiftImageGallerySaverPlugin" >> "$IGS_DIR/ios/image_gallery_saver/Sources/image_gallery_saver/SwiftImageGallerySaverPlugin.swift"
  cat << 'EOF' > "$IGS_DIR/ios/image_gallery_saver/Package.swift"
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "image_gallery_saver",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "image-gallery-saver", targets: ["image_gallery_saver"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "image_gallery_saver",
            dependencies: [],
            path: "Sources/image_gallery_saver"
        )
    ]
)
EOF
  echo "[✓] image_gallery_saver configured for SPM"
fi

# 2. wifi_scan
WIFI_SCAN_DIR=$(find "$PUB_CACHE/hosted/pub.dev" -maxdepth 1 -name "wifi_scan-*" | sort -V | tail -n 1)
if [ -n "$WIFI_SCAN_DIR" ] && [ -d "$WIFI_SCAN_DIR" ]; then
  mkdir -p "$WIFI_SCAN_DIR/ios/wifi_scan/Sources/wifi_scan"
  cp -f "$WIFI_SCAN_DIR/ios/Classes/SwiftWifiScanPlugin.swift" "$WIFI_SCAN_DIR/ios/wifi_scan/Sources/wifi_scan/"
  echo "public typealias WifiScanPlugin = SwiftWifiScanPlugin" >> "$WIFI_SCAN_DIR/ios/wifi_scan/Sources/wifi_scan/SwiftWifiScanPlugin.swift"
  cat << 'EOF' > "$WIFI_SCAN_DIR/ios/wifi_scan/Package.swift"
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "wifi_scan",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "wifi-scan", targets: ["wifi_scan"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "wifi_scan",
            dependencies: [],
            path: "Sources/wifi_scan"
        )
    ]
)
EOF
  echo "[✓] wifi_scan configured for SPM"
fi

# 3. wifi_iot
WIFI_IOT_DIR=$(find "$PUB_CACHE/hosted/pub.dev" -maxdepth 1 -name "wifi_iot-*" | sort -V | tail -n 1)
if [ -n "$WIFI_IOT_DIR" ] && [ -d "$WIFI_IOT_DIR" ]; then
  mkdir -p "$WIFI_IOT_DIR/ios/wifi_iot/Sources/wifi_iot"
  cp -f "$WIFI_IOT_DIR/ios/Classes/SwiftWifiIotPlugin.swift" "$WIFI_IOT_DIR/ios/wifi_iot/Sources/wifi_iot/"
  echo "public typealias WifiIotPlugin = SwiftWifiIotPlugin" >> "$WIFI_IOT_DIR/ios/wifi_iot/Sources/wifi_iot/SwiftWifiIotPlugin.swift"
  cat << 'EOF' > "$WIFI_IOT_DIR/ios/wifi_iot/Package.swift"
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "wifi_iot",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "wifi-iot", targets: ["wifi_iot"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "wifi_iot",
            dependencies: [],
            path: "Sources/wifi_iot"
        )
    ]
)
EOF
  echo "[✓] wifi_iot configured for SPM"
fi

# 4. flutter_timezone
TZ_DIR=$(find "$PUB_CACHE/hosted/pub.dev" -maxdepth 1 -name "flutter_timezone-*" | sort -V | tail -n 1)
if [ -n "$TZ_DIR" ] && [ -d "$TZ_DIR" ]; then
  mkdir -p "$TZ_DIR/ios/flutter_timezone/Sources/flutter_timezone"
  cat << 'EOF' > "$TZ_DIR/ios/flutter_timezone/Sources/flutter_timezone/FlutterTimezonePlugin.swift"
import Flutter
import UIKit

public class FlutterTimezonePlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_timezone", binaryMessenger: registrar.messenger())
        let instance = FlutterTimezonePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "getLocalTimezone" {
            result(TimeZone.current.identifier)
        } else if call.method == "getAvailableTimezones" {
            result(TimeZone.knownTimeZoneIdentifiers)
        } else {
            result(FlutterMethodNotImplemented)
        }
    }
}
EOF
  cat << 'EOF' > "$TZ_DIR/ios/flutter_timezone/Package.swift"
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "flutter_timezone",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "flutter-timezone", targets: ["flutter_timezone"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "flutter_timezone",
            dependencies: [],
            path: "Sources/flutter_timezone"
        )
    ]
)
EOF
  echo "[✓] flutter_timezone configured for SPM"
fi

# 5. flutter_secure_storage
FSS_DIR=$(find "$PUB_CACHE/hosted/pub.dev" -maxdepth 1 -name "flutter_secure_storage-*" | sort -V | tail -n 1)
if [ -n "$FSS_DIR" ] && [ -d "$FSS_DIR" ]; then
  mkdir -p "$FSS_DIR/ios/flutter_secure_storage/Sources/flutter_secure_storage"
  cp -f "$FSS_DIR/ios/Classes/FlutterSecureStorage.swift" "$FSS_DIR/ios/flutter_secure_storage/Sources/flutter_secure_storage/"
  cp -f "$FSS_DIR/ios/Classes/SwiftFlutterSecureStoragePlugin.swift" "$FSS_DIR/ios/flutter_secure_storage/Sources/flutter_secure_storage/"
  echo "public typealias FlutterSecureStoragePlugin = SwiftFlutterSecureStoragePlugin" >> "$FSS_DIR/ios/flutter_secure_storage/Sources/flutter_secure_storage/SwiftFlutterSecureStoragePlugin.swift"
  cat << 'EOF' > "$FSS_DIR/ios/flutter_secure_storage/Package.swift"
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "flutter_secure_storage",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "flutter-secure-storage", targets: ["flutter_secure_storage"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "flutter_secure_storage",
            dependencies: [],
            path: "Sources/flutter_secure_storage"
        )
    ]
)
EOF
  echo "[✓] flutter_secure_storage configured for SPM"
fi

echo "All 5 plugins configured successfully."
