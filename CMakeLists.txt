cmake_minimum_required(VERSION 3.22)
project("plasma-current-wallpaper")
option(INSTALL_PLASMOID "Install plasmoid" ON)
option(PACKAGE_PLASMOID "Package plasmoid" OFF)
option(BUILD_HELPER "Build the login screen wallpaper helper" ON)

set(PROJECT_DEP_VERSION "6.0.0")
set(QT_MIN_VERSION "6.6.0")
set(KF6_MIN_VERSION "6.0.0")
set(KDE_COMPILERSETTINGS_LEVEL "5.82")

find_package(ECM ${KF6_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH} ${CMAKE_CURRENT_SOURCE_DIR}/cmake/modules)
set(CMAKE_EXPORT_COMPILE_COMMANDS 1)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_AUTOMOC ON)
include(KDEInstallDirs)
include(KDECMakeSettings)
# Get id and version from metadata
file(READ ${CMAKE_CURRENT_SOURCE_DIR}/package/metadata.json METADATA)
string(JSON PLUGIN_ID GET ${METADATA} KPlugin Id)
string(JSON CUR_VERSION GET ${METADATA} KPlugin Version)
message("Plugin Id: ${PLUGIN_ID}")
message("Version: ${CUR_VERSION}")

if(INSTALL_PLASMOID)
    find_package(Plasma5Support ${PROJECT_DEP_VERSION} REQUIRED)
    find_package(Plasma ${PROJECT_DEP_VERSION} REQUIRED)
    plasma_install_package(package ${PLUGIN_ID})
endif()

if(BUILD_HELPER)
    add_subdirectory(helper)
endif()

if(PACKAGE_PLASMOID)
    set(PLASMOID_FILE "${CMAKE_CURRENT_SOURCE_DIR}/${PROJECT_NAME}-v${CUR_VERSION}.plasmoid")
    add_custom_target(plasmoid ALL
        COMMAND rm -rf "${PLASMOID_FILE}"
        COMMAND ${CMAKE_COMMAND} -E chdir ${CMAKE_CURRENT_SOURCE_DIR}/package zip -r ${PLASMOID_FILE} ./
        COMMENT "Generating ${PLASMOID_FILE}"
    )
endif()
