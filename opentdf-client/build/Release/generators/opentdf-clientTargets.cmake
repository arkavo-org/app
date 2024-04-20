# Load the debug and release variables
file(GLOB DATA_FILES "${CMAKE_CURRENT_LIST_DIR}/opentdf-client-*-data.cmake")

foreach(f ${DATA_FILES})
    include(${f})
endforeach()

# Create the targets for all the components
foreach(_COMPONENT ${opentdf-client_COMPONENT_NAMES} )
    if(NOT TARGET ${_COMPONENT})
        add_library(${_COMPONENT} INTERFACE IMPORTED)
        message(${opentdf-client_MESSAGE_MODE} "Conan: Component target declared '${_COMPONENT}'")
    endif()
endforeach()

if(NOT TARGET opentdf-client::opentdf-client)
    add_library(opentdf-client::opentdf-client INTERFACE IMPORTED)
    message(${opentdf-client_MESSAGE_MODE} "Conan: Target declared 'opentdf-client::opentdf-client'")
endif()
# Load the debug and release library finders
file(GLOB CONFIG_FILES "${CMAKE_CURRENT_LIST_DIR}/opentdf-client-Target-*.cmake")

foreach(f ${CONFIG_FILES})
    include(${f})
endforeach()