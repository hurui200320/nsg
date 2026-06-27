#ifndef CLASSIC_BT_H
#define CLASSIC_BT_H

#include <BluetoothSerial.h>

#include <string>

class ClassicBT {
   public:
    ClassicBT(std::string name);
    ~ClassicBT();
    // return true -> start pairing, need to check and confirm code.
    // return false -> failed
    bool searchAndInitiatePair();
    uint32_t getPairCode();
    // return true -> pair confirmed,
    // return false -> pair failed.
    bool confirmPairCode(bool accept);

   private:
    BluetoothSerial serialBT;
    uint32_t pairCode;
    std::string targetName;
    bool pairCodeReady = false;
    bool authDone = false;
    bool authSuccess = false;
};

#endif
