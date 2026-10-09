#!/bin/bash
# build-installer.sh - 构建 iNas Windows 自解压安装器
# 用法: ./build-installer.sh [版本号]

set -e

VERSION=${1:-"1.0.0"}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WINDOWS_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$WINDOWS_DIR")"

echo "=== iNas Installer Builder ==="
echo "Version: $VERSION"
echo "Project: $PROJECT_DIR"

# 1. 构建 Electron
echo ""
echo "[1/4] Building Electron app..."
cd "$WINDOWS_DIR"
npm install
npx electron-builder --dir --win

ELECTRON_OUT="$WINDOWS_DIR/dist/win-unpacked"
if [ ! -d "$ELECTRON_OUT" ]; then
    echo "Error: Electron build output not found at $ELECTRON_OUT"
    exit 1
fi
echo "Electron build done: $ELECTRON_OUT"

# 2. 准备 System 目录结构
echo ""
echo "[2/4] Preparing package structure..."
PACKAGE_DIR="$WINDOWS_DIR/dist/package"
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR/System"

# 复制 Electron 输出到 System 目录
cp -r "$ELECTRON_OUT/"* "$PACKAGE_DIR/System/"

# 重命名主程序为 iNas.exe（如果 electron-builder 输出的是其他名字）
if [ -f "$PACKAGE_DIR/System/iNas.exe" ]; then
    echo "Main exe already named iNas.exe"
elif [ -f "$PACKAGE_DIR/System/electron.exe" ]; then
    mv "$PACKAGE_DIR/System/electron.exe" "$PACKAGE_DIR/System/iNas.exe"
fi

# 创建默认文件夹（这些会在安装时由 stub 创建，这里也放一个占位）
mkdir -p "$PACKAGE_DIR/回收站"
mkdir -p "$PACKAGE_DIR/音乐"
mkdir -p "$PACKAGE_DIR/视频"
mkdir -p "$PACKAGE_DIR/图片"
mkdir -p "$PACKAGE_DIR/下载"

echo "Package structure ready: $PACKAGE_DIR"

# 3. 打包为 zip
echo ""
echo "[3/4] Creating zip archive..."
ZIP_PATH="$WINDOWS_DIR/dist/iNas-package.zip"
rm -f "$ZIP_PATH"
cd "$PACKAGE_DIR"
zip -r -q "$ZIP_PATH" .
echo "Zip created: $ZIP_PATH ($(du -h "$ZIP_PATH" | cut -f1))"

# 4. 编译 Go stub 并拼接
echo ""
echo "[4/4] Building Go stub and concatenating..."
STUB_DIR="$WINDOWS_DIR/stub"
STUB_EXE="$WINDOWS_DIR/dist/stub.exe"

cd "$STUB_DIR"
GOOS=windows GOARCH=amd64 go build -ldflags="-s -w -H windowsgui" -o "$STUB_EXE" .

if [ ! -f "$STUB_EXE" ]; then
    echo "Error: Go stub build failed"
    exit 1
fi
echo "Stub built: $STUB_EXE ($(du -h "$STUB_EXE" | cut -f1))"

# 拼接 stub + zip = 最终安装器
FINAL_EXE="$WINDOWS_DIR/dist/iNas-Setup-${VERSION}.exe"
cat "$STUB_EXE" "$ZIP_PATH" > "$FINAL_EXE"

echo ""
echo "=== Build Complete ==="
echo "Output: $FINAL_EXE"
echo "Size: $(du -h "$FINAL_EXE" | cut -f1)"
echo ""
echo "Done!"
