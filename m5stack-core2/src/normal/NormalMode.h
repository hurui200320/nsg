#ifndef NORMAL_MODE_H
#define NORMAL_MODE_H

#include "BootMode.h"
#include "ConnectedCamera.h"
#include "GeoMessage.h"
#include "PairedScanner.h"
#include "TimeMessage.h"

class NormalMode : public BootMode {
   public:
    NormalMode();

    void setup() override;
    void loop() override;

   private:
    PairedScanner* scanner;
    std::vector<ConnectedCamera> connectedCameras;
    void updateTimeMessageWithRTC(TimeMessage& message);
    GeoMessage generateGeoMessage(double lat, double lon, int32_t altitude, uint8_t satellites, uint8_t valid);
};

#endif  // NORMAL_MODE_H
