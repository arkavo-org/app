########## MACROS ###########################################################################
#############################################################################################

# Requires CMake > 3.15
if(${CMAKE_VERSION} VERSION_LESS "3.15")
    message(FATAL_ERROR "The 'CMakeDeps' generator only works with CMake >= 3.15")
endif()

if(opentdf-client_FIND_QUIETLY)
    set(opentdf-client_MESSAGE_MODE VERBOSE)
else()
    set(opentdf-client_MESSAGE_MODE STATUS)
endif()

include(${CMAKE_CURRENT_LIST_DIR}/cmakedeps_macros.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/opentdf-clientTargets.cmake)
include(CMakeFindDependencyMacro)

check_build_type_defined()

foreach(_DEPENDENCY ${opentdf-client_FIND_DEPENDENCY_NAMES} )
    # Check that we have not already called a find_package with the transitive dependency
    if(NOT ${_DEPENDENCY}_FOUND)
        find_dependency(${_DEPENDENCY} REQUIRED ${${_DEPENDENCY}_FIND_MODE})
    endif()
endforeach()

set(opentdf-client_VERSION_STRING "1.5.6")
set(opentdf-client_INCLUDE_DIRS ${opentdf-client_INCLUDE_DIRS_DEBUG} )
set(opentdf-client_INCLUDE_DIR ${opentdf-client_INCLUDE_DIRS_DEBUG} )
set(opentdf-client_LIBRARIES ${opentdf-client_LIBRARIES_DEBUG} )
set(opentdf-client_DEFINITIONS ${opentdf-client_DEFINITIONS_DEBUG} )

# Only the first installed configuration is included to avoid the collision
foreach(_BUILD_MODULE ${opentdf-client_BUILD_MODULES_PATHS_DEBUG} )
    message(${opentdf-client_MESSAGE_MODE} "Conan: Including build module from '${_BUILD_MODULE}'")
    include(${_BUILD_MODULE})
endforeach()


