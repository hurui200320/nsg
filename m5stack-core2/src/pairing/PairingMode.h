#ifndef PAIRING_MODE_H
#define PAIRING_MODE_H

#include "BootMode.h"
#include "PairingScanner.h"
#include "../common/NikonBLEClient.h"

class PairingMode : public BootMode {
   public:
    PairingMode();

    void setup() override;
    void loop() override;

   private:
    PairingScanner* scanner;
    NikonBLEClient* pClient;
};

#endif  // PAIRING_MODE_H
