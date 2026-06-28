idf_component_register(SRCS main.cpp BootMode.cpp Config.cpp Logging.cpp
                           common/NikonBLEClient.cpp
                           normal/ConnectedCamera.cpp normal/PairedScanner.cpp normal/NormalMode.cpp
                           pairing/ClassicBT.cpp pairing/PairingScanner.cpp pairing/PairingMode.cpp
                       INCLUDE_DIRS "." "common" "normal" "pairing"
                       REQUIRES arduino-esp32 nikon-protocol utils random blowfish)

target_compile_definitions(${COMPONENT_LIB} PRIVATE UNITY_SUPPORT_64=1)

if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    target_compile_definitions(${COMPONENT_LIB} PRIVATE NSG_LOG_LEVEL=0)
else()
    target_compile_definitions(${COMPONENT_LIB} PRIVATE NSG_LOG_LEVEL=1)
endif()