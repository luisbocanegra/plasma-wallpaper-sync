/*
 *  SPDX-FileCopyrightText: 2014 Martin Gräßlin <mgraesslin@kde.org>
 *  SPDX-FileCopyrightText: 2019 Kevin Ottens <kevin.ottens@enioka.com>
 *  SPDX-FileCopyrightText: 2020 David Redondo <kde@david-redondo.de>
 *  SPDX-FileCopyrightText: 2025 Oliver Beard <olib141@outlook.com>
 *  SPDX-FileCopyrightText: 2026 Luis Bocanegra <luisbocanegra17b@gmail.com>
 *
 *  SPDX-License-Identifier: GPL-2.0-or-later
 */

#include <KAuth/Action>
#include <KAuth/ExecuteJob>
#include <KConfig>
#include <KConfigGroup>
#include <KSharedConfig>
#include <KUser>

#include "config.h"
#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QDBusUnixFileDescriptor>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMap>
#include <QTemporaryDir>
#include <QTextStream>
#include <QUrl>

#include "plasmaloginauthhelper.h"
#include "validation.h"

using namespace Qt::StringLiterals;

static int setLockScreenWallpaper(const QString &plugin, const QString &configJson, QString &error)
{
    QMap<QString, QString> values;
    if (!parseWallpaperConfig(plugin, configJson, values, error)) {
        return 1;
    }

    KSharedConfigPtr screenLockerConfig = KSharedConfig::openConfig(u"kscreenlockerrc"_s);

    if (screenLockerConfig->accessMode() != KConfig::ReadWrite) {
        error = u"cannot write "_s + screenLockerConfig->name();
        return 1;
    }

    KConfigGroup greeter = screenLockerConfig->group(u"Greeter"_s);
    greeter.writeEntry(u"WallpaperPlugin"_s, plugin);
    KConfigGroup general = greeter.group(u"Wallpaper"_s).group(plugin).group(u"General"_s);
    for (auto it = values.begin(); it != values.end(); ++it) {
        // PreviewImage is a supposedly transient state for previewing, we don't want to save this to disk
        if (it.key() == QLatin1String("PreviewImage")) {
            continue;
        }
        general.writeEntry(it.key(), it.value());
    }

    if (!screenLockerConfig->sync()) {
        error = u"failed to sync config"_s;
        return 1;
    }
    return 0;
}

QVariantMap syncWallpaper(const QUrl &imageUri, QString &error)
{
    const QString baseName = imageUri.fileName();
    const QString imagePath = imageUri.toLocalFile();

    if (imagePath.isEmpty()) {
        return {};
    }

    QVariantMap wallpaperArgs;
    QStringList files;

    // We open the file and pass an FD so the root helper knows our user can read the contents
    auto addFile = [&wallpaperArgs, &files, &error](const QString &relativePath, const QString &fullPath) {
        files.append(relativePath);
        QFile imageFile(fullPath);
        if (imageFile.open(QIODevice::ReadOnly)) {
            // There's a silly quirk in KAuth that we can only pass FDs on the top level of the QVariantMap as it's handled specially
            // Hence one entry for the list of files, then one entry per file descriptor.
            wallpaperArgs["_fd_" + relativePath] = QVariant::fromValue(QDBusUnixFileDescriptor(imageFile.handle()));
        } else {
            error = "Could not read file " + fullPath;
        }
    };

    QFileInfo fileInfo(imagePath);
    if (fileInfo.isDir()) {
        // special case, it's a package
        addFile(baseName + "/metadata.json", imagePath + "/metadata.json");
        QDir imagesDir(imagePath + "/contents/images");
        for (const QString &imageFileName : imagesDir.entryList(QDir::Files)) {
            addFile(baseName + "/contents/images/" + imageFileName, imagePath + "/contents/images/" + imageFileName);
        }
        QDir darkImagesDir(imagePath + "/contents/images_dark");
        for (const QString &imageFileName : darkImagesDir.entryList(QDir::Files)) {
            addFile(baseName + "/contents/images_dark/" + imageFileName, imagePath + "/contents/images_dark/" + imageFileName);
        }
    } else {
        addFile(baseName, imagePath);
    }
    wallpaperArgs.insert("wallpapers", files);
    return wallpaperArgs;
}

static int setPlasmaLoginWallpaper(const QString &plugin, const QString &configJson, QString &error)
{
    QMap<QString, QString> values;
    const bool isLoginScreen = true;
    if (!parseWallpaperConfig(plugin, configJson, values, error, isLoginScreen)) {
        return 1;
    }

    QTemporaryDir tempDir;
    if (!tempDir.isValid()) {
        error = "Failed to create temporary directory";
        return 1;
    }

    QString homeDirPath;

    if (auto opt = plasmaloginUserHomeDir()) {
        homeDirPath = *opt;
    } else {
        error = "Could not determine home directory for plasmalogin user";
        return 1;
    }

    QVariantMap args;

    const QString tempFileName = tempDir.path() + QLatin1String("/plasmalogin.conf");

    KConfig tempConfig(tempFileName, KConfig::SimpleConfig);
    KConfigGroup greeter = tempConfig.group(u"Greeter"_s);

    greeter.writeEntry(u"WallpaperPluginId"_s, plugin);
    KConfigGroup general = greeter.group(u"Wallpaper"_s).group(plugin).group(u"General"_s);

    for (auto it = values.begin(); it != values.end(); ++it) {
        // PreviewImage is a supposedly transient state for previewing, we don't want to save this to disk
        if (it.key() == QLatin1String("PreviewImage")) {
            continue;
        }
        general.writeEntry(it.key(), it.value());
    }

    args.clear();

    // For image wallpapers we want to copy the user-set image
    auto imageWallpaperGroup = tempConfig.group(u"Greeter"_s).group(u"Wallpaper"_s).group(u"org.kde.image"_s);
    if (imageWallpaperGroup.exists()) {
        // PreviewImage is a supposedly transient state for previewing, we don't want to save this to disk
        imageWallpaperGroup.group(u"General"_s).deleteEntry(u"PreviewImage"_s);

        if (values.contains(u"Image"_s)) {
            // Copy the original image to somewhere the greeter can read it
            const QUrl imageUri = QUrl(values.value(u"Image"_s), QUrl::StrictMode).adjusted(QUrl::StripTrailingSlash);
            if (!imageUri.isValid() || imageUri.scheme().isEmpty()) {
                error = "not a valid url, e.g 'file:///path/to/wallpaper.png'";
                return 1;
            }
            if (imageUri.isLocalFile()) {
                args.insert(syncWallpaper(imageUri, error));

                if (!error.isEmpty()) {
                    return 1;
                }

                QUrl adjustedUri = QUrl();
                adjustedUri.setScheme(u"file"_s);
                adjustedUri.setPath(homeDirPath + "/wallpapers/" + imageUri.fileName());
                adjustedUri.setFragment(imageUri.fragment());
                imageWallpaperGroup.group(u"General"_s).writeEntry(u"Image"_s, adjustedUri);
            } else {
                error = "'" + imageUri.toString() + "' is not a local file";
                return 1;
            }
        }
    }

    // Write our temporary saved config to be read back into auth helper args
    // NOTE: If the config ends up empty, then sync won't write the file and
    //       we'd trip up on that later
    const bool configHasContent = tempConfig.isDirty();
    if (configHasContent) {
        tempConfig.sync();
    }

    // Read our temporary saved config into auth helper args
    QString config;
    if (configHasContent) {
        QFile tempFile(tempFileName);
        if (!tempFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            qWarning() << "failed to open temporary config file for reading";
            return 1;
        }

        QTextStream in(&tempFile);
        config = in.readAll();
    }

    args[u"config"_s] = config;

    KAuth::Action saveAction(u"luisbocanegra.plasma.wallpapersync.save"_s);
    saveAction.setHelperId(u"luisbocanegra.plasma.wallpapersync"_s);
    saveAction.setArguments(args);
    KAuth::ExecuteJob *saveJob = saveAction.execute();
    if (!saveJob->exec()) {
        error = saveJob->errorString();
        return 1;
    }
    return 0;
}

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    QCoreApplication::setApplicationName("Plasma Wallpaper Sync Helper");
    QCoreApplication::setApplicationVersion("0.1.0");

    QCommandLineParser parser;
    parser.setApplicationDescription("Plasma Wallpaper Sync Helper");
    parser.addHelpOption();
    parser.addVersionOption();

    QCommandLineOption lockScreenOption(QStringList() << "lock", "Set wallpaper for the lock screen.");
    parser.addOption(lockScreenOption);

    QCommandLineOption plasmaloginOption(QStringList() << "login", "Set wallpaper for the login screen.");
    parser.addOption(plasmaloginOption);

    QCommandLineOption pluginOption(QStringList() << "plugin", "The wallpaper plugin to use, by default org.kde.image.", "pluginName", "org.kde.image");
    parser.addOption(pluginOption);

    QCommandLineOption configOption(QStringList() << "config", "The plugin configuration in JSON format", "jsonString");
    parser.addOption(configOption);

    parser.process(app);

    QTextStream tsOut(stdout);
    QTextStream tsErr(stderr);
    QString error;

    const QString plugin = parser.value(pluginOption);
    QString config = parser.value(configOption);

    if (config.isEmpty()) {
        tsErr << "Must give config" << Qt::endl;
        parser.showHelp(1);
    }

    int ret{};
    if (parser.isSet(lockScreenOption)) {
        ret = setLockScreenWallpaper(plugin, config, error);
    }
    if (parser.isSet(plasmaloginOption)) {
        ret = setPlasmaLoginWallpaper(plugin, config, error);
    }
    if (ret != 0) {
        if (!error.isEmpty()) {
            tsErr << error << Qt::endl;
        }
        return 1;
    }
    return 0;
}
