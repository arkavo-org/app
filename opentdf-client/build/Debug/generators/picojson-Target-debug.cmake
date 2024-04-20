# Avoid multiple calls to find_package to append duplicated properties to the targets
include_guard()########### VARIABLES #######################################################################
#############################################################################################
set(picojson_FRAMEWORKS_FOUND_DEBUG "") # Will be filled later
conan_find_apple_frameworks(picojson_FRAMEWORKS_FOUND_DEBUG "${picojson_FRAMEWORKS_DEBUG}" "${picojson_FRAMEWORK_DIRS_DEBUG}")

set(picojson_LIBRARIES_TARGETS "") # Will be filled later


######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
if(NOT TARGET picojson_DEPS_TARGET)
    add_library(picojson_DEPS_TARGET INTERFACE IMPORTED)
endif()

set_property(TARGET picojson_DEPS_TARGET
             APPEND PROPERTY INTERFACE_LINK_LIBRARIES
             $<$<CONFIG:Debug>:${picojson_FRAMEWORKS_FOUND_DEBUG}>
             $<$<CONFIG:Debug>:${picojson_SYSTEM_LIBS_DEBUG}>
             $<$<CONFIG:Debug>:>)

####### Find the libraries declared in cpp_info.libs, create an IMPORTED target for each one and link the
####### picojson_DEPS_TARGET to all of them
conan_package_library_targets("${picojson_LIBS_DEBUG}"    # libraries
                              "${picojson_LIB_DIRS_DEBUG}" # package_libdir
                              "${picojson_BIN_DIRS_DEBUG}" # package_bindir
                              "${picojson_LIBRARY_TYPE_DEBUG}"
                              "${picojson_IS_HOST_WINDOWS_DEBUG}"
                              picojson_DEPS_TARGET
                              picojson_LIBRARIES_TARGETS  # out_libraries_targets
                              "_DEBUG"
                              "picojson"    # package_name
                              "${picojson_NO_SONAME_MODE_DEBUG}")  # soname

# FIXME: What is the result of this for multi-config? All configs adding themselves to path?
set(CMAKE_MODULE_PATH ${picojson_BUILD_DIRS_DEBUG} ${CMAKE_MODULE_PATH})

########## GLOBAL TARGET PROPERTIES Debug ########################################
    set_property(TARGET picojson::picojson
                 APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                 $<$<CONFIG:Debug>:${picojson_OBJECTS_DEBUG}>
                 $<$<CONFIG:Debug>:${picojson_LIBRARIES_TARGETS}>
                 )

    if("${picojson_LIBS_DEBUG}" STREQUAL "")
        # If the package is not declaring any "cpp_info.libs" the package deps, system libs,
        # frameworks etc are not linked to the imported targets and we need to do it to the
        # global target
        set_property(TARGET picojson::picojson
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     picojson_DEPS_TARGET)
    endif()

    set_property(TARGET picojson::picojson
                 APPEND PROPERTY INTERFACE_LINK_OPTIONS
                 $<$<CONFIG:Debug>:${picojson_LINKER_FLAGS_DEBUG}>)
    set_property(TARGET picojson::picojson
                 APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                 $<$<CONFIG:Debug>:${picojson_INCLUDE_DIRS_DEBUG}>)
    # Necessary to find LINK shared libraries in Linux
    set_property(TARGET picojson::picojson
                 APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                 $<$<CONFIG:Debug>:${picojson_LIB_DIRS_DEBUG}>)
    set_property(TARGET picojson::picojson
                 APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                 $<$<CONFIG:Debug>:${picojson_COMPILE_DEFINITIONS_DEBUG}>)
    set_property(TARGET picojson::picojson
                 APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                 $<$<CONFIG:Debug>:${picojson_COMPILE_OPTIONS_DEBUG}>)

########## For the modules (FindXXX)
set(picojson_LIBRARIES_DEBUG picojson::picojson)
