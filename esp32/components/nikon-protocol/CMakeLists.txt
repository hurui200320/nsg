idf_component_register(SRCS PairingMessage.cpp TimeMessage.cpp GeoMessage.cpp
                           BlowfishHasher.cpp NikonPairingEngine.cpp
                       INCLUDE_DIRS "."
                       REQUIRES blowfish random)