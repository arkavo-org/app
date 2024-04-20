# Avoid multiple calls to find_package to append duplicated properties to the targets
include_guard()########### VARIABLES #######################################################################
#############################################################################################
set(jwt-cpp_FRAMEWORKS_FOUND_DEBUG "") # Will be filled later
conan_find_apple_frameworks(jwt-cpp_FRAMEWORKS_FOUND_DEBUG "${jwt-cpp_FRAMEWORKS_DEBUG}" "${jwt-cpp_FRAMEWORK_DIRS_DEBUG}")

set(jwt-cpp_LIBRARIES_TARGETS "") # Will be filled later


######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
if(NOT TARGET jwt-cpp_DEPS_TARGET)
    add_library(jwt-cpp_DEPS_TARGET INTERFACE IMPORTED)
endif()

set_property(TARGET jwt-cpp_DEPS_TARGET
             APPEND PROPERTY INTERFACE_LINK_LIBRARIES
             $<$<CONFIG:Debug>:${jwt-cpp_FRAMEWORKS_FOUND_DEBUG}>
             $<$<CONFIG:Debug>:${jwt-cpp_SYSTEM_LIBS_DEBUG}>
             $<$<CONFIG:Debug>:openssl::openssl;picojson::picojson>)

####### Find the libraries declared in cpp_info.libs, create an IMPORTED target for each one and link the
####### jwt-cpp_DEPS_TARGET to all of them
conan_package_library_targets("${jwt-cpp_LIBS_DEBUG}"    # libraries
                              "${jwt-cpp_LIB_DIRS_DEBUG}" # package_libdir
                              "${jwt-cpp_BIN_DIRS_DEBUG}" # package_bindir
                              "${jwt-cpp_LIBRARY_TYPE_DEBUG}"
                              "${jwt-cpp_IS_HOST_WINDOWS_DEBUG}"
                              jwt-cpp_DEPS_TARGET
                              jwt-cpp_LIBRARIES_TARGETS  # out_libraries_targets
                              "_DEBUG"
                              "jwt-cpp"    # package_name
                              "${jwt-cpp_NO_SONAME_MODE_DEBUG}")  # soname

# FIXME: What is the result of this for multi-config? All configs adding themselves to path?
set(CMAKE_MODULE_PATH ${jwt-cpp_BUILD_DIRS_DEBUG} ${CMAKE_MODULE_PATH})

########## GLOBAL TARGET PROPERTIES Debug ########################################
    set_property(TARGET jwt-cpp::jwt-cpp
                 APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                 $<$<CONFIG:Debug>:${jwt-cpp_OBJECTS_DEBUG}>
                 $<$<CONFIG:Debug>:${jwt-cpp_LIBRARIES_TARGETS}>
                 )

    if("${jwt-cpp_LIBS_DEBUG}" STREQUAL "")
        # If the package is not declaring any "cpp_info.libs" the package deps, system libs,
        # frameworks etc are not linked to the imported targets and we need to do it to the
        # global target
        set_property(TARGET jwt-cpp::jwt-cpp
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     jwt-cpp_DEPS_TARGET)
    endif()

    set_property(TARGET jwt-cpp::jwt-cpp
                 APPEND PROPERTY INTERFACE_LINK_OPTIONS
                 $<$<CONFIG:Debug>:${jwt-cpp_LINKER_FLAGS_DEBUG}>)
    set_property(TARGET jwt-cpp::jwt-cpp
                 APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                 $<$<CONFIG:Debug>:${jwt-cpp_INCLUDE_DIRS_DEBUG}>)
    # Necessary to find LINK shared libraries in Linux
    set_property(TARGET jwt-cpp::jwt-cpp
                 APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                 $<$<CONFIG:Debug>:${jwt-cpp_LIB_DIRS_DEBUG}>)
    set_property(TARGET jwt-cpp::jwt-cpp
                 APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                 $<$<CONFIG:Debug>:${jwt-cpp_COMPILE_DEFINITIONS_DEBUG}>)
    set_property(TARGET jwt-cpp::jwt-cpp
                 APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                 $<$<CONFIG:Debug>:${jwt-cpp_COMPILE_OPTIONS_DEBUG}>)

########## For the modules (FindXXX)
set(jwt-cpp_LIBRARIES_DEBUG jwt-cpp::jwt-cpp)
