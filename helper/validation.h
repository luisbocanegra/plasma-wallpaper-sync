/*
    SPDX-FileCopyrightText: 2026 Luis Bocanegra <luisbocanegra17b@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
 */

#pragma once

#include <QJsonDocument>
#include <QJsonObject>
#include <QMap>
#include <QRegularExpression>
#include <QString>
#include <QStringList>

static const QStringList allowedPlugins = {
    QStringLiteral("org.kde.color"),
    QStringLiteral("org.kde.image"),
    QStringLiteral("org.kde.tiled"),
    QStringLiteral("org.kde.haenau"),
    QStringLiteral("org.kde.potd"),
    QStringLiteral("org.kde.hunyango"),
    // slideshow is not included as we apply the image via org.kde.image
};

static inline bool isSafeName(const QString &s)
{
    static const QRegularExpression re(QStringLiteral("^[A-Za-z0-9._-]+$"));
    return re.match(s).hasMatch();
}

static inline bool parseWallpaperConfig(const QString &plugin,
                                        const QString &configJson,
                                        QMap<QString, QString> &values,
                                        QString &error, const bool isLoginScreen = false)
{
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(configJson.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        error = QStringLiteral("invalid JSON: ") + parseError.errorString();
        return false;
    }
    if (isLoginScreen && !allowedPlugins.contains(plugin)) {
        error = QStringLiteral("unsupported plugin: ") + plugin;
        return false;
    }

    const QJsonObject config = doc.object();
    for (auto it = config.begin(); it != config.end(); ++it) {
        if (!isSafeName(it.key())) {
            error = QStringLiteral("invalid key: ") + it.key();
            return false;
        }

        values.insert(it.key(), it.value().toVariant().toString());
    }
    return true;
}
