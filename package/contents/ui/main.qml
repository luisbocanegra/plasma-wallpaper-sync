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
    property bool wasExpanded
    property bool inEditMode: Plasmoid.containment?.corona?.editMode ?? false
    property bool onDesktop: Plasmoid.location === PlasmaCore.Types.Floating
    property string pluginName
    property bool delay: false
    property bool destroying: false
    property bool completed: false
    property string configString
    property var config: ({})
    property string lastUsedPlugin
    readonly property bool pluginAvailable: syncPlugin !== null
    property var syncPlugin: null
    readonly property bool hasErrors: errorsModel.count > 0

    ListModel {
        id: errorsModel
    }

    function loadPlugin() {
        // qmlformat off
        try {
            syncPlugin = Qt.createQmlObject(
                'import com.github.luisbocanegra.wallpapersync 1.0; WallpaperSync {}',
                root,
                "DynamicWallpaperSync"
            );
        } catch (e) {
            console.debug("WallpaperSync plugin not found:", e);
        }
        if (Plasmoid.configuration.pluginAvailable !== pluginAvailable) {
            Plasmoid.configuration.pluginAvailable = pluginAvailable;
            Plasmoid.configuration.writeConfig();
        }
        // qmlformat on
    }

    function setError(where: string, message) {
        let index = -1;
        for (let i = 0; i < errorsModel.count; i++) {
            if (errorsModel.get(i).where === where) {
                index = i;
                break;
            }
        }
        if (!message) {
            if (index >= 0) {
                errorsModel.remove(index);
            }
        } else {
            if (index >= 0) {
                errorsModel.setProperty(index, "message", message);
            } else {
                errorsModel.append({
                    where,
                    message
                });
            }
        }
    }

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

    // We need a way to update the login wallpaper before plasmalogin
    // loads when switching users, this takes advantage of the fact that
    // the session is locked before that happens
    DBus.SignalWatcher {
        busType: DBus.BusType.Session
        service: "org.freedesktop.ScreenSaver"
        path: "/ScreenSaver"
        iface: "org.kde.screensaver"
        function dbusAboutToLock() {
            console.log(Plasmoid.id, "About to lock");
            if (root.syncLoginScreen) {
                setPlasmaLogin(lastUsedPlugin, root.configString);
            }
        }
    }

    Connections {
        target: Qt.application
        function onAboutToQuit() {
            console.log(Plasmoid.id, "About to quit");
            if (root.syncLoginScreen) {
                setPlasmaLogin(lastUsedPlugin, root.configString);
            }
        }
        function onScreensChanged() {
            console.log(Plasmoid.id, "Monitors changed");
            if (syncAllScreens) {
                setDesktopAllScreens(lastUsedPlugin, config);
            }
        }
    }

    Component.onDestruction: {
        destroying = true;
        freeSingleton();
    }

    Component.onCompleted: {
        loadPlugin();
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
        text: Plasmoid.configuration.hideWidget ? i18n("Show widget") : i18n("Hide widget")
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
            const where = `Desktop(dbus)`;
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
                    const message = `Failed to set wallpaper: ${reply.error.message}`;
                    console.warn(message);
                    setError(where, message);
                } else {
                    setError(where);
                }
                reply.destroy();
            });
        }
    }

    function shellQuote(s: string): string {
        return "'" + s.replace(/'/g, "'\\''") + "'";
    }

    function setLockScreen(plugin: string, config: var, configString: string) {
        let error;
        if (pluginAvailable) {
            error = syncPlugin.setLockScreenWallpaper(plugin, configString);
            if (!error) {
                return;
            }
        } else {
            error = "Plugin not found";
        }
        setLockScreenKwriteConfigFallback(plugin, config, error);
    }

    function setLockScreenKwriteConfigFallback(plugin: string, config: var, pluginError: string) {
        const kwrite = "kwriteconfig6 --file kscreenlockerrc --group Greeter ";
        const cmds = [kwrite + "--key WallpaperPlugin " + shellQuote(plugin)];
        const group = kwrite + "--group Wallpaper --group " + shellQuote(plugin) + " --group General --key ";
        for (let key in config) {
            cmds.push(group + shellQuote(key) + " " + shellQuote(config[key]));
        }
        runCommand.exec(cmds.join(" && "), output => {
            if (output.exitCode !== 0) {
                let where = "Lock(plugin)";
                let message = `Failed to set wallpaper: ${pluginError}`;
                setError(where, message);
                console.warn(`${where}: ${message}`);

                const fallbackError = output.stderr.trim() || output.stdout.trim();
                where = "Lock(fallback)";
                message = `Failed to set wallpaper: ${fallbackError}`;
                setError(where, message);
                console.warn(`${where}: ${message}`);
            } else {
                setError("Lock(plugin)");
                setError("Lock(fallback)");
            }
        });
    }

    // FIXME(?): KAuth logs a warning about the parent window (DesktopView)
    // not being an XDG toplevel window
    function setPlasmaLogin(plugin: string, configString: string) {
        let error;
        if (pluginAvailable) {
            error = syncPlugin.setPlasmaLoginWallpaper(plugin, configString);
        } else {
            error = "Plugin not found";
        }

        const where = "Login(plugin)";
        let message;
        if (error) {
            message = `Failed to set wallpaper: ${error}`;
            console.warn(`${where}: ${message}`);
        }
        setError(where, message);
    }

    // Plugins may save colors as Color type, we need to convert them
    // to a format plugins can read back from the configuration file
    function serializeConfig(config) {
        const to255 = val => Math.min(255, Math.max(0, Math.round(val * 255)));
        const rgbToHex = (red, green, blue) => {
            const rgb = (to255(red) << 16) | (to255(green) << 8) | (to255(blue) << 0);
            return '#' + (0x1000000 + rgb).toString(16).slice(1);
        };
        return JSON.stringify(config, function (key, value) {
            // qmlformat off
            if (typeof value === "object" && value !== null &&
                typeof value.r === "number" && typeof value.g === "number" &&
                typeof value.b === "number" && typeof value.a === "number") {
                return `${rgbToHex(value.r, value.g, value.b)}`
            }
            // qmlformat on
            return value;
        });
    }

    // Plugins may save colors as Color type, we need to convert them
    // to a format plugins can be sent over dbus and the configuration files
    function convertValue(value) {
        const to255 = val => Math.min(255, Math.max(0, Math.round(val * 255)));
        const rgbToHex = (red, green, blue) => {
            const rgb = (to255(red) << 16) | (to255(green) << 8) | (to255(blue) << 0);
            return '#' + (0x1000000 + rgb).toString(16).slice(1);
        };
        // qmlformat off
        if (typeof value === "object" && value !== null &&
            typeof value.r === "number" && typeof value.g === "number" &&
            typeof value.b === "number" && typeof value.a === "number") {
            return `${rgbToHex(value.r, value.g, value.b)}`
        }
        // qmlformat on
        return value;
    }

    function getConfig() {
        let config = {};
        for (let key of wallpaperConfig.keys()) {
            if (key.endsWith("Default")) {
                continue;
            }
            const value = wallpaperConfig[key];
            console.log(key, value);
            // Not sure if this is even possible but doesn't hurt to check
            if (value === null || value === undefined) {
                continue;
            }
            config[key] = convertValue(value);
        }
        return config;
    }

    function syncWallpaper() {
        if (!isEnabled || !root.pluginName) {
            return;
        }
        lastUsedPlugin = pluginName;
        if (lastUsedPlugin === "org.kde.slideshow") {
            lastUsedPlugin = "org.kde.image";
        }
        // Deep copy because the KConfigPropertyMap can change and have
        // invalid values, notably example is when all monitors are unplugged
        configString = JSON.stringify(getConfig());
        config = JSON.parse(configString);
        console.log(JSON.stringify(config));
        if (syncAllScreens) {
            setDesktopAllScreens(lastUsedPlugin, config);
        }
        if (syncLockScreen) {
            setLockScreen(lastUsedPlugin, config, configString);
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
                    clipboard.content = errorsTextArea.text;
                }
            }
            Kirigami.AbstractCard {
                Layout.fillWidth: true
                Layout.maximumHeight: Kirigami.Units.gridUnit * 15
                visible: root.hasErrors
                contentItem: PlasmaComponents.ScrollView {
                    Layout.fillWidth: true
                    TextArea {
                        id: errorsTextArea
                        text: {
                            const errorTexts = [];
                            for (let i = 0; i < errorsModel.count; i++) {
                                const item = errorsModel.get(i);
                                errorTexts.push(`${item.where}: ${item.message}`);
                            }
                            return errorTexts.join("\n");
                        }
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
