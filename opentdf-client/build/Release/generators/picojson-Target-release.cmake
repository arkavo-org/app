# Avoid multiple calls to find_package to append duplicated properties to the targets
include_guard()########### VARIABLES #######################################################################
#############################################################################################
set(picojson_FRAMEWORKS_FOUND_RELEASE "") # Will be filled later
conan_find_apple_frameworks(picojson_FRAMEWORKS_FOUND_RELEASE "${picojson_FRAMEWORKS_RELEASE}" "${picojson_FRAMEWORK_DIRS_RELEASE}")

set(picojson_LIBRARIES_TARGETS "") # Will be filled later


######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
if(NOT TARGET picojson_DEPS_TARGET)
    add_library(picojson_DEPS_TARGET INTERFACE IMPORTED)
endif()

set_property(TARGET picojson_DEPS_TARGET
             APPEND PROPERTY INTERFACE_LINK_LIBRARIES
             $<$<CONFIG:Release>:${picojson_FRAMEWORKS_FOUND_RELEASE}>
             $<$<CONFIG:Release>:${picojson_SYSTEM_LIBS_RELEASE}>
             $<$<CONFIG:Release>:>)

####### Find the libraries declared in cpp_info.libs, create an IMPORTED target for each one and link the
####### picojson_DEPS_TARGET to all of them
conan_package_library_targets("${picojson_LIBS_RELEASE}"    # libraries
                              "${picojson_LIB_DIRS_RELEASE}" # package_libdir
                              "${picojson_BIN_DIRS_RELEASE}" # package_bindir
                              "${picojson_LIBRARY_TYPE_RELEASE}"
                              "${picojson_IS_HOST_WINDOWS_RELEASE}"
                              picojson_DEPS_TARGET
                              picojson_LIBRARIES_TARGETS  # out_libraries_targets
                              "_RELEASE"
                              "picojson"    # package_name
                              "${picojson_NO_SONAME_MODE_RELEASE}")  # soname

# FIXME: What is the result of this for multi-config? All configs adding themselves to path?
set(CMAKE_MODULE_PATH ${picojson_BUILD_DIRS_RELEASE} ${CMAKE_MODULE_PATH})

########## GLOBAL TARGET PROPERTIES Release ########################################
    set_property(TARGET picojson::picojson
                 APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                 $<$<CONFIG:Release>:${picojson_OBJECTS_RELEASE}>
                 $<$<CONFIG:Release>:${picojson_LIBRARIES_TARGETS}>
                 )

    if("${picojson_LIBS_RELEASE}" STREQUAL "")
        # If the package is not declaring any "cpp_info.libs" the package deps, system libs,
        # frameworks etc are not linked to the imported targets and we need to do it to the
        # global target
        set_property(TARGET picojson::picojson
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     picojson_DEPS_TARGET)
    endif()

    set_property(TARGET picojson::picojson
                 APPEND PROPERTY INTERFACE_LINK_OPTIONS
                 $<$<CONFIG:Release>:${picojson_LINKER_FLAGS_RELEASE}>)
    set_property(TARGET picojson::picojson
                 APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                 $<$<CONFIG:Release>:${picojson_INCLUDE_DIRS_RELEASE}>)
    # Necessary to find LINK shared libraries in Linux
    set_property(TARGET picojson::picojson
                 APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                 $<$<CONFIG:Release>:${picojson_LIB_DIRS_RELEASE}>)
    set_property(TARGET picojson::picojson
                 APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                 $<$<CONFIG:Release>:${picojson_COMPILE_DEFINITIONS_RELEASE}>)
    set_property(TARGET picojson::picojson
                 APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                 $<$<CONFIG:Release>:${picojson_COMPILE_OPTIONS_RELEASE}>)

########## For the modules (FindXXX)
set(picojson_LIBRARIES_RELEASE picojson::picojson)
