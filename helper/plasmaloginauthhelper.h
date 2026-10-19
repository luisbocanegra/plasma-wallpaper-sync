/*
    SPDX-FileCopyrightText: 2019 Filip Fila <filipfila.kde@gmail.com>
    SPDX-FileCopyrightText: 2013 Reza Fatahilah Shah <rshah0385@kireihana.com>
    SPDX-FileCopyrightText: 2026 Luis Bocanegra <luisbocanegra17b@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
 */

#pragma once

#include <KAuth/ActionReply>
#include <KAuth/HelperSupport>
#include <KUser>
#include <QObject>
#include <unistd.h>

/*
 * Return the plasmalogin user path
 */
static inline std::optional<QString> plasmaloginUserHomeDir()
{
    // we have to check with QString and isEmpty() instead of QDir and exists()
    // because QDir returns "." and true for exists() in the case of a
    // non-existent user
    const QString plasmaloginHomeDirPath = KUser("plasmalogin").homeDir();
    if (plasmaloginHomeDirPath.isEmpty()) {
        return std::nullopt;
    } else {
        return plasmaloginHomeDirPath;
    }
}

using namespace KAuth;

class PlasmaLoginAuthHelper : public QObject
{
    Q_OBJECT

public Q_SLOTS:

    /*
     * Update the PLASMALOGIN_CONFIG_FILE with the user's specified settings
     */
    ActionReply save(const QVariantMap &args);

    /*
     * Read the PLASMALOGIN_CONFIG_FILE
     */
    ActionReply read(const QVariantMap &args);

private:
    bool adjustPermissionsFromPlasma6_6();
};
