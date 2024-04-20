# Avoid multiple calls to find_package to append duplicated properties to the targets
include_guard()########### VARIABLES #######################################################################
#############################################################################################
set(jwt-cpp_FRAMEWORKS_FOUND_RELEASE "") # Will be filled later
conan_find_apple_frameworks(jwt-cpp_FRAMEWORKS_FOUND_RELEASE "${jwt-cpp_FRAMEWORKS_RELEASE}" "${jwt-cpp_FRAMEWORK_DIRS_RELEASE}")

set(jwt-cpp_LIBRARIES_TARGETS "") # Will be filled later


######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
if(NOT TARGET jwt-cpp_DEPS_TARGET)
    add_library(jwt-cpp_DEPS_TARGET INTERFACE IMPORTED)
endif()

set_property(TARGET jwt-cpp_DEPS_TARGET
             APPEND PROPERTY INTERFACE_LINK_LIBRARIES
             $<$<CONFIG:Release>:${jwt-cpp_FRAMEWORKS_FOUND_RELEASE}>
             $<$<CONFIG:Release>:${jwt-cpp_SYSTEM_LIBS_RELEASE}>
             $<$<CONFIG:Release>:openssl::openssl;picojson::picojson>)

####### Find the libraries declared in cpp_info.libs, create an IMPORTED target for each one and link the
####### jwt-cpp_DEPS_TARGET to all of them
conan_package_library_targets("${jwt-cpp_LIBS_RELEASE}"    # libraries
                              "${jwt-cpp_LIB_DIRS_RELEASE}" # package_libdir
                              "${jwt-cpp_BIN_DIRS_RELEASE}" # package_bindir
                              "${jwt-cpp_LIBRARY_TYPE_RELEASE}"
                              "${jwt-cpp_IS_HOST_WINDOWS_RELEASE}"
                              jwt-cpp_DEPS_TARGET
                              jwt-cpp_LIBRARIES_TARGETS  # out_libraries_targets
                              "_RELEASE"
                              "jwt-cpp"    # package_name
                              "${jwt-cpp_NO_SONAME_MODE_RELEASE}")  # soname

# FIXME: What is the result of this for multi-config? All configs adding themselves to path?
set(CMAKE_MODULE_PATH ${jwt-cpp_BUILD_DIRS_RELEASE} ${CMAKE_MODULE_PATH})

########## GLOBAL TARGET PROPERTIES Release ########################################
    set_property(TARGET jwt-cpp::jwt-cpp
                 APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                 $<$<CONFIG:Release>:${jwt-cpp_OBJECTS_RELEASE}>
                 $<$<CONFIG:Release>:${jwt-cpp_LIBRARIES_TARGETS}>
                 )

    if("${jwt-cpp_LIBS_RELEASE}" STREQUAL "")
        # If the package is not declaring any "cpp_info.libs" the package deps, system libs,
        # frameworks etc are not linked to the imported targets and we need to do it to the
        # global target
        set_property(TARGET jwt-cpp::jwt-cpp
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     jwt-cpp_DEPS_TARGET)
    endif()

    set_property(TARGET jwt-cpp::jwt-cpp
                 APPEND PROPERTY INTERFACE_LINK_OPTIONS
                 $<$<CONFIG:Release>:${jwt-cpp_LINKER_FLAGS_RELEASE}>)
    set_property(TARGET jwt-cpp::jwt-cpp
                 APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                 $<$<CONFIG:Release>:${jwt-cpp_INCLUDE_DIRS_RELEASE}>)
    # Necessary to find LINK shared libraries in Linux
    set_property(TARGET jwt-cpp::jwt-cpp
                 APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                 $<$<CONFIG:Release>:${jwt-cpp_LIB_DIRS_RELEASE}>)
    set_property(TARGET jwt-cpp::jwt-cpp
                 APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                 $<$<CONFIG:Release>:${jwt-cpp_COMPILE_DEFINITIONS_RELEASE}>)
    set_property(TARGET jwt-cpp::jwt-cpp
                 APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                 $<$<CONFIG:Release>:${jwt-cpp_COMPILE_OPTIONS_RELEASE}>)

########## For the modules (FindXXX)
set(jwt-cpp_LIBRARIES_RELEASE jwt-cpp::jwt-cpp)
