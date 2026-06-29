#ifndef PAIRING_MODE_H
#define PAIRING_MODE_H

#include <memory>
#include <vector>

#include "BootMode.h"
#include "ClassicBT.h"
#include "Esp32RandomGenerator.h"
#include "PairingScanner.h"
#include "../common/NikonBLEClient.h"
#include "../common/ScannedCamera.h"

class PairingMode : public BootMode {
   public:
    PairingMode();
    ~PairingMode();

    void setup() override;
    void loop() override;

   private:
    enum class State {
        SCANNING,
        PAIRING,
        DONE
    };

    State state;
    Esp32RandomGenerator rnd;
    std::unique_ptr<PairingScanner> scanner;
    std::unique_ptr<NikonBLEClient> pClient;
    std::unique_ptr<ClassicBT> classicBT;
    std::vector<ScannedCamera> cameraList;
    size_t selectedCameraIdx;

    void handleScanResults();
    void selectFirstCamera();
    void runPairingFlow();
};

#endif  // PAIRING_MODE_H
