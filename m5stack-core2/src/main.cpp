#include <Arduino.h>
#include <BLEDevice.h>
#include <M5Unified.h>

#include "BootMode.h"
#include "Config.h"
#include "Logging.h"
#include "Utils.h"
#include "normal/NormalMode.h"
#include "pairing/PairingMode.h"

void drawCentered(const String& text, int y, int textSize = 2, uint32_t color = TFT_WHITE) {
    M5.Display.setTextSize(textSize);
    M5.Display.setTextColor(color, TFT_BLACK);
    M5.Display.setTextDatum(middle_center);
    M5.Display.drawString(text, M5.Display.width() / 2, y);
}

BootModeEnum detectBootMode() {
    const unsigned long WAIT_MS = 5000;
    const unsigned long THRESHOLD_MS = 2500;
    const unsigned long REFRESH_MS = 30;

    unsigned long startMs = millis();
    unsigned long touched = 0;

    // draw text
    M5.Display.fillScreen(TFT_BLACK);
    drawCentered("Press screen for 3s", M5.Display.height() / 2 - 45, 2);
    drawCentered("to enter", M5.Display.height() / 2 - 20, 2);
    drawCentered("Pairing Mode", M5.Display.height() / 2 + 5, 3, TFT_YELLOW);

    while (millis() - startMs < WAIT_MS) {
        M5.update();

        // any touch will be considered valid
        if (M5.Touch.getCount() > 0) {
            touched += REFRESH_MS;
            if (touched >= THRESHOLD_MS) break;
        } else {
            touched = 0;
        }

        // show counter
        int remaining = (WAIT_MS - (millis() - startMs) + 999) / 1000;
        // This will cause flickering
        // M5.Display.fillRect(0, M5.Display.height() / 2 + 30, M5.Display.width(), 40, TFT_BLACK);
        drawCentered(String("Auto normal in ") + remaining + "s", M5.Display.height() / 2 + 50, 2, TFT_LIGHTGREY);

        delay(REFRESH_MS);
    }

    // show result
    M5.Display.fillScreen(TFT_BLACK);
    if (touched >= THRESHOLD_MS) {
        Logging::info("DetectBootMode", "Booting into pairing mode...");
        drawCentered("Pairing Mode", M5.Display.height() / 2, 3, TFT_GREEN);
        return BootModeEnum::PAIRING;
    } else {
        Logging::info("DetectBootMode", "Booting into normal mode...");
        drawCentered("Normal Mode", M5.Display.height() / 2, 3, TFT_CYAN);
        return BootModeEnum::NORMAL;
    }
}

BootModeEnum bootModeType = BootModeEnum::NORMAL;
NormalMode* normalMode = nullptr;
PairingMode* pairingMode = nullptr;

void setup() {
    // enable default serial as monitor
    Serial.begin(115200);
    Logging::debug("MainSetup", "Serial initialized");
    // Initialize M5 for screen, etc.
    M5.begin();
    Logging::debug("MainSetup", "M5 initialized");

    if (!M5.Rtc.isEnabled()) {
        Logging::fatal("MainSetup", "RTC not found, waiting...");
    }

    if (!M5.Rtc.begin()) {
        Logging::error("MainSetup", "failed to initialize RTC");
    }

    // collect boot up mode
    Logging::debug("MainSetup", "Detecting boot mode...");
    bootModeType = detectBootMode();

    switch (bootModeType) {
        case BootModeEnum::NORMAL:
            normalMode = new NormalMode();
            normalMode->setup();
            break;

        case BootModeEnum::PAIRING:
            pairingMode = new PairingMode();
            pairingMode->setup();
            break;

        default:
            Logging::fatal("MainSetup", "Unexpected boot type");
            break;
    }
}

void loop() {
    switch (bootModeType) {
        case BootModeEnum::NORMAL:
            if (normalMode) {
                normalMode->loop();
            } else {
                Logging::fatal("MainLoop", "Boot type normal but nullptr");
            }
            break;

        case BootModeEnum::PAIRING:
            if (pairingMode) {
                pairingMode->loop();
            } else {
                Logging::fatal("MainLoop", "Boot type pairing but nullptr");
            }
            break;

        default:
            Logging::fatal("MainLoop", "Unexpected boot type");
            break;
    }
}
