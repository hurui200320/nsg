#ifndef PAIRING_MODELS_H
#define PAIRING_MODELS_H

typedef struct {
    // haven't seen any camera's name longer than 32 bytes
    char name[33];
    // 4b:f9:87:33:6f:dd, last is always '\0'
    char addr[18];
    esp_ble_addr_type_t addrType;
} Camera; 


#endif
