#!/bin/zsh
# Compila l'app e la confeziona come GRIFFR Stili.app in build/.
# Uso: Scripts/build-app.sh [--open]
set -e
root=${0:a:h:h}
cd $root
build_path=${GRIFFR_BUILD_PATH:-"$root/.build"}
app_build_dir=${GRIFFR_APP_BUILD_DIR:-"$root/build"}
build_flags=()
if [[ ${GRIFFR_DISABLE_BUILD_SANDBOX:-0} == 1 ]]; then build_flags+=(--disable-sandbox); fi
swift build "${build_flags[@]}" --scratch-path "$build_path" -c release --product WordProcessor
mkdir -p "$app_build_dir"
destination="$app_build_dir/GRIFFR Stili.app"
staging=$(mktemp -d "$app_build_dir/.griffr-stage.XXXXXX")
app="$staging/GRIFFR Stili.app"
mkdir -p $app/Contents/MacOS
cp "$build_path/release/WordProcessor" $app/Contents/MacOS/WordProcessor
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
    <key>CFBundleName</key><string>GRIFFR Stili</string>
    <key>CFBundleDisplayName</key><string>GRIFFR Stili</string>
    <key>CFBundleIdentifier</key><string>local.wordprocessor.stili</string>
    <key>CFBundleExecutable</key><string>WordProcessor</string>
    <key>CFBundleIconFile</key><string>GRIFFR</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string></array>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Documento GRIFFR</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Alternate</string>
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
# Un eseguibile aperto su SMB può trattenere un file .smbdelete.
# Si conserva la precedente compilazione senza l'estensione .app: resta
# recuperabile, ma non è un'altra applicazione da aprire o associare ai file.
previous=""
if [[ -e "$destination" ]]; then
    previous=$(mktemp -d "$app_build_dir/.griffr-previous.XXXXXX")
    mv "$destination" "$previous/GRIFFR Stili.retired"
fi
if ! mv "$app" "$destination"; then
    if [[ -n "$previous" ]]; then
        mv "$previous/GRIFFR Stili.retired" "$destination"
    fi
    exit 1
fi
rmdir "$staging" 2>/dev/null || true
# Anche le copie lasciate dalle versioni precedenti dello script cessano di
# essere applicazioni apribili; non si elimina nessuna vecchia compilazione.
for legacy in "$app_build_dir"/.griffr-{previous,stage}.*/"GRIFFR Stili.app"(N); do
    mv "$legacy" "${legacy%.app}.retired"
done
app="$destination"
echo "Creata $app"
if [[ ${1:-} == --open ]]; then
    open "$app"
fi
