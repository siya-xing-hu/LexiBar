#!/bin/bash
set -e

CONFIGURATION="Debug"
SCHEME="LexiBar"
PROJECT="LexiBar.xcodeproj"
DERIVED_DATA=".derivedata"
OUTPUT_DIR="build"
APP_NAME="LexiBar.app"

# 每次都用 XcodeGen 重新生成 .xcodeproj，确保新增文件被包含
echo "Generating Xcode project..."
xcodegen generate

# 清理旧的 Derived Data，避免路径混乱
rm -rf "$DERIVED_DATA"

# 编译
echo "Building $APP_NAME..."
LOG_FILE="$DERIVED_DATA/build.log"
mkdir -p "$DERIVED_DATA"

if ! xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    build > "$LOG_FILE" 2>&1; then
    echo "Build failed. Last 30 lines of log:"
    tail -n 30 "$LOG_FILE"
    exit 1
fi

# 复制 .app 到项目目录下的 build/ 文件夹
BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME"
mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR/$APP_NAME"
cp -R "$BUILT_APP" "$OUTPUT_DIR/"

echo ""
echo "Build succeeded: $OUTPUT_DIR/$APP_NAME"
echo "You can now run: open \"$OUTPUT_DIR/$APP_NAME\""
