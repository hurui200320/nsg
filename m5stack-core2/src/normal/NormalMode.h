#ifndef NORMAL_MODE_H
#define NORMAL_MODE_H

#include "BootMode.h"

class NormalMode : public BootMode {
   public:
    NormalMode();
    
    void setup() override;
    void loop() override;
};

#endif  // NORMAL_MODE_H
