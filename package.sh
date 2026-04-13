#!/usr/bin/env bash
# 打包 AropytEditor
# 用法：./package.sh [dmg|pkg]   默认 dmg
set -euo pipefail

MODE="${1:-dmg}"
if [[ "$MODE" != "dmg" && "$MODE" != "pkg" ]]; then
    echo "用法：$0 [dmg|pkg]" >&2
    exit 1
fi

APP_NAME="AropytEditor"
DISPLAY_NAME="Aropyt"
VERSION="0.1.0"
BUNDLE_ID="com.aropyt.AropytEditor"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build/release"
DIST_DIR="$SCRIPT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

# ── 第 1 步：编译 ────────────────────────────────────────────────────────────
echo "==> [1/4] swift build -c release"
cd "$SCRIPT_DIR"
swift build -c release

# ── 第 2 步：组装 .app bundle ─────────────────────────────────────────────────
echo "==> [2/4] 组装 $APP_NAME.app"
rm -rf "$DIST_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 主二进制
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# SPM 资源包（JS / CSS）—— 代码通过 Bundle.module 定位
cp -R "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" \
      "$APP_BUNDLE/Contents/Resources/"

# Info.plist —— bundle 模式由系统从 Contents/ 读；裸跑时靠 Mach-O __info_plist 段
cp "$SCRIPT_DIR/Sources/$APP_NAME/Resources/Info.plist" \
   "$APP_BUNDLE/Contents/Info.plist"

# ── 第 3 步：Ad-hoc 签名 ─────────────────────────────────────────────────────
# 无 Apple 开发者账号时用 "-"；分发给他人需换成真实证书并 notarize
echo "==> [3/4] ad-hoc 签名"
codesign --deep --force --sign - "$APP_BUNDLE"

# ── 第 4 步：打包 ─────────────────────────────────────────────────────────────
if [[ "$MODE" == "dmg" ]]; then
    OUTPUT="$DIST_DIR/$DISPLAY_NAME-$VERSION.dmg"
    echo "==> [4/4] 打 DMG → $OUTPUT"

    # create-dmg 直接把包含 .app 的目录做成 DMG
    # --app-drop-link 会自动在指定坐标放 /Applications 快捷方式，无需手动 ln -s
    DMG_SRC="$DIST_DIR/_dmg_staging"
    mkdir -p "$DMG_SRC"
    cp -R "$APP_BUNDLE" "$DMG_SRC/"

    create-dmg \
        --volname "$DISPLAY_NAME $VERSION" \
        --window-size 560 340 \
        --icon-size 100 \
        --icon "$APP_NAME.app" 140 170 \
        --hide-extension "$APP_NAME.app" \
        --app-drop-link 420 170 \
        "$OUTPUT" \
        "$DMG_SRC"

    rm -rf "$DMG_SRC"

elif [[ "$MODE" == "pkg" ]]; then
    OUTPUT="$DIST_DIR/$DISPLAY_NAME-$VERSION.pkg"
    echo "==> [4/4] 打 PKG → $OUTPUT"

    # pkgbuild 把 --root 下的内容安装到 --install-location
    # 结果：用户双击 pkg 后 .app 被装入 /Applications/
    PKG_ROOT="$DIST_DIR/_pkg_root"
    mkdir -p "$PKG_ROOT"
    cp -R "$APP_BUNDLE" "$PKG_ROOT/"

    pkgbuild \
        --root "$PKG_ROOT" \
        --install-location /Applications \
        --identifier "$BUNDLE_ID" \
        --version "$VERSION" \
        "$OUTPUT"

    rm -rf "$PKG_ROOT"
fi

echo ""
echo "Done! 产物：$OUTPUT"
