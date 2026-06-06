#!/bin/bash
# Sparkle auto-update: EdDSA-sign a built PICkle DMG and emit a ready-to-paste
# appcast <item> (plus a full appcast.xml) under dist/.
#
# Mirrors pizzaClip/scripts/release.sh's Sparkle block. The private EdDSA key
# lives in the login Keychain (reused from pizzaClip — same key pair, no new
# key generation needed). Sparkle's `sign_update` reads it automatically.
#
# Usage:
#   ./scripts/sparkle-appcast.sh [path-to-dmg]
#
# If no DMG path is given, defaults to the newest PICkle-*.dmg in ~/Downloads
# (that's where scripts/release-test-dmg.sh writes its output).
#
# Prereq: Sparkle must have been resolved into build/SourcePackages so that the
# `sign_update` binary exists. The main build command already does this:
#   xcodebuild ... -clonedSourcePackagesDirPath build/SourcePackages build
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# ── Locate the DMG to sign ───────────────────────────────────────────────────
DMG="${1:-}"
if [ -z "$DMG" ]; then
    DMG="$(ls -t "$HOME"/Downloads/PICkle-*.dmg 2>/dev/null | head -1 || true)"
fi
if [ -z "$DMG" ] || [ ! -f "$DMG" ]; then
    echo "✗ No DMG found. Pass one explicitly: ./scripts/sparkle-appcast.sh <dmg>" >&2
    exit 1
fi
echo "→ DMG: $DMG"

# ── Find Sparkle's sign_update binary (path varies by build dir) ─────────────
# After an xcodebuild that resolves packages into build/SourcePackages, the
# Sparkle artifacts (incl. sign_update / generate_appcast) land under:
#   build/SourcePackages/artifacts/sparkle/Sparkle/bin/
# We search dynamically so a different derivedData/clonedSourcePackages path
# still works.
SIGN_UPDATE="$(find build -type f -name sign_update -path '*sparkle*/bin/*' 2>/dev/null | head -1 || true)"
if [ -z "$SIGN_UPDATE" ]; then
    # Fallback: search anywhere under build/.
    SIGN_UPDATE="$(find build -type f -name sign_update 2>/dev/null | head -1 || true)"
fi
if [ -z "$SIGN_UPDATE" ] || [ ! -x "$SIGN_UPDATE" ]; then
    echo "✗ sign_update not found under build/." >&2
    echo "  Resolve Sparkle first, e.g.:" >&2
    echo "    xcodebuild -project PicKle.xcodeproj -scheme PicKle \\" >&2
    echo "      -resolvePackageDependencies -derivedDataPath build \\" >&2
    echo "      -clonedSourcePackagesDirPath build/SourcePackages" >&2
    exit 1
fi
echo "→ sign_update: $SIGN_UPDATE"

# ── Version metadata from project.yml ────────────────────────────────────────
VERSION="$(grep 'MARKETING_VERSION:' project.yml | head -1 | sed 's/.*"\([^"]*\)".*/\1/')"
BUILD_NUMBER="$(grep 'CURRENT_PROJECT_VERSION:' project.yml | head -1 | sed 's/.*"\([^"]*\)".*/\1/')"
[ -n "$VERSION" ] || { echo "✗ Could not read MARKETING_VERSION from project.yml" >&2; exit 1; }
echo "→ Version $VERSION (build $BUILD_NUMBER)"

mkdir -p dist

# ── EdDSA-sign the DMG ───────────────────────────────────────────────────────
echo "→ Signing DMG for Sparkle (EdDSA)"
SIG_LINE="$("$SIGN_UPDATE" "$DMG")"
echo "    $SIG_LINE"

# ── Release notes → HTML for the Sparkle "what's new" panel ──────────────────
# One source of truth: dist/notes-<version>.md (Markdown). Falls back to a
# one-liner so a forgotten notes file never breaks signing.
md_to_html() {
    awk '
        function esc(s) { gsub(/&/,"\\&amp;",s); gsub(/</,"\\&lt;",s); gsub(/>/,"\\&gt;",s); return s }
        function closelist() { if (inlist) { print "</ul>"; inlist=0 } }
        BEGIN { inlist=0 }
        { line=$0; sub(/\r$/,"",line) }
        line ~ /^[[:space:]]*$/ { closelist(); next }
        line ~ /^## /  { closelist(); sub(/^## /,"",line); print "<h3>" esc(line) "</h3>"; next }
        line ~ /^# /   { closelist(); sub(/^# /,"",line);  print "<h2>" esc(line) "</h2>"; next }
        line ~ /^[-*] / { if (!inlist){print "<ul>"; inlist=1} sub(/^[-*] /,"",line); print "<li>" esc(line) "</li>"; next }
        { closelist(); print "<p>" esc(line) "</p>" }
        END { closelist() }
    ' "$1"
}
NOTES="dist/notes-${VERSION}.md"
[ -f "$NOTES" ] || printf '# PICkle %s\n\n- 버그 수정 및 개선\n' "$VERSION" > "$NOTES"
NOTES_HTML="$(md_to_html "$NOTES")"

# ── Download URL ─────────────────────────────────────────────────────────────
# ⚠️ PLACEHOLDER — point <enclosure url> at the REAL DMG download URL.
# Recommended: a GitHub Release asset, e.g.
#   https://github.com/<owner>/<repo>/releases/download/v<version>/PICkle-<version>.dmg
# Override via env: DOWNLOAD_BASE_URL=... ./scripts/sparkle-appcast.sh
DMG_NAME="$(basename "$DMG")"
DOWNLOAD_BASE_URL="${DOWNLOAD_BASE_URL:-https://REPLACE-WITH-REAL-DMG-HOST/PICkle/v${VERSION}}"

PUBDATE="$(LC_TIME=en_US.UTF-8 date -u "+%a, %d %b %Y %H:%M:%S +0000")"
APPCAST_ITEM="dist/appcast-item-${VERSION}.xml"
cat > "$APPCAST_ITEM" <<EOF
        <item>
            <title>PICkle ${VERSION}</title>
            <pubDate>${PUBDATE}</pubDate>
            <sparkle:version>${BUILD_NUMBER}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <description><![CDATA[
${NOTES_HTML}
]]></description>
            <!-- ⚠️ Put the REAL DMG download URL here (GitHub Release asset, etc.). -->
            <enclosure url="${DOWNLOAD_BASE_URL}/${DMG_NAME}"
                       type="application/octet-stream"
                       ${SIG_LINE} />
        </item>
EOF
echo "    appcast <item> → $APPCAST_ITEM"

# ── Full appcast.xml (drop-in for the website) ───────────────────────────────
# This is what SUFeedURL (https://pizza-clip.com/pickle/appcast.xml) must serve.
APPCAST="dist/appcast.xml"
cat > "$APPCAST" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>PICkle</title>
        <link>https://pizza-clip.com/pickle/appcast.xml</link>
        <description>PICkle updates</description>
        <language>en</language>
$(cat "$APPCAST_ITEM")
    </channel>
</rss>
EOF
echo "    full appcast → $APPCAST"

echo ""
echo "✓ Sparkle signing done for PICkle $VERSION"
echo "  Next steps (manual):"
echo "    1. Upload the DMG to its host and set the real <enclosure url> in $APPCAST"
echo "    2. Publish $APPCAST at https://pizza-clip.com/pickle/appcast.xml"
