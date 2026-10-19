pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrolsaddons as KQuickControlsAddons
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.dbus as DBus

PlasmoidItem {
    id: root
    readonly property bool isActive: ActiveSync.activeId === Plasmoid.id
    readonly property int activeId: Plasmoid.configuration.activeId
    readonly property bool isEnabled: Plasmoid.configuration.isEnabled && isActive
    readonly property bool syncAllScreens: Plasmoid.configuration.syncAllScreens
    readonly property bool syncLockScreen: Plasmoid.configuration.syncLockScreen
    readonly property bool syncLoginScreen: Plasmoid.configuration.syncLoginScreen
    readonly property var wallpaperItem: Plasmoid.containment?.wallpaperGraphicsObject ?? null
    readonly property var wallpaperConfig: wallpaperItem?.configuration ?? null
    readonly property bool canExpand: root.hasErrors || !root.isActive || !root.onDesktop
    readonly property bool canHide: !hasErrors && isActive && !inEditMode
    readonly property bool hideWidget: {
        return Plasmoid.configuration.hideWidget && canHide;
    }
    readonly property string helperExecutable: "plasma-wallpaper-sync-helper"
    property bool wasExpanded
    property bool inEditMode: Plasmoid.containment?.corona?.editMode ?? false
    property bool onDesktop: Plasmoid.location === PlasmaCore.Types.Floating
    property string pluginName
    property bool hasErrors: errors.length > 0
    property list<var> errors: []
    property bool delay: false
    property bool destroying: false
    property bool completed: false

    function claimSingleton() {
        if (ActiveSync.activeId === -1 && onDesktop && !destroying && completed) {
            ActiveSync.activeId = Plasmoid.id;
            Plasmoid.configuration.activeId = Plasmoid.id;
            Plasmoid.configuration.writeConfig();
        }
    }

    function restoreSingleton() {
        if (ActiveSync.activeId === -1 && onDesktop && !destroying && completed && activeId === Plasmoid.id) {
            ActiveSync.activeId = Plasmoid.id;
        }
    }

    function freeSingleton() {
        if (ActiveSync.activeId !== -1) {
            ActiveSync.activeId = -1;
        }
    }

    Component.onDestruction: {
        destroying = true;
        freeSingleton();
    }

    Component.onCompleted: {
        completed = true;
        restoreSingleton();
        claimSingleton();
    }

    Connections {
        target: ActiveSync
        function onActiveIdChanged() {
            claimSingleton();
        }
    }

    Plasmoid.backgroundHints: hideWidget ? PlasmaCore.Types.NoBackground : PlasmaCore.Types.DefaultBackground
    PlasmaCore.Action {
        id: hideWidgetAction
        text: (Plasmoid.configuration.hideWidget ? i18n("Show") : i18n("Hide")) + " widget"
        icon.name: "visibility-symbolic"
        onTriggered: {
            Plasmoid.configuration.hideWidget = !Plasmoid.configuration.hideWidget;
            Plasmoid.configuration.writeConfig();
        }
        enabled: root.canHide
    }
    Plasmoid.contextualActions: hideWidgetAction

    function setDesktopAllScreens(plugin: string, config: var) {
        for (let i = 0; i < Application.screens.length; i++) {
            if (i === root.screen) {
                continue;
            }
            const reply = DBus.SessionBus.asyncCall({
                "service": "org.kde.plasmashell",
                "path": "/PlasmaShell",
                "iface": "org.kde.PlasmaShell",
                "member": "setWallpaper",
                "arguments": [plugin, config, i],
                "signature": "",
                "inSignature": "sa{sv}u"
            }) as DBus.DBusPendingReply;
            reply.finished.connect(() => {
                if (reply.isError) {
                    const [where, message] = ["Desktop", `Failed to set wallpaper: ${reply.error.message}`];
                    console.error(message);
                    errors.push({
                        where,
                        message
                    });
                }
                reply.destroy();
            });
        }
    }

    function shellQuote(s: string): string {
        return "'" + s.replace(/'/g, "'\\''") + "'";
    }

    function setLockScreen(plugin: string, config: string) {
        const helperCommand = `${shellQuote(helperExecutable)} --lock --plugin ${plugin} --config ${shellQuote(config)}`;
        runCommand.exec(helperCommand, output => {
            if (output.exitCode !== 0) {
                const error = output.stderr.trim() || output.stdout.trim();
                setLockScreenFallback(plugin, config, error);
            }
        });
    }

    function setLockScreenFallback(plugin: string, config: string, helperError: string) {
        const kwrite = "kwriteconfig6 --file kscreenlockerrc --group Greeter ";
        const cmds = [kwrite + "--key WallpaperPlugin " + shellQuote(plugin)];
        const group = kwrite + "--group Wallpaper --group " + shellQuote(plugin) + " --group General --key ";
        for (let key in config) {
            cmds.push(group + shellQuote(key) + " " + shellQuote(config[key]));
            if (key === "Image") {
                cmds.push(group + "PreviewImage " + shellQuote(config[key]));
            }
        }
        runCommand.exec(cmds.join(" && "), output => {
            if (output.exitCode !== 0) {
                let [where, message] = ["Lock(helper)", `Failed to set wallpaper: ${helperError}`];
                errors.push({
                    where,
                    message
                });
                console.warn(`${where}: ${message}`);

                const fallbackError = output.stderr.trim() || output.stdout.trim();
                [where, message] = ["Lock(fallback)", `Failed to set wallpaper: ${fallbackError}`];
                errors.push({
                    where,
                    message
                });
                console.warn(`${where}: ${message}`);
            }
        });
    }

    function setPlasmaLogin(plugin: string, config: string) {
        const helperCommand = `${shellQuote(helperExecutable)} --login --plugin ${plugin} --config ${shellQuote(config)}`;
        runCommand.exec(helperCommand, output => {
            if (output.exitCode !== 0) {
                const error = output.stderr.trim() || output.stdout.trim();
                const [where, message] = ["Login", `Failed to set wallpaper: ${error}`];
                console.warn(`${where}: ${message}`);
                errors.push({
                    where,
                    message
                });
            }
        });
    }

    function serializeConfig(config) {
        const to255 = val => Math.min(255, Math.max(0, Math.round(val * 255)));
        return JSON.stringify(config, function (key, value) {
        // qmlformat off
        if (typeof value === "object" && value !== null &&
            typeof value.r === "number" && typeof value.g === "number" &&
            typeof value.b === "number" && typeof value.a === "number") {
                // qmlformat on
                return `${to255(value.r)},${to255(value.g)},${to255(value.b)}`;
            }
            return value;
        });
    }

    function getConfig() {
        let config = {};
        for (let key in wallpaperConfig) {
            if (key.endsWith("Default")) {
                continue;
            }
            if (typeof wallpaperConfig[key] === 'function') {
                continue;
            }
            let value = wallpaperConfig[key];
            let defaultValue = wallpaperConfig[key + "Default"];
            if (value && value != defaultValue) {
                config[key] = value;
            }
        }
        return config;
    }

    function syncWallpaper() {
        if (!isEnabled || root.pluginName === "") {
            return;
        }
        errors = [];
        let plugin = pluginName;
        if (plugin === "org.kde.slideshow") {
            plugin = "org.kde.image";
        }
        const config = getConfig();
        if (syncAllScreens) {
            setDesktopAllScreens(plugin, config);
        }
        const serialized = serializeConfig(config);
        if (syncLockScreen) {
            setLockScreen(plugin, serialized);
        }
        if (syncLoginScreen) {
            setPlasmaLogin(plugin, serialized);
        }
    }

    onIsEnabledChanged: Qt.callLater(root.syncWallpaper)
    onSyncAllScreensChanged: Qt.callLater(root.syncWallpaper)
    onSyncLockScreenChanged: Qt.callLater(root.syncWallpaper)
    onSyncLoginScreenChanged: Qt.callLater(root.syncWallpaper)

    RunCommand {
        id: runCommand
    }

    Timer {
        id: delayTimer
        interval: 100
        onTriggered: {
            root.delay = false;
            syncWallpaper();
        }
    }

    Connections {
        target: root.wallpaperConfig
        function onValueChanged(key, property) {
            if (root.delay) {
                return;
            }
            Qt.callLater(root.syncWallpaper);
        }
    }

    onWallpaperItemChanged: {
        pluginName = wallpaperItem?.pluginName ?? "";
        root.delay = true;
        delayTimer.restart();
    }
    toolTipSubText: {
        if (!onDesktop) {
            return i18n("Inactive: this widget only works on the desktop");
        } else if (root.hasErrors) {
            return i18n("Something went wrong");
        } else if (!root.isActive) {
            return i18n("Inactive: another instance of this widget is already active.");
        }
        return Plasmoid.metaData.description;
    }
    toolTipTextFormat: Text.RichText
    Plasmoid.icon: {
        if (!onDesktop) {
            return "dialog-cancel-symbolic";
        }
        if (root.hasErrors) {
            return "dialog-warning-symbolic";
        }
        if (!root.isActive) {
            return ActiveSync.activeId === -1 ? "content-loading-symbolic" : "dialog-cancel-symbolic";
        }
        return "viewimage-symbolic";
    }

    compactRepresentation: MouseArea {
        id: compact
        anchors.fill: parent

        Kirigami.Icon {
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.roundedIconSize(Math.min(parent.width, parent.height))
            height: width
            source: Plasmoid.icon
            color: !root.onDesktop ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            visible: !root.hideWidget
        }

        onPressed: {
            if (root.canExpand) {
                root.wasExpanded = root.expanded;
            }
        }
        onClicked: {
            if (root.canExpand) {
                root.expanded = !root.wasExpanded;
            }
        }
    }

    KQuickControlsAddons.Clipboard {
        id: clipboard
    }

    preferredRepresentation: compactRepresentation
    fullRepresentation: Item {
        id: fullRep
        Layout.minimumWidth: Kirigami.Units.gridUnit * 25
        Layout.minimumHeight: col.implicitHeight
        Layout.maximumWidth: Kirigami.Units.gridUnit * 25
        Layout.maximumHeight: col.implicitHeight
        ColumnLayout {
            id: col
            anchors.fill: parent
            PlasmaComponents.Label {
                visible: !root.isActive || !root.onDesktop
                text: toolTipSubText
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            PlasmaComponents.ToolButton {
                text: i18n("Copy to clipboard")
                visible: root.hasErrors
                Layout.alignment: Qt.AlignHCenter
                icon.name: "edit-copy-symbolic"
                onClicked: {
                    clipboard.content = errors.map(e => `${e.where}: ${e.message}`).join("\n");
                }
            }
            Kirigami.AbstractCard {
                Layout.fillWidth: true
                Layout.maximumHeight: Kirigami.Units.gridUnit * 15
                visible: root.hasErrors
                contentItem: PlasmaComponents.ScrollView {
                    Layout.fillWidth: true
                    TextArea {
                        text: errors.map(e => `${e.where}: ${e.message}`).join("\n")
                        font: Kirigami.Theme.smallFont
                        // HACK: silence binding loop warnings.
                        // contentWidth seems to be causing the binding loop,
                        // but contentWidth is read-only and we have no control
                        // over how it is calculated.
                        implicitWidth: 0
                        Layout.fillWidth: true
                        wrapMode: Text.WrapAnywhere
                        background: Item {}
                        cursorVisible: false
                    }
                }
            }
        }
    }
}
