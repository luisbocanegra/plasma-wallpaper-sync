pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root
    property alias cfg_isEnabled: isEnabled.checked
    property alias cfg_syncAllScreens: syncAllScreens.checked
    property alias cfg_syncLockScreen: syncLockScreen.checked
    property alias cfg_syncLoginScreen: syncLoginScreen.checked

    ColumnLayout {
        Kirigami.FormLayout {
            CheckBox {
                id: isEnabled
                Kirigami.FormData.label: i18n("Enabled:")
            }
            CheckBox {
                id: syncAllScreens
                Kirigami.FormData.label: i18n("Other screens:")
                enabled: isEnabled.checked
            }

            CheckBox {
                id: syncLockScreen
                Kirigami.FormData.label: i18n("Lock screen:")
                enabled: isEnabled.checked
            }

            Label {
                text: i18n("Requires helper or kwriteconfig6")
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
                Layout.preferredWidth: 400
            }

            RowLayout {
                Kirigami.FormData.label: i18n("Login screen:")
                enabled: isEnabled.checked
                CheckBox {
                    id: syncLoginScreen
                }
            }
            Label {
                text: i18n("Requires Plasma Login Manager and helper and only works with the built-in wallpaper plugins. Check the project <a href=\"%1\">README</a> for instructions.", "https://github.com/luisbocanegra/plasma-wallpaper-sync")
                Layout.preferredWidth: 400
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
                onLinkActivated: link => Qt.openUrlExternally(link)
            }
        }
    }
}
