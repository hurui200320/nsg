#ifndef PAIRING_MODELS_H
#define PAIRING_MODELS_H

typedef struct {
    // haven't seen any camera's name longer than 45 bytes
    char name[46];
    // 4b:f9:87:33:6f:dd, last is always '\0'
    char addr[18];
} Camera;  // each struct is 64 bytes


#endif
