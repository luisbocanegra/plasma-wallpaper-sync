find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core DBus)
find_package(KF6Config ${KF6_MIN_VERSION} REQUIRED)
find_package(KF6 ${KF6_MIN_VERSION} REQUIRED COMPONENTS Auth CoreAddons I18n Package)

set(PLASMALOGIN_CONFIG_FILE "${CMAKE_INSTALL_FULL_SYSCONFDIR}/plasmalogin.conf" CACHE PATH "Path of the plasma-login config file")

configure_file(config.h.in config.h IMMEDIATE @ONLY)

add_library(settings STATIC
    config.h
)

set_property(TARGET settings PROPERTY POSITION_INDEPENDENT_CODE ON)

target_link_libraries(settings)

add_executable(plasma-wallpaper-sync-helper main.cpp)
target_link_libraries(plasma-wallpaper-sync-helper
    Qt6::Core
    Qt6::DBus
    KF6::ConfigCore
    KF6::AuthCore
)
install(TARGETS plasma-wallpaper-sync-helper DESTINATION ${KDE_INSTALL_BINDIR})

add_executable(wallpapersync_kauthhelper plasmaloginauthhelper.cpp plasmaloginauthhelper.h)
target_link_libraries(wallpapersync_kauthhelper
    settings
    Qt6::Core
    Qt6::DBus
    KF6::ConfigCore
    KF6::AuthCore
    KF6::I18n
)
install(TARGETS wallpapersync_kauthhelper DESTINATION ${KAUTH_HELPER_INSTALL_DIR})
kauth_install_helper_files(wallpapersync_kauthhelper luisbocanegra.plasma.wallpapersync root)
kauth_install_actions(luisbocanegra.plasma.wallpapersync luisbocanegra.plasma.wallpapersync.actions)
