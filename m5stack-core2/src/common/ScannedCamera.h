#ifndef SCANNED_CAMERA_H
#define SCANNED_CAMERA_H

#include <BLEDevice.h>

typedef struct {
    // haven't seen any camera's name longer than 32 bytes
    char name[33];
    // native addr for BLEAddress
    esp_bd_addr_t addr;
    uint8_t addrType;
    // device from manufacturer data, 0 if no such data
    uint32_t device;
} ScannedCamera; 


#endif
