########## MACROS ###########################################################################
#############################################################################################

# Requires CMake > 3.15
if(${CMAKE_VERSION} VERSION_LESS "3.15")
    message(FATAL_ERROR "The 'CMakeDeps' generator only works with CMake >= 3.15")
endif()

if(picojson_FIND_QUIETLY)
    set(picojson_MESSAGE_MODE VERBOSE)
else()
    set(picojson_MESSAGE_MODE STATUS)
endif()

include(${CMAKE_CURRENT_LIST_DIR}/cmakedeps_macros.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/picojsonTargets.cmake)
include(CMakeFindDependencyMacro)

check_build_type_defined()

foreach(_DEPENDENCY ${picojson_FIND_DEPENDENCY_NAMES} )
    # Check that we have not already called a find_package with the transitive dependency
    if(NOT ${_DEPENDENCY}_FOUND)
        find_dependency(${_DEPENDENCY} REQUIRED ${${_DEPENDENCY}_FIND_MODE})
    endif()
endforeach()

set(picojson_VERSION_STRING "1.3.0")
set(picojson_INCLUDE_DIRS ${picojson_INCLUDE_DIRS_DEBUG} )
set(picojson_INCLUDE_DIR ${picojson_INCLUDE_DIRS_DEBUG} )
set(picojson_LIBRARIES ${picojson_LIBRARIES_DEBUG} )
set(picojson_DEFINITIONS ${picojson_DEFINITIONS_DEBUG} )

# Only the first installed configuration is included to avoid the collision
foreach(_BUILD_MODULE ${picojson_BUILD_MODULES_PATHS_DEBUG} )
    message(${picojson_MESSAGE_MODE} "Conan: Including build module from '${_BUILD_MODULE}'")
    include(${_BUILD_MODULE})
endforeach()


