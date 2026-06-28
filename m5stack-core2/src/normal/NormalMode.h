#ifndef NORMAL_MODE_H
#define NORMAL_MODE_H

#include "BootMode.h"
#include "ConnectedCamera.h"
#include "PairedScanner.h"

class NormalMode : public BootMode {
   public:
    NormalMode();

    void setup() override;
    void loop() override;

   private:
    PairedScanner* scanner;
    std::vector<ConnectedCamera> connectedCameras;
};

#endif  // NORMAL_MODE_H
