# Load the debug and release variables
file(GLOB DATA_FILES "${CMAKE_CURRENT_LIST_DIR}/picojson-*-data.cmake")

foreach(f ${DATA_FILES})
    include(${f})
endforeach()

# Create the targets for all the components
foreach(_COMPONENT ${picojson_COMPONENT_NAMES} )
    if(NOT TARGET ${_COMPONENT})
        add_library(${_COMPONENT} INTERFACE IMPORTED)
        message(${picojson_MESSAGE_MODE} "Conan: Component target declared '${_COMPONENT}'")
    endif()
endforeach()

if(NOT TARGET picojson::picojson)
    add_library(picojson::picojson INTERFACE IMPORTED)
    message(${picojson_MESSAGE_MODE} "Conan: Target declared 'picojson::picojson'")
endif()
# Load the debug and release library finders
file(GLOB CONFIG_FILES "${CMAKE_CURRENT_LIST_DIR}/picojson-Target-*.cmake")

foreach(f ${CONFIG_FILES})
    include(${f})
endforeach()