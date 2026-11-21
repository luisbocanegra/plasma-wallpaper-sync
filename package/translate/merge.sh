#!/bin/sh
# Extracts translatable messages from the plasmoid sources into template.pot
# and merges any changes into the existing *.po files.
# Adapted for KF6 (metadata.json) from the KDE plasmoid i18n workflow.
# https://develop.kde.org/docs/plasma/widget/translations-i18n/
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
packageRoot="${DIR}/.."
metadataFile="${packageRoot}/metadata.json"

# Read plugin id / website from metadata.json (KF6). Prefer python3, fall back to jq.
read_json_field() {
    # $1 = field name inside the "KPlugin" object, e.g. "Id" or "Website"
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import json,sys; print(json.load(open('${metadataFile}'))['KPlugin'].get('${1}',''))"
    elif command -v jq >/dev/null 2>&1; then
        jq -r ".KPlugin.${1} // \"\"" "${metadataFile}"
    else
        grep -o "\"${1}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "${metadataFile}" | head -1 | sed -E 's/.*"[^"]*"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/'
    fi
}

plasmoidName="$(read_json_field Id)"
website="$(read_json_field Website)"
bugAddress="${website}"
widgetName="${plasmoidName##*.}" # Strip namespace, e.g. "sync"
projectName="plasma_applet_${plasmoidName}"

if [ -z "${plasmoidName}" ]; then
    echo "[merge] Error: Could not read plugin Id from ${metadataFile}" >&2
    exit 1
fi
if [ -z "$(command -v xgettext)" ]; then
    echo "[merge] Error: xgettext not found. Install gettext." >&2
    exit 1
fi

echo "[merge] Extracting messages (domain: ${projectName})"
# Run from the translate dir so source references stay relative (../contents/...)
cd "${DIR}"
find .. \( -name '*.cpp' -o -name '*.h' -o -name '*.c' -o -name '*.qml' -o -name '*.js' \) | sort > "infiles.list"
xgettext \
    --files-from="infiles.list" \
    --from-code=UTF-8 --width=200 --add-location=file \
    -C -kde -ci18n \
    -ki18n:1 -ki18nc:1c,2 -ki18np:1,2 -ki18ncp:1c,2,3 \
    -kki18n:1 -kki18nc:1c,2 -kki18np:1,2 -kki18ncp:1c,2,3 \
    -kxi18n:1 -kxi18nc:1c,2 -kxi18np:1,2 -kxi18ncp:1c,2,3 \
    -kkxi18n:1 -kkxi18nc:1c,2 -kkxi18np:1,2 -kkxi18ncp:1c,2,3 \
    -kI18N_NOOP:1 -kI18NC_NOOP:1c,2 -kI18N_NOOP2:1c,2 -kI18N_NOOP2_NOSTRIP:1c,2 \
    -ktr2i18n:1 -ktr2xi18n:1 -kN_:1 -kaliasLocale \
    --package-name="${widgetName}" \
    --msgid-bugs-address="${bugAddress}" \
    -D .. -D . \
    -o "template.pot.new" \
    || { echo "[merge] error while calling xgettext. aborting." >&2; exit 1; }
sed -i 's/"Content-Type: text\/plain; charset=CHARSET\\n"/"Content-Type: text\/plain; charset=UTF-8\\n"/' "template.pot.new"
sed -i 's/# SOME DESCRIPTIVE TITLE./'"# Translation of ${widgetName} in LANGUAGE"'/' "template.pot.new"
sed -i 's/# Copyright (C) YEAR THE PACKAGE'"'"'S COPYRIGHT HOLDER/'"# Copyright (C) $(date +%Y)"'/' "template.pot.new"

if [ -f "template.pot" ]; then
    newPotDate=$(grep "POT-Creation-Date:" "template.pot.new" | sed 's/.\{3\}$//')
    oldPotDate=$(grep "POT-Creation-Date:" "template.pot" | sed 's/.\{3\}$//')
    sed -i 's/'"${newPotDate}"'/'"${oldPotDate}"'/' "template.pot.new"
    changes=$(diff "template.pot" "template.pot.new" || true)
    if [ -n "${changes}" ]; then
        sed -i 's/'"${oldPotDate}"'/'"${newPotDate}"'/' "template.pot.new"
        mv "template.pot.new" "template.pot"
        echo "[merge] Template updated."
    else
        rm "template.pot.new"
        echo "[merge] No changes to template."
    fi
else
    mv "template.pot.new" "template.pot"
fi
rm -f "infiles.list"

echo "[merge] Merging messages"
for cat in $(find "${DIR}" -maxdepth 1 -name '*.po' | sort); do
    catLocale=$(basename "${cat}" .po)
    echo "[merge] Updating ${catLocale}.po"
    cp "${cat}" "${cat}.new"
    sed -i 's/"Content-Type: text\/plain; charset=CHARSET\\n"/"Content-Type: text\/plain; charset=UTF-8\\n"/' "${cat}.new"
    msgmerge --width=400 --add-location=file --no-fuzzy-matching -o "${cat}.new" "${cat}.new" "${DIR}/template.pot"
    sed -i 's/# SOME DESCRIPTIVE TITLE./'"# Translation of ${widgetName} in ${catLocale}"'/' "${cat}.new"
    sed -i 's/# Translation of '"${widgetName}"' in LANGUAGE/'"# Translation of ${widgetName} in ${catLocale}"'/' "${cat}.new"
    sed -i 's/# Copyright (C) YEAR THE PACKAGE'"'"'S COPYRIGHT HOLDER/'"# Copyright (C) $(date +%Y)"'/' "${cat}.new"
    mv "${cat}.new" "${cat}"
done
echo "[merge] Done. Run build.sh to compile .po -> .mo."
