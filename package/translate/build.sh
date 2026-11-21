#!/bin/sh
# Compiles the *.po files into binary *.mo catalogs and installs them into
# the bundled package so translations ship with the plasmoid:
#   package/contents/locale/<lang>/LC_MESSAGES/plasma_applet_<pluginId>.mo
# Adapted for KF6 (metadata.json).
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
packageRoot="${DIR}/.."
metadataFile="${packageRoot}/metadata.json"

read_json_field() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import json,sys; print(json.load(open('${metadataFile}'))['KPlugin'].get('${1}',''))"
    elif command -v jq >/dev/null 2>&1; then
        jq -r ".KPlugin.${1} // \"\"" "${metadataFile}"
    else
        grep -o "\"${1}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "${metadataFile}" | head -1 | sed -E 's/.*"[^"]*"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/'
    fi
}

plasmoidName="$(read_json_field Id)"
projectName="plasma_applet_${plasmoidName}"

if [ -z "${plasmoidName}" ]; then
    echo "[build] Error: Could not read plugin Id from ${metadataFile}" >&2
    exit 1
fi
if [ -z "$(command -v msgfmt)" ]; then
    echo "[build] Error: msgfmt not found. Install gettext." >&2
    exit 1
fi

echo "[build] Compiling messages (domain: ${projectName})"
for cat in $(find "${DIR}" -maxdepth 1 -name '*.po' | sort); do
    catLocale=$(basename "${cat}" .po)
    installPath="${packageRoot}/contents/locale/${catLocale}/LC_MESSAGES/${projectName}.mo"
    echo "[build] ${catLocale}.po => contents/locale/${catLocale}/LC_MESSAGES/${projectName}.mo"
    msgfmt --check -o "${catLocale}.mo" "${cat}"
    mkdir -p "$(dirname "${installPath}")"
    mv "${catLocale}.mo" "${installPath}"
done
echo "[build] Done. (Re)install the plasmoid and restart plasmashell to test."
