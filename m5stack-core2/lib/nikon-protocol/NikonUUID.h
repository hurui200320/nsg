#ifndef NIKON_UUID_H
#define NIKON_UUID_H

namespace NikonUUID {
    /**
     * The main service id.
     */
    constexpr char SERVICE[] = "0000de00-3dd4-4255-8d62-6dc7b9bd5561";

    /**
     * Characteristic for writing pairing message and receive indications.
     */
    constexpr char PAIR_CHR[] = "00002000-3dd4-4255-8d62-6dc7b9bd5561";

    constexpr char NOT1_CHR[] = "00002008-3dd4-4255-8d62-6dc7b9bd5561";
    constexpr char NOT2_CHR[] = "0000200a-3dd4-4255-8d62-6dc7b9bd5561";

    /**
     * Characteristic for writing controller's id.
     * Should be 32 bytes of ASCII chars, padding with zero.
     */
    constexpr char ID_CHR[] = "00002002-3dd4-4255-8d62-6dc7b9bd5561";

    /**
     * Characteristic for writing GEO message, providing location to camera.
     */
    constexpr char GEO_CHR[] = "00002007-3dd4-4255-8d62-6dc7b9bd5561";

    /**
     * Characteristic for writing TIME message, providing time to camera.
     */
    constexpr char TIME_CHR[] = "00002006-3dd4-4255-8d62-6dc7b9bd5561";
}

#endif //NIKON_UUID_H
