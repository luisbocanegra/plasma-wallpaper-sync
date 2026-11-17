/*
    SPDX-FileCopyrightText: 2019 Filip Fila <filipfila.kde@gmail.com>
    SPDX-FileCopyrightText: 2013 Reza Fatahilah Shah <rshah0385@kireihana.com>
    SPDX-FileCopyrightText: 2011, 2012 David Edmundson <kde@davidedmundson.co.uk>
    SPDX-FileCopyrightText: 2026 Luis Bocanegra <luisbocanegra17b@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
 */
#include "plasmaloginauthhelper.h"
#include "config.h"

#include <dirent.h>
#include <fcntl.h> /* Definition of O_* and S_* constants */
#include <linux/openat2.h> /* Definition of RESOLVE_* constants */
#include <qchar.h>
#include <qdebug.h>
#include <sys/stat.h>
#include <sys/syscall.h> /* Definition of SYS_* constants */
#include <sys/wait.h>
#include <unistd.h>

#include <QBuffer>
#include <QDBusUnixFileDescriptor>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMimeDatabase>
#include <QMimeType>
#include <QSharedPointer>

#include <KConfig>
#include <KConfigGroup>
#include <KLazyLocalizedString>
#include <KLocalizedString>
#include <KUser>

static const QFile::Permissions standardPermissions = QFile::ReadOwner | QFile::WriteOwner | QFile::ReadGroup | QFile::ReadOther;

template<typename Func>
static bool runAsPlasmaLoginUser(Func function)
{
    KUser user("plasmalogin");
    if (!user.isValid()) {
        qWarning() << "Could not find plasmalogin user";
        return false;
    }
    pid_t pid = fork();
    if (pid < 0) {
        qWarning() << "Failed to fork plasmalogin helper process";
        return false;
    } else if (pid == 0) {
        if (setgid(user.groupId().nativeId()) != 0) {
            qWarning() << "Failed to setgid in plasmalogin helper subprocess";
            _exit(EXIT_FAILURE);
        }
        if (setuid(user.userId().nativeId()) != 0) {
            qWarning() << "Failed to setuid in plasmalogin helper subprocess";
            _exit(EXIT_FAILURE);
        }

        if (function()) {
            _exit(EXIT_SUCCESS);
        } else {
            _exit(EXIT_FAILURE);
        }
    } else {
        int status;
        if (waitpid(pid, &status, 0) < 0) {
            return false;
        }
        return status == EXIT_SUCCESS;
    }
}

static bool adjustOwnershipRecursively(int dirFd, uid_t uid, gid_t gid, const QString &path)
{
    bool success = true;

    DIR *dir = fdopendir(dirFd);
    if (!dir) {
        qWarning() << "Could not open directory stream for" << path << ":" << strerror(errno);
        close(dirFd);
        return false;
    }
    auto closeDir = qScopeGuard([dir]() {
        closedir(dir);
    });

    while (dirent *entry = readdir(dir)) {
        const QByteArray name(entry->d_name);
        if (name == "." || name == "..") {
            continue;
        }

        struct stat statBuf;
        if (fstatat(dirFd, name.constData(), &statBuf, AT_SYMLINK_NOFOLLOW) != 0) {
            qWarning() << "Could not stat" << path + QLatin1Char('/') + QString::fromUtf8(name) << ":" << strerror(errno);
            success = false;
            continue;
        }

        if (S_ISLNK(statBuf.st_mode)) {
            continue;
        }

        if (S_ISDIR(statBuf.st_mode)) {
            struct open_how how = {.flags = O_RDONLY | O_DIRECTORY | O_CLOEXEC,
                                   .mode = 0,
                                   .resolve = RESOLVE_BENEATH | RESOLVE_NO_MAGICLINKS};
            const int childFd = syscall(SYS_openat2, dirFd, name.constData(), &how, sizeof(struct open_how));
            if (childFd < 0) {
                qWarning() << "Could not open directory" << path + QLatin1Char('/') + QString::fromUtf8(name) << ":" << strerror(errno);
                success = false;
                continue;
            }

            success = adjustOwnershipRecursively(childFd, uid, gid, path + QLatin1Char('/') + QString::fromUtf8(name)) && success;
        }

        if (fchownat(dirFd, name.constData(), uid, gid, AT_SYMLINK_NOFOLLOW) != 0) {
            qWarning() << "Could not change owner of" << path + QLatin1Char('/') + QString::fromUtf8(name) << ":" << strerror(errno);
            success = false;
        }
    }

    return success;
}

bool PlasmaLoginAuthHelper::adjustPermissionsFromPlasma6_6()
{
    // Plasma 6.6 ran some things as root. For 6.7 onwards we run them as the
    // plasmalogin user, so upgraded installations may need ownership repaired.
    KUser user(QStringLiteral("plasmalogin"));
    if (!user.isValid()) {
        qWarning() << "Could not find plasmalogin user";
        return false;
    }

    const QString homeDirPath = user.homeDir();
    if (homeDirPath.isEmpty()) {
        qWarning() << "Could not determine home directory for plasmalogin user";
        return false;
    }

    const QByteArray homeDirPathUtf8 = homeDirPath.toUtf8();
    const int homeDirFd = open(homeDirPathUtf8.constData(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (homeDirFd < 0) {
        qWarning() << "Could not open home directory for plasmalogin user:" << strerror(errno);
        return false;
    }

    return adjustOwnershipRecursively(homeDirFd, user.userId().nativeId(), user.groupId().nativeId(), homeDirPath);
}

static bool isRegularFd(int fd)
{
    int flags = fcntl(fd, F_GETFL);
    if (flags == -1) {
        return false;
    }
    if (flags & O_PATH) {
        return false;
    }
    struct stat st;
    if (fstat(fd, &st) == -1) {
        return false;
    }
    return S_ISREG(st.st_mode);
}

ActionReply PlasmaLoginAuthHelper::save(const QVariantMap &args)
{
    QString configStr = args[QStringLiteral("config")].toString();

    // Only write if we have content
    ActionReply errorReply = ActionReply::HelperErrorReply();
    if (!configStr.isEmpty()) {
        QFile file(QLatin1String(PLASMALOGIN_CONFIG_FILE));
        if (!file.open(QIODevice::WriteOnly | QIODevice::Text | QIODevice::Truncate, standardPermissions)) {
            errorReply.setErrorDescription(file.errorString());
            return errorReply;
        }

        if (configStr.toUtf8().size() > 1 * 1024 * 1024) {
            errorReply.setErrorDescription("Config size is greater than 1 MiB");
            return errorReply;

        } else {
            QTextStream out(&file);
            out << configStr;
            out.flush();
        }

        file.close();

        // Ensure permissions on the config file are appropriate
        if (file.permissions() != standardPermissions) {
            file.setPermissions(standardPermissions);
        }
    }

    // Wallpaper stuff
    // This is in /var/plasmalogin so we drop privileges
    QString homeDirPath;
    if (auto opt = plasmaloginUserHomeDir()) {
        homeDirPath = *opt;
    } else {
        errorReply.setErrorDescription("Could not determine home directory for plasmalogin user");
        return errorReply;
    }

    if (!adjustPermissionsFromPlasma6_6()) {
        return ActionReply::HelperErrorReply();
    }

    bool rc = runAsPlasmaLoginUser([homeDirPath, args, &errorReply]() {
        QDir homeDir(homeDirPath);
        QDir wallpaperDir(homeDir.absoluteFilePath("wallpapers"));
        if (!wallpaperDir.removeRecursively()) {
            qWarning() << "Could not clean old wallpaper directory";
        }
        homeDir.mkdir("wallpapers");

        auto rootWallpaperFd = open(wallpaperDir.path().toUtf8().constData(), O_RDONLY | O_DIRECTORY);
        if (rootWallpaperFd < 0) {
            errorReply.setErrorDescription("Could not load root wallpaper directory." + QString(strerror(errno)));
            return false;
        }
        auto closeRootWallpaperFd = qScopeGuard([&]() {
            close(rootWallpaperFd);
        });

        const QStringList wallpapers = args[QStringLiteral("wallpapers")].toStringList();
        for (const QString &wallpaper : wallpapers) {
            // This shouldn't be needed with the explicit openat flags, but
            // another check can't hurt
            if (wallpaper.contains("..")) {
                errorReply.setErrorDescription("Badly formed wallpaper name detected, aborting");
                return false;
            }

            const QString relativeFilePath = "wallpapers/" + wallpaper;
            const QString relativeParentDirectory = relativeFilePath.left(relativeFilePath.lastIndexOf("/"));
            if (!homeDir.mkpath(relativeParentDirectory)) {
                errorReply.setErrorDescription("Could not create new wallpaper directory");
                return false;
            }

            struct open_how how = {.flags = O_CREAT | O_WRONLY | O_TRUNC,
                                   .mode = S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH,
                                   .resolve = RESOLVE_BENEATH | RESOLVE_NO_MAGICLINKS};
            int outFd = syscall(SYS_openat2, rootWallpaperFd, wallpaper.toUtf8().constData(), &how, sizeof(struct open_how));
            if (outFd < 0) {
                errorReply.setErrorDescription("Could not open wallpaper file." + QString(strerror(errno)));
                return false;
            }
            QFile file;
            if (!file.open(outFd, QIODevice::WriteOnly | QIODevice::Truncate, QFileDevice::AutoCloseHandle)) {
                errorReply.setErrorDescription("Could not open wallpaper directory from FD.");
                return false;
            }

            QDataStream out(&file);
            QDBusUnixFileDescriptor fd = args.value("_fd_" + wallpaper).value<QDBusUnixFileDescriptor>();
            if (!fd.isValid() || !isRegularFd(fd.fileDescriptor())) {
                errorReply.setErrorDescription("Could not retrieve wallpaper" + wallpaper);
                continue;
            }
            QFile wallpaperIn;
            if (!wallpaperIn.open(fd.fileDescriptor(), QIODevice::ReadOnly)) {
                errorReply.setErrorDescription("Failed to open wallpaper");
                return false;
            }
            QByteArray buf(4096, 0);
            while (true) {
                qint64 n = wallpaperIn.read(buf.data(), buf.size());
                if (n == 0) {
                    break;
                } else if (n < 0) {
                    errorReply.setErrorDescription("Failed to transfer wallpaper data for file" + relativeFilePath);
                    return false;
                } else {
                    out.writeRawData(buf.data(), n);
                }
            }
        }
        return true;
    });

    if (rc) {
        return ActionReply::SuccessReply();
    } else {
        return errorReply;
    }
}

ActionReply PlasmaLoginAuthHelper::read(const QVariantMap &args)
{
    ActionReply reply;
    QString filename = args["filename"].toString();
    QFile file(filename);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        reply = ActionReply::HelperErrorReply();
        reply.setErrorDescription(file.errorString());
        return reply;
    }
    QTextStream stream(&file);
    QString contents;
    while (!stream.atEnd()) {
        contents = stream.readAll();
    }
    file.close();
    reply.addData("contents", contents);
    return reply;
}

KAUTH_HELPER_MAIN("luisbocanegra.plasma.wallpapersync", PlasmaLoginAuthHelper)

#include "moc_plasmaloginauthhelper.cpp"
