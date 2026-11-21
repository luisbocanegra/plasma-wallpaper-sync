pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

KCM.SimpleKCM {
    id: root
    property alias cfg_isEnabled: isEnabled.checked
    property alias cfg_syncAllScreens: syncAllScreens.checked
    property alias cfg_syncLockScreen: syncLockScreen.checked
    property alias cfg_syncLoginScreen: syncLoginScreen.checked

    ColumnLayout {
        Kirigami.InlineMessage {
            id: warningResources
            Layout.fillWidth: true
            type: Kirigami.MessageType.Information
            text: i18n("See README for instructions to install with C++ plugin.")
            visible: !Plasmoid.configuration.pluginAvailable
            actions: Kirigami.Action {
                text: i18n("Install instructions")
                icon.name: "open-link-symbolic"
                onTriggered: Qt.openUrlExternally("https://github.com/luisbocanegra/plasma-wallpaper-sync#build-from-source#installation")
            }
        }
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
                text: i18n("Requires kwriteconfig6 or C++ plugin")
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
                Layout.preferredWidth: 400
                textFormat: Text.RichText
            }

            RowLayout {
                Kirigami.FormData.label: i18n("Login screen:")
                enabled: isEnabled.checked
                CheckBox {
                    id: syncLoginScreen
                }
            }
            Label {
                text: i18n("Requires C++ plugin and Plasma Login Manager. Only works with built-in wallpaper plugins.")
                Layout.preferredWidth: 400
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
                onLinkActivated: link => Qt.openUrlExternally(link)
            }
        }
    }
}
