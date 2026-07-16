#!/usr/bin/env bash
# FluentyCoach build script
# Usage:
#   ./build.sh              — compile + sign FluentyCoach.app
#   ./build.sh install      — also copy to /Applications/FluentyCoach.app
#   ./build.sh cert         — create self-signed dev certificate (run once)
#   ./build.sh reset-perms  — clear stale Accessibility grant so it can be re-granted cleanly
set -euo pipefail

BUNDLE_ID="com.fluenty.coach"

# ── reset-perms: clear stale TCC entries ────────────────────────────────────────
# Old ad-hoc-signed builds can leave a dead Accessibility entry that the running
# (cert-signed) app no longer matches, which makes macOS re-prompt on every launch.
# Resetting lets you grant it once cleanly; the stable cert keeps it after that.
if [[ "${1:-}" == "reset-perms" ]]; then
    echo "==> Resetting Accessibility permission for $BUNDLE_ID"
    tccutil reset Accessibility "$BUNDLE_ID" || true
    tccutil reset AppleEvents "$BUNDLE_ID" || true
    echo "==> Done. Launch the app and grant Accessibility once when asked."
    exit 0
fi

CERT_NAME="FluentyDevCert"
SIGN_IDENTITY="${FLUENTY_SIGN_IDENTITY:-$CERT_NAME}"
APP_PATH="FluentyCoach.app"
BIN_PATH="$APP_PATH/Contents/MacOS/FluentyCoach"
ENTITLEMENTS="FluentyCoach/FluentyCoach.entitlements"

SOURCES=(
    FluentyCoach/Models/Language.swift
    FluentyCoach/Models/PermissionState.swift
    FluentyCoach/Models/TranslationState.swift
    FluentyCoach/Extensions/NSScreen+Cursor.swift
    FluentyCoach/Services/AccessibilityService.swift
    FluentyCoach/Services/HotkeyService.swift
    FluentyCoach/Services/SpeechService.swift
    FluentyCoach/Services/HistoryStore.swift
    FluentyCoach/Services/TranslationStyleStore.swift
    FluentyCoach/Services/AITranslationService.swift
    FluentyCoach/Services/TranslationService.swift
    FluentyCoach/UI/GlassActionButton.swift
    FluentyCoach/UI/LanguageToggleView.swift
    FluentyCoach/UI/ApiKeySetupView.swift
    FluentyCoach/UI/SettingsView.swift
    FluentyCoach/UI/TranslationResultView.swift
    FluentyCoach/UI/TranslationPopoverView.swift
    FluentyCoach/UI/HistoryView.swift
    FluentyCoach/UI/OnboardingView.swift
    FluentyCoach/UI/PopoverController.swift
    FluentyCoach/App/AppDelegate.swift
    FluentyCoach/App/FluentyCoachApp.swift
)

# ── cert: create a self-signed developer certificate ───────────────────────────
if [[ "${1:-}" == "cert" ]]; then
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$CERT_NAME\""; then
        echo "==> Certificate '$CERT_NAME' already exists."
        exit 0
    fi

    echo "==> Creating self-signed certificate '$CERT_NAME'"

    cat > /tmp/fluenty-cert.cfg << 'CERTEOF'
[req]
distinguished_name = req_dn
x509_extensions = v3_codesign
prompt = no
[req_dn]
CN = FluentyDevCert
[v3_codesign]
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
basicConstraints = critical, CA:FALSE
subjectKeyIdentifier = hash
CERTEOF

    openssl genrsa -out /tmp/fluenty.key 2048 2>/dev/null
    openssl req -new -x509 -key /tmp/fluenty.key -out /tmp/fluenty.crt \
        -days 3650 -config /tmp/fluenty-cert.cfg 2>/dev/null
    openssl pkcs12 -export -out /tmp/fluenty.p12 \
        -inkey /tmp/fluenty.key -in /tmp/fluenty.crt \
        -name "$CERT_NAME" -passout pass:fluenty 2>/dev/null
    security import /tmp/fluenty.p12 \
        -k ~/Library/Keychains/login.keychain-db \
        -P "fluenty" -A -T /usr/bin/codesign
    security add-trusted-cert -d -r trustRoot \
        -k ~/Library/Keychains/login.keychain-db \
        /tmp/fluenty.crt
    rm -f /tmp/fluenty.{key,crt,p12} /tmp/fluenty-cert.cfg

    echo "==> Certificate '$CERT_NAME' created and trusted."
    echo "    Run ./build.sh to compile."
    exit 0
fi

# ── check signing identity ──────────────────────────────────────────────────────
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$SIGN_IDENTITY\""; then
    echo "⚠️  Certificate '$SIGN_IDENTITY' not found."
    echo "   Run './build.sh cert' once to create it (keeps accessibility permissions across rebuilds)."
    echo "   Falling back to ad-hoc signing for now."
    SIGN_IDENTITY="-"
fi

# ── icons: regenerate if SVG is newer than .icns ────────────────────────────────
if [[ ! -f "FluentyCoach/Resources/AppIcon.icns" ]] || \
   [[ "FluentyCoach/Resources/AppIcon.svg" -nt "FluentyCoach/Resources/AppIcon.icns" ]]; then
    echo "==> Regenerating icons from SVG"
    swift make-icon.swift
fi

# ── compile ─────────────────────────────────────────────────────────────────────
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

echo "==> Compiling FluentyCoach"
swiftc "${SOURCES[@]}" \
    -o "$BIN_PATH" \
    -parse-as-library \
    -target arm64-apple-macosx26.0

# ── resources ───────────────────────────────────────────────────────────────────
echo "==> Copying resources"
cp -f FluentyCoach/Resources/AppIcon.icns "$APP_PATH/Contents/Resources/"
cp -f FluentyCoach/Resources/MenuBarIcon.pdf "$APP_PATH/Contents/Resources/"

# ── Info.plist: generated here so the bundle is reproducible ─────────────────────
# (Intentionally NO NSAppleEventsUsageDescription — Fluenty uses only Accessibility,
#  so macOS never shows a separate Automation permission modal.)
echo "==> Writing Info.plist"
cat > "$APP_PATH/Contents/Info.plist" << 'PLISTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FluentyCoach</string>
    <key>CFBundleIdentifier</key>
    <string>com.fluenty.coach</string>
    <key>CFBundleName</key>
    <string>FluentyCoach</string>
    <key>CFBundleDisplayName</key>
    <string>Fluenty Coach</string>
    <key>CFBundleVersion</key>
    <string>1.1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>Fluenty Coach needs accessibility access to replace selected text in other apps.</string>
</dict>
</plist>
PLISTEOF

# ── sign ────────────────────────────────────────────────────────────────────────
echo "==> Signing with '$SIGN_IDENTITY'"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - "$APP_PATH"
else
    codesign --force --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_PATH"
fi

# ── install ─────────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "install" ]]; then
    echo "==> Installing to /Applications/FluentyCoach.app"
    rsync -a --delete "$APP_PATH/" "/Applications/FluentyCoach.app/"
    if [[ "$SIGN_IDENTITY" == "-" ]]; then
        codesign --force --sign - "/Applications/FluentyCoach.app"
    else
        codesign --force --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" "/Applications/FluentyCoach.app"
    fi
    echo "==> Run: open /Applications/FluentyCoach.app"
fi

echo "==> Done."
