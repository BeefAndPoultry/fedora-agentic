cmake_minimum_required(VERSION 3.22)

project(ksystemstats_plugin_llamacpp
    VERSION 1.0.0
    DESCRIPTION "ksystemstats plugin for a router-mode llama-server"
    LANGUAGES CXX)

# ---- Standard C++20 setup ---------------------------------------------------
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# KPluginFactory discovers the Q_OBJECT/PLUGIN factory via the generated moc.
set(CMAKE_AUTOMOC ON)

# ---- KDE / ECM modules ------------------------------------------------------
find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${ECM_MODULE_PATH} ${ECM_PREFIX}/share/ECM/modules)

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

# ---- Dependencies -----------------------------------------------------------
find_package(Qt6 REQUIRED COMPONENTS Core Network)
find_package(KF6 REQUIRED COMPONENTS CoreAddons I18n)
find_package(KSysGuard REQUIRED)

# ---- Plugin -----------------------------------------------------------------
kcoreaddons_add_plugin(ksystemstats_plugin_llamacpp
    SOURCES
        llama_plugin.cpp
        llama_plugin.h
    INSTALL_NAMESPACE "ksystemstats"
)

# metadata.json must ship next to the compiled .so so KPluginFactory can open it
# at runtime. The kcoreaddons plugin macro installs the .so under
# <libdir>/qt6/plugins/ksystemstats, so copy the JSON to the same destination.
set(LLMACPP_PLUGIN_DESTINATION "${KDE_INSTALL_LIBDIR}/qt6/plugins/ksystemstats")

target_link_libraries(ksystemstats_plugin_llamacpp
    PRIVATE
        Qt6::Core
        Qt6::Network
        KF6::CoreAddons
        KF6::I18n
        KSysGuard::SystemStats)

include(GNUInstallDirs)
install(EXPORT ksystemstats_plugin_llamacpp DESTINATION "${KDE_INSTALL_CMAKEPACKAGEDIR}")

install(FILES metadata.json
    DESTINATION "${LLMACPP_PLUGIN_DESTINATION}")

# ---- Convenience -------------------------------------------------------------
if(CMAKE_BUILD_TYPE STREQUAL "")
    set(CMAKE_BUILD_TYPE Release)
endif()
