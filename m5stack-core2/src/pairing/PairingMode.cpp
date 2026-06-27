#include "PairingMode.h"

#include <Arduino.h>
#include <BluetoothSerial.h>
#include <M5Unified.h>
#include <esp_bt.h>
#include <esp_idf_version.h>

#include <cstring>
#include <string>
#include <vector>

#include "../common/NikonBLEClient.h"
#include "Config.h"
#include "Logging.h"
#include "PairingModels.h"
#include "PairingScanner.h"
#include "Utils.h"

// =============================================================================
// BTA_DmBond — initiate GAP-level SSP bonding without a profile connection.
//
// The Nikon camera exposes no classic BT profile servers (no SPP, A2DP, HFP).
// It only accepts GAP-level bonding (like Android's BluetoothDevice.createBond()).
// ESP-IDF has NO public API for this — esp_spp_connect / esp_a2d_source_connect
// both require the remote to accept an L2CAP PSM, which the camera rejects
// before the security check runs, so SSP never triggers.
//
// BTA_DmBond is an internal Bluedroid function that sends an LMP pairing
// request directly at the ACL level, with no L2CAP/profile connection. It is
// the function that ALL bonding goes through internally (every profile
// connection calls it under the hood). It has been stable in Bluedroid for
// 10+ years and is exported as a global symbol in libbt.a.
//
// If this symbol ever disappears in a future ESP-IDF version, the fix is to
// find the new equivalent — look for "DmBond" or "SecBond" in libbt.a:
//   nm <arduino-sdk>/tools/sdk/esp32/lib/libbt.a | grep -i bond
//
// Tested with: Arduino-ESP32 3.x (ESP-IDF 4.4), espressif32 @ 7.0.1
// =============================================================================
#if ESP_IDF_VERSION_MAJOR >= 4
extern "C" void BTA_DmBond(uint8_t* bd_addr);
#define NSG_HAS_BTA_DMBOND 1
#else
#error "BTA_DmBond not verified on ESP-IDF < 4; check libbt.a symbols"
#endif

PairingMode::PairingMode() {}

PairingScanner* scanner;
BLESecurity* pSecurity;

void PairingMode::setup() {
    BootMode::initBLE();

    scanner = new PairingScanner();
    scanner->startScanning();
    // turn off backlight since we don't need screen for now
    M5.Display.setBrightness(0);
}

std::vector<Camera> cameraList;
bool selectedCamera = false;
size_t selectedCameraIdx = 0;

NikonBLEClient* pClient;

BluetoothSerial serialBT;
bool confirmRequestDone = false;

void BTConfirmRequestCallback(uint32_t numVal) {
    char buffer[10];
    sprintf(buffer, "%06lu", numVal);
    Logging::info("BTConfirmRequestCallback", std::string("The pairing PIN is: ") + buffer);
    serialBT.confirmReply(true);
}

void BTAuthCompleteCallback(boolean success) {
    if (success) {
        confirmRequestDone = true;
        Logging::info("BTAuthCompleteCallback", "pairing success");
    } else {
        Logging::error("BTAuthCompleteCallback", "pairing failed!!");
    }
}

void PairingMode::loop() {
    Camera camera;
    while (xQueueReceive(scanner->scanResultQueue, &camera, (TickType_t)0)) {
        auto deviceName = std::string(camera.name);
        auto deviceAddr = std::string(camera.addr);
        bool dup = false;
        for (size_t i = 0; i < cameraList.size(); i++) {
            auto item = cameraList[i];
            if (memcmp(item.addr, camera.addr, sizeof(item.addr)) == 0) {
                dup = true;
                break;
            }
        }
        if (!dup) {
            cameraList.push_back(camera);
            Logging::info("BLEScanCallback", "Found " + deviceName + ", addr=" + deviceAddr);
        }
    }

    // TODO: show list on screen?
    // TODO: select one camera

    // TODO: assuming we select the first camera in list
    if (!selectedCamera && cameraList.size() > 0) {
        scanner->stopScanning();
        selectedCameraIdx = 0;
        selectedCamera = true;
        Logging::info("PairingMode::loop", "Pairing with " + std::string(cameraList[selectedCameraIdx].name));
    }

    // TODO: need to ensure only execute once
    if (selectedCamera) {
        camera = cameraList[selectedCameraIdx];
        auto cameraName = std::string(camera.name);
        auto cameraAddr = BLEAddress(std::string(camera.addr));
        // perform BLE handshake
        pClient = new NikonBLEClient();
        if (!pClient->doHandshake(cameraAddr, camera.addrType)) {
            Logging::fatal("loop", "failed to perform handshake");
        }
        Logging::info("loop", "Disconnecting BLE connection");
        pClient->disconnect();
        // TODO: test if we can bring up classic BT while keeping BLE stack
        // delete pClient;
        // pClient = nullptr;

        // start classic BT pairing
        Logging::info("loop", "Setting up classic BT");
        serialBT.enableSSP();
        serialBT.onConfirmRequest(BTConfirmRequestCallback);
        serialBT.onAuthComplete(BTAuthCompleteCallback);
        // we must use SPP slave mode so camera will find our SPP profile
        // otherwise camera will fail pairing
        serialBT.begin("nsg", false);
        // scan for 10s
        Logging::info("loop", "Scanning classic BT...");
        auto pResults = serialBT.discover(10000);
        if (!pResults) {
            Logging::fatal("loop", "failed to discover classic bt devices");
        }
        BTAdvertisedDevice* pDevice = nullptr;
        Logging::info("loop", "Camera name: " + cameraName);
        for (size_t i = 0; i < pResults->getCount(); i++) {
            auto device = pResults->getDevice(i);
            if (!device->haveName()) continue;
            Logging::info("loop", "find device: " + device->getName());
            if (cameraName == device->getName()) {
                pDevice = device;
                break;
            }
        }
        if (!pDevice) {
            Logging::fatal("loop", "Camera not found");
        } else {
            Logging::info("loop", "Find camera " + pDevice->getName() + ", addr=" + pDevice->getAddress().toString().c_str());
        }

        // Initiate GAP-level bonding directly via BTA_DmBond.
        // This sends an LMP pairing request at the ACL level — equivalent to
        // Android's BluetoothDevice.createBond(). No profile/L2CAP connection
        // is needed. The camera's CoD is "imaging" (shows as printer/camera
        // icon on Android); it serves no BT profiles, only GAP bonding.
        Logging::info("loop", "Initiating GAP bonding via BTA_DmBond...");
        uint8_t classicAddr[ESP_BD_ADDR_LEN];
        memcpy(classicAddr, pDevice->getAddress().getNative(), ESP_BD_ADDR_LEN);
        // BTA_DmBond will automatically handle re-pairing.
        // the serialBt's unpair device is async and will break the BTA_DmBond
        confirmRequestDone = false;
#if defined(NSG_HAS_BTA_DMBOND) && NSG_HAS_BTA_DMBOND
        BTA_DmBond(classicAddr);
#else
        Logging::fatal("loop", "BTA_DmBond not available, cannot bond");
#endif

        unsigned long bondStart = millis();
        while (!confirmRequestDone && millis() - bondStart < 30000) {
            delay(100);
        }

        if (confirmRequestDone) {
            // give camera sometime to make the connection
            delay(10000);
            Logging::info("loop", "Classic BT bond established");
        } else {
            Logging::error("loop", "Classic BT bonding timed out (30s)");
        }

        serialBT.end();

        // stuck here
        while (true) {
            // nop
        }
    }
}
