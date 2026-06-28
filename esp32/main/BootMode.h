#ifndef BOOT_MODE_H
#define BOOT_MODE_H

enum class BootModeEnum {
    PAIRING,
    NORMAL
};

class BootMode {
   public:
    virtual ~BootMode() = default;
    virtual void setup() = 0;
    virtual void loop() = 0;

   protected:
    /**
     * Init BLE with proper device name.
     */
    void initBLE();
};

#endif  // BOOT_MODE_H
