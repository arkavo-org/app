# Avoid multiple calls to find_package to append duplicated properties to the targets
include_guard()########### VARIABLES #######################################################################
#############################################################################################
set(opentdf-client_FRAMEWORKS_FOUND_DEBUG "") # Will be filled later
conan_find_apple_frameworks(opentdf-client_FRAMEWORKS_FOUND_DEBUG "${opentdf-client_FRAMEWORKS_DEBUG}" "${opentdf-client_FRAMEWORK_DIRS_DEBUG}")

set(opentdf-client_LIBRARIES_TARGETS "") # Will be filled later


######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
if(NOT TARGET opentdf-client_DEPS_TARGET)
    add_library(opentdf-client_DEPS_TARGET INTERFACE IMPORTED)
endif()

set_property(TARGET opentdf-client_DEPS_TARGET
             APPEND PROPERTY INTERFACE_LINK_LIBRARIES
             $<$<CONFIG:Debug>:${opentdf-client_FRAMEWORKS_FOUND_DEBUG}>
             $<$<CONFIG:Debug>:${opentdf-client_SYSTEM_LIBS_DEBUG}>
             $<$<CONFIG:Debug>:openssl::openssl;boost::boost;LibXml2::LibXml2;jwt-cpp::jwt-cpp;ZLIB::ZLIB>)

####### Find the libraries declared in cpp_info.libs, create an IMPORTED target for each one and link the
####### opentdf-client_DEPS_TARGET to all of them
conan_package_library_targets("${opentdf-client_LIBS_DEBUG}"    # libraries
                              "${opentdf-client_LIB_DIRS_DEBUG}" # package_libdir
                              "${opentdf-client_BIN_DIRS_DEBUG}" # package_bindir
                              "${opentdf-client_LIBRARY_TYPE_DEBUG}"
                              "${opentdf-client_IS_HOST_WINDOWS_DEBUG}"
                              opentdf-client_DEPS_TARGET
                              opentdf-client_LIBRARIES_TARGETS  # out_libraries_targets
                              "_DEBUG"
                              "opentdf-client"    # package_name
                              "${opentdf-client_NO_SONAME_MODE_DEBUG}")  # soname

# FIXME: What is the result of this for multi-config? All configs adding themselves to path?
set(CMAKE_MODULE_PATH ${opentdf-client_BUILD_DIRS_DEBUG} ${CMAKE_MODULE_PATH})

########## COMPONENTS TARGET PROPERTIES Debug ########################################

    ########## COMPONENT copentdf-client::opentdf-client #############

        set(opentdf-client_copentdf-client_opentdf-client_FRAMEWORKS_FOUND_DEBUG "")
        conan_find_apple_frameworks(opentdf-client_copentdf-client_opentdf-client_FRAMEWORKS_FOUND_DEBUG "${opentdf-client_copentdf-client_opentdf-client_FRAMEWORKS_DEBUG}" "${opentdf-client_copentdf-client_opentdf-client_FRAMEWORK_DIRS_DEBUG}")

        set(opentdf-client_copentdf-client_opentdf-client_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET opentdf-client_copentdf-client_opentdf-client_DEPS_TARGET)
            add_library(opentdf-client_copentdf-client_opentdf-client_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET opentdf-client_copentdf-client_opentdf-client_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:Debug>:${opentdf-client_copentdf-client_opentdf-client_FRAMEWORKS_FOUND_DEBUG}>
                     $<$<CONFIG:Debug>:${opentdf-client_copentdf-client_opentdf-client_SYSTEM_LIBS_DEBUG}>
                     $<$<CONFIG:Debug>:${opentdf-client_copentdf-client_opentdf-client_DEPENDENCIES_DEBUG}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'opentdf-client_copentdf-client_opentdf-client_DEPS_TARGET' to all of them
        conan_package_library_targets("${opentdf-client_copentdf-client_opentdf-client_LIBS_DEBUG}"
                              "${opentdf-client_copentdf-client_opentdf-client_LIB_DIRS_DEBUG}"
                              "${opentdf-client_copentdf-client_opentdf-client_BIN_DIRS_DEBUG}" # package_bindir
                              "${opentdf-client_copentdf-client_opentdf-client_LIBRARY_TYPE_DEBUG}"
                              "${opentdf-client_copentdf-client_opentdf-client_IS_HOST_WINDOWS_DEBUG}"
                              opentdf-client_copentdf-client_opentdf-client_DEPS_TARGET
                              opentdf-client_copentdf-client_opentdf-client_LIBRARIES_TARGETS
                              "_DEBUG"
                              "opentdf-client_copentdf-client_opentdf-client"
                              "${opentdf-client_copentdf-client_opentdf-client_NO_SONAME_MODE_DEBUG}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET copentdf-client::opentdf-client
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:Debug>:${opentdf-client_copentdf-client_opentdf-client_OBJECTS_DEBUG}>
                     $<$<CONFIG:Debug>:${opentdf-client_copentdf-client_opentdf-client_LIBRARIES_TARGETS}>
                     )

        if("${opentdf-client_copentdf-client_opentdf-client_LIBS_DEBUG}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET copentdf-client::opentdf-client
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         opentdf-client_copentdf-client_opentdf-client_DEPS_TARGET)
        endif()

        set_property(TARGET copentdf-client::opentdf-client APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:Debug>:${opentdf-client_copentdf-client_opentdf-client_LINKER_FLAGS_DEBUG}>)
        set_property(TARGET copentdf-client::opentdf-client APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:Debug>:${opentdf-client_copentdf-client_opentdf-client_INCLUDE_DIRS_DEBUG}>)
        set_property(TARGET copentdf-client::opentdf-client APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:Debug>:${opentdf-client_copentdf-client_opentdf-client_LIB_DIRS_DEBUG}>)
        set_property(TARGET copentdf-client::opentdf-client APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:Debug>:${opentdf-client_copentdf-client_opentdf-client_COMPILE_DEFINITIONS_DEBUG}>)
        set_property(TARGET copentdf-client::opentdf-client APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:Debug>:${opentdf-client_copentdf-client_opentdf-client_COMPILE_OPTIONS_DEBUG}>)

    ########## AGGREGATED GLOBAL TARGET WITH THE COMPONENTS #####################
    set_property(TARGET opentdf-client::opentdf-client APPEND PROPERTY INTERFACE_LINK_LIBRARIES copentdf-client::opentdf-client)

########## For the modules (FindXXX)
set(opentdf-client_LIBRARIES_DEBUG opentdf-client::opentdf-client)
