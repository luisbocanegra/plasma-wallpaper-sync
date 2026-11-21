#!/bin/sh
if [ -d "build" ]; then
    rm -rf build
fi

cmake -B build -S . -DCMAKE_INSTALL_PREFIX=/usr
cmake --build build
sudo cmake --install build

# remove KDE Store / kpackagetool6 install so it doesn't override the system-wide one
echo "Removing previous install (if exists) from $HOME/.local/share/plasma/plasmoids/"
rm -r "$HOME/.local/share/plasma/plasmoids/luisbocanegra.wallpaper.sync/" 2>/dev/null || true
echo "Done"
