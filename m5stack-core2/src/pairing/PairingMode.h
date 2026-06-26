#ifndef PAIRING_MODE_H
#define PAIRING_MODE_H

#include "BootMode.h"

class PairingMode : public BootMode {
   public:
    PairingMode();
    
    void setup() override;
    void loop() override;
};

#endif  // PAIRING_MODE_H
