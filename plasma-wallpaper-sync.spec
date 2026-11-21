%global debug_package %{nil}

Name:           plasma-wallpaper-sync
Version:        0.1.0
Release:        1%{?dist}
Summary:        KDE Plasma widget to sync the wallpaper to other desktops and screens

License:        GPL-3.0-only
URL:            https://github.com/luisbocanegra/plasma-wallpaper-sync
Source0:        %{URL}/archive/refs/tags/v%{version}.tar.gz#/%{name}-%{version}.tar.gz

BuildRequires:  cmake
BuildRequires:  gcc-c++
BuildRequires:  extra-cmake-modules
BuildRequires:  kf6-rpm-macros
BuildRequires:  gettext
BuildRequires:  qt6-qtbase-devel
BuildRequires:  qt6-qtdeclarative-devel
BuildRequires:  libplasma-devel
BuildRequires:  kf6-kconfig-devel
BuildRequires:  kf6-kcoreaddons-devel
BuildRequires:  kf6-kauth-devel

Requires:       plasma-workspace >= 6.4.0
Requires:       libplasma
Requires:       qt6-qtbase
Requires:       qt6-qtdeclarative
Requires:       kf6-kconfig
Requires:       kf6-kcoreaddons
Requires:       kf6-kauth
Requires:       polkit

%description
A KDE Plasma widget that synchronizes the wallpaper currently shown on the
desktop to other monitors, the lock screen and the Plasma Login Manager
login screen.

The widget watches for wallpaper changes and applies the new configuration
through the Plasma D-Bus API. Lock screen support is handled by copying the
configuration to kscreenlockerrc, while login screen support uses a KAuth
helper to update plasmalogin's configuration and wallpaper directory.

%prep
%autosetup -n %{name}-%{version}

%build
# The bundled .po translations are compiled to .mo by the build itself
# (package/translate/build.sh, wired through CMake); gettext is required.
%cmake_kf6 \
    -DINSTALL_PLASMOID=ON \
    -DBUILD_HELPER=ON \
    -DPACKAGE_PLASMOID=OFF
%cmake_build

%install
%cmake_install

%files
%license LICENSE
%doc README.md
# Plasmoid package (metadata.json, QML, bundled translations)
%{_kf6_datadir}/plasma/plasmoids/luisbocanegra.wallpaper.sync/
# KAuth helper used to write the login screen configuration. The KF6 D-Bus
# backend activates it as root via D-Bus, so it is installed with normal 0755
# permissions (no setuid bit).
%{_kf6_libexecdir}/kauth/wallpapersync_kauthhelper
# kauth_install_actions() turns the .actions file into a .policy file via
# kauth-policy-gen and installs it under polkit's actions directory.
%{_datadir}/polkit-1/actions/luisbocanegra.plasma.wallpapersync.policy
# kauth_install_helper_files() installs the D-Bus system policy and service
# files used to activate the helper on the system bus.
%{_datadir}/dbus-1/system.d/luisbocanegra.plasma.wallpapersync.conf
%{_datadir}/dbus-1/system-services/luisbocanegra.plasma.wallpapersync.service
# Command line helper for scripting and troubleshooting
%{_bindir}/plasma-wallpaper-sync-helper
# C++ QML module imported by the widget
%{_qt6_qmldir}/com/github/luisbocanegra/wallpapersync/

%changelog
* Sat Nov 21 2026 KairikiFedora <13278297951@sina.cn> - 0.1.0-1
- Fix packaging of the KAuth helper: ship the generated .policy file
  (not the .actions source) and the D-Bus system .conf/.service files;
  drop the incorrect setuid attribute on the helper binary.
- Initial RPM package with German, French, Japanese, Korean, Simplified
  Chinese and Traditional Chinese translations.
