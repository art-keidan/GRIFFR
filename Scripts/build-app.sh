#!/bin/zsh
# Compila l'app e la confeziona come GRIFFR.app in build/ (l'eseguibile interno resta WordProcessor).
# Uso: Scripts/build-app.sh [--open]
set -e
root=${0:a:h:h}
cd $root
swift build -c release --product WordProcessor
app=$root/build/GRIFFR.app
rm -rf $app
mkdir -p $app/Contents/MacOS
cp .build/release/WordProcessor $app/Contents/MacOS/WordProcessor
# I modelli di sillabazione di TeX, che il programma cerca tra le proprie risorse.
mkdir -p $app/Contents/Resources
cp -R Sources/Typesetting/Resources/Hyphenation $app/Contents/Resources/Hyphenation
# Le icone dell'app e dei documenti (si rifanno con Scripts/make-icon.swift).
cp Resources/GRIFFR.icns $app/Contents/Resources/GRIFFR.icns
cp Resources/GRIFFR-documento.icns $app/Contents/Resources/GRIFFR-documento.icns
cat > $app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>GRIFFR</string>
    <key>CFBundleDisplayName</key><string>GRIFFR</string>
    <key>CFBundleIdentifier</key><string>local.wordprocessor.prototype</string>
    <key>CFBundleExecutable</key><string>WordProcessor</string>
    <key>CFBundleIconFile</key><string>GRIFFR</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleDevelopmentRegion</key><string>it</string>
    <key>CFBundleLocalizations</key><array><string>it</string></array>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Documento GRIFFR</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Owner</string>
            <key>CFBundleTypeIconFile</key><string>GRIFFR-documento</string>
            <key>LSItemContentTypes</key><array><string>local.wordprocessor.document</string></array>
            <key>NSDocumentClass</key><string>TextDocument</string>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key><string>local.wordprocessor.document</string>
            <key>UTTypeDescription</key><string>Documento GRIFFR</string>
            <key>UTTypeIconFile</key><string>GRIFFR-documento</string>
            <key>UTTypeConformsTo</key><array><string>public.xml</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>grx</string><string>wpx</string></array></dict>
        </dict>
    </array>
</dict>
</plist>
PLIST
echo "Creata $app"
if [[ ${1:-} == --open ]]; then
    open "$app"
fi
