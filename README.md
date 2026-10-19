# Plasma Wallpaper Sync

KDE Plasma Widget that synchronizes the current Desktop wallpaper to other Monitors, Lock Screen and Login Screen (Plasma Login Manager).

Quick and dirty way to automatically sync wallpapers all across Plasma until a proper upstream implementation becomes available.

---

Consider sponsoring or donating to support the continued maintenance of this and [my other projects](https://github.com/luisbocanegra?tab=repositories&q=&type=source&language=&sort=stargazers) ❤️

[![GitHub Sponsors](https://img.shields.io/badge/GitHub%20Sponsors-%2329313C?logo=githubsponsors&style=for-the-badge)](https://github.com/sponsors/luisbocanegra)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-supporter?logo=ko-fi&logoColor=%23ffffff&color=%23467BEB&style=for-the-badge)](https://ko-fi.com/luisbocanegra)
[!["Buy Me A Coffee"](https://img.shields.io/badge/Buy%20me%20a%20coffee-supporter?logo=buymeacoffee&logoColor=%23282828&color=%23FF803F&style=for-the-badge)](https://www.buymeacoffee.com/luisbocanegra)
[![PayPal](https://img.shields.io/badge/PayPal-supporter?logo=paypal&logoColor=%23ffffff&color=%23003087&style=for-the-badge)](https://www.paypal.com/donate/?hosted_button_id=68SF5ZPAZ46UN)
[![Patreon](https://img.shields.io/badge/Patreon-%23000000?logo=patreon&logoColor=%23ffffff&style=for-the-badge)](https://patreon.com/luisbocanegra?utm_medium=unknown&utm_source=join_link&utm_campaign=creatorshare_creator&utm_content=copyLink)

---

## Installation

### From Source

1. Install these dependencies or the equivalents for your distribution

    ```sh
    # Arch Linux
    sudo pacman -S git gcc cmake extra-cmake-modules libplasma
    # Fedora
    sudo dnf install git gcc-c++ cmake extra-cmake-modules libplasma-devel
    # Kubuntu
    sudo apt install git build-essential cmake extra-cmake-modules libplasma-dev
    # openSUSE
    sudo zypper install git cmake extra-cmake-modules libplasma6-devel
    ```

    _Additional dependencies like `kauth` devel packages may be required depending on your distribution, this will be updated later (PRs welcome)_

2. Clone and install

    ```sh
    git clone https://github.com/luisbocanegra/plasma-wallpaper-sync.git
    cd plasma-wallpaper-sync
    ./install.sh
    ```

## Usage

1. Once installed, add the "Wallpaper Sync" widget to your desktop.
2. By default, it will automatically monitor and synchronize wallpaper changes to all monitors, the lock screen, and the login screen, this can be configured in the widget settings.
3. Right click to hide the widget so it only shows in Edit Mode.

### Login Screen Support

This requires that either you or you distribution have switched from SDDM to Plasma Login Manager. You can check if that's the case by running `systemctl is-enabled plasmalogin`, it should return `enabled`.

If it returns `disabled` or `not-found` search for how to do this in your distribution documentation, [instructions for Arch](https://wiki.archlinux.org/title/Plasma_Login_Manager), [instructions for Fedora](https://discussion.fedoraproject.org/t/replace-sddm-with-plasma-login-manager-after-the-upgrade/190632).

## Notes

- Only the configuration is synchronized, plugins that display dynamic content may not stay synchronized everywhere.
- For Plasma Login Manager, only the built-in wallpaper plugins are currently supported. This is because the login manager does not have access (and shouldn't) to other user's files, see [How it works](#how-it-works) for more details.

> [!WARNING]
> [Opening the wallpaper settings dialog may cause a plasmashell crash on Plasma 6.7 and older](https://bugs.kde.org/show_bug.cgi?id=525207), update to Plasma 6.8 or remove the widget while configuring the wallpaper.

## How it works

The widget monitors the desktop wallpaper for changes then:

- Mirrors the new configuration to other monitors using [Plasma D-Bus API](https://invent.kde.org/plasma/plasma-workspace/-/blob/master/shell/dbus/org.kde.PlasmaShell.xml?ref_type=heads).
- For the lock screen it copies the configuration to `$HOME/.config/kscreenlockerrc`
- For the Login Screen it uses KAuth to copy the configuration to `/etc/plasmalogin.conf`.
- When using the Image and Slideshow wallpaper plugins, the current image is copied to plasmalogin's `$HOME/wallpapers` directory

> [!WARNING]
> By default the KAuth actions policy is set to allow all users to change the Login Screen wallpaper without requesting authentication, if you want to change this see the KAuth documentation: <https://develop.kde.org/docs/features/kauth/#the-basic-actions-file> then rebuild from source.

## Acknowledgements

Plasma Login wallpaper helper is a trimmed down version of [Plasma Login Manager KCM](https://invent.kde.org/plasma/plasma-login-manager/-/tree/master/src/frontend/kcm?ref_type=heads)
