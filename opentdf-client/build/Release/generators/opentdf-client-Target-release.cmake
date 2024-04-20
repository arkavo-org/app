# Avoid multiple calls to find_package to append duplicated properties to the targets
include_guard()########### VARIABLES #######################################################################
#############################################################################################
set(opentdf-client_FRAMEWORKS_FOUND_RELEASE "") # Will be filled later
conan_find_apple_frameworks(opentdf-client_FRAMEWORKS_FOUND_RELEASE "${opentdf-client_FRAMEWORKS_RELEASE}" "${opentdf-client_FRAMEWORK_DIRS_RELEASE}")

set(opentdf-client_LIBRARIES_TARGETS "") # Will be filled later


######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
if(NOT TARGET opentdf-client_DEPS_TARGET)
    add_library(opentdf-client_DEPS_TARGET INTERFACE IMPORTED)
endif()

set_property(TARGET opentdf-client_DEPS_TARGET
             APPEND PROPERTY INTERFACE_LINK_LIBRARIES
             $<$<CONFIG:Release>:${opentdf-client_FRAMEWORKS_FOUND_RELEASE}>
             $<$<CONFIG:Release>:${opentdf-client_SYSTEM_LIBS_RELEASE}>
             $<$<CONFIG:Release>:openssl::openssl;boost::boost;LibXml2::LibXml2;jwt-cpp::jwt-cpp;ZLIB::ZLIB>)

####### Find the libraries declared in cpp_info.libs, create an IMPORTED target for each one and link the
####### opentdf-client_DEPS_TARGET to all of them
conan_package_library_targets("${opentdf-client_LIBS_RELEASE}"    # libraries
                              "${opentdf-client_LIB_DIRS_RELEASE}" # package_libdir
                              "${opentdf-client_BIN_DIRS_RELEASE}" # package_bindir
                              "${opentdf-client_LIBRARY_TYPE_RELEASE}"
                              "${opentdf-client_IS_HOST_WINDOWS_RELEASE}"
                              opentdf-client_DEPS_TARGET
                              opentdf-client_LIBRARIES_TARGETS  # out_libraries_targets
                              "_RELEASE"
                              "opentdf-client"    # package_name
                              "${opentdf-client_NO_SONAME_MODE_RELEASE}")  # soname

# FIXME: What is the result of this for multi-config? All configs adding themselves to path?
set(CMAKE_MODULE_PATH ${opentdf-client_BUILD_DIRS_RELEASE} ${CMAKE_MODULE_PATH})

########## COMPONENTS TARGET PROPERTIES Release ########################################

    ########## COMPONENT copentdf-client::opentdf-client #############

        set(opentdf-client_copentdf-client_opentdf-client_FRAMEWORKS_FOUND_RELEASE "")
        conan_find_apple_frameworks(opentdf-client_copentdf-client_opentdf-client_FRAMEWORKS_FOUND_RELEASE "${opentdf-client_copentdf-client_opentdf-client_FRAMEWORKS_RELEASE}" "${opentdf-client_copentdf-client_opentdf-client_FRAMEWORK_DIRS_RELEASE}")

        set(opentdf-client_copentdf-client_opentdf-client_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET opentdf-client_copentdf-client_opentdf-client_DEPS_TARGET)
            add_library(opentdf-client_copentdf-client_opentdf-client_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET opentdf-client_copentdf-client_opentdf-client_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:Release>:${opentdf-client_copentdf-client_opentdf-client_FRAMEWORKS_FOUND_RELEASE}>
                     $<$<CONFIG:Release>:${opentdf-client_copentdf-client_opentdf-client_SYSTEM_LIBS_RELEASE}>
                     $<$<CONFIG:Release>:${opentdf-client_copentdf-client_opentdf-client_DEPENDENCIES_RELEASE}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'opentdf-client_copentdf-client_opentdf-client_DEPS_TARGET' to all of them
        conan_package_library_targets("${opentdf-client_copentdf-client_opentdf-client_LIBS_RELEASE}"
                              "${opentdf-client_copentdf-client_opentdf-client_LIB_DIRS_RELEASE}"
                              "${opentdf-client_copentdf-client_opentdf-client_BIN_DIRS_RELEASE}" # package_bindir
                              "${opentdf-client_copentdf-client_opentdf-client_LIBRARY_TYPE_RELEASE}"
                              "${opentdf-client_copentdf-client_opentdf-client_IS_HOST_WINDOWS_RELEASE}"
                              opentdf-client_copentdf-client_opentdf-client_DEPS_TARGET
                              opentdf-client_copentdf-client_opentdf-client_LIBRARIES_TARGETS
                              "_RELEASE"
                              "opentdf-client_copentdf-client_opentdf-client"
                              "${opentdf-client_copentdf-client_opentdf-client_NO_SONAME_MODE_RELEASE}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET copentdf-client::opentdf-client
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:Release>:${opentdf-client_copentdf-client_opentdf-client_OBJECTS_RELEASE}>
                     $<$<CONFIG:Release>:${opentdf-client_copentdf-client_opentdf-client_LIBRARIES_TARGETS}>
                     )

        if("${opentdf-client_copentdf-client_opentdf-client_LIBS_RELEASE}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET copentdf-client::opentdf-client
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         opentdf-client_copentdf-client_opentdf-client_DEPS_TARGET)
        endif()

        set_property(TARGET copentdf-client::opentdf-client APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:Release>:${opentdf-client_copentdf-client_opentdf-client_LINKER_FLAGS_RELEASE}>)
        set_property(TARGET copentdf-client::opentdf-client APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:Release>:${opentdf-client_copentdf-client_opentdf-client_INCLUDE_DIRS_RELEASE}>)
        set_property(TARGET copentdf-client::opentdf-client APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:Release>:${opentdf-client_copentdf-client_opentdf-client_LIB_DIRS_RELEASE}>)
        set_property(TARGET copentdf-client::opentdf-client APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:Release>:${opentdf-client_copentdf-client_opentdf-client_COMPILE_DEFINITIONS_RELEASE}>)
        set_property(TARGET copentdf-client::opentdf-client APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:Release>:${opentdf-client_copentdf-client_opentdf-client_COMPILE_OPTIONS_RELEASE}>)

    ########## AGGREGATED GLOBAL TARGET WITH THE COMPONENTS #####################
    set_property(TARGET opentdf-client::opentdf-client APPEND PROPERTY INTERFACE_LINK_LIBRARIES copentdf-client::opentdf-client)

########## For the modules (FindXXX)
set(opentdf-client_LIBRARIES_RELEASE opentdf-client::opentdf-client)
