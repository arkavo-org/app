########## MACROS ###########################################################################
#############################################################################################

# Requires CMake > 3.15
if(${CMAKE_VERSION} VERSION_LESS "3.15")
    message(FATAL_ERROR "The 'CMakeDeps' generator only works with CMake >= 3.15")
endif()

if(LibXml2_FIND_QUIETLY)
    set(LibXml2_MESSAGE_MODE VERBOSE)
else()
    set(LibXml2_MESSAGE_MODE STATUS)
endif()

include(${CMAKE_CURRENT_LIST_DIR}/cmakedeps_macros.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/module-LibXml2Targets.cmake)
include(CMakeFindDependencyMacro)

check_build_type_defined()

foreach(_DEPENDENCY ${libxml2_FIND_DEPENDENCY_NAMES} )
    # Check that we have not already called a find_package with the transitive dependency
    if(NOT ${_DEPENDENCY}_FOUND)
        find_dependency(${_DEPENDENCY} REQUIRED ${${_DEPENDENCY}_FIND_MODE})
    endif()
endforeach()

set(LibXml2_VERSION_STRING "2.11.6")
set(LibXml2_INCLUDE_DIRS ${libxml2_INCLUDE_DIRS_RELEASE} )
set(LibXml2_INCLUDE_DIR ${libxml2_INCLUDE_DIRS_RELEASE} )
set(LibXml2_LIBRARIES ${libxml2_LIBRARIES_RELEASE} )
set(LibXml2_DEFINITIONS ${libxml2_DEFINITIONS_RELEASE} )

# Only the first installed configuration is included to avoid the collision
foreach(_BUILD_MODULE ${libxml2_BUILD_MODULES_PATHS_RELEASE} )
    message(${LibXml2_MESSAGE_MODE} "Conan: Including build module from '${_BUILD_MODULE}'")
    include(${_BUILD_MODULE})
endforeach()


include(FindPackageHandleStandardArgs)
set(LibXml2_FOUND 1)
set(LibXml2_VERSION "2.11.6")

find_package_handle_standard_args(LibXml2
                                  REQUIRED_VARS LibXml2_VERSION
                                  VERSION_VAR LibXml2_VERSION)
mark_as_advanced(LibXml2_FOUND LibXml2_VERSION)
