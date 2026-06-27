#include "PairingMode.h"

#include <Arduino.h>
#include <M5Unified.h>
#include <BluetoothSerial.h>

#include <cstring>
#include <string>
#include <vector>

#include "../common/NikonBLEClient.h"
#include "Config.h"
#include "Logging.h"
#include "PairingModels.h"
#include "PairingScanner.h"
#include "Utils.h"

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
        serialBT.begin("nsg", true);
        // scan for 10s
        Logging::info("loop", "Scanning classic BT...");
        auto pResults = serialBT.discover(10000);
        if (!pResults) {
            Logging::fatal("loop", "failed to discover classic bt devices");
        }
        BTAdvertisedDevice* pDevice = nullptr;
        for (size_t i = 0; i < pResults->getCount(); i++) {
            auto device = pResults->getDevice(i);
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
        // resolve channel
        auto channels = serialBT.getChannels(pDevice->getAddress());
        int channel = 0;
        if (channels.size() > 0) {
            channel = channels.begin()->first;
        }
        // remove if already bonded
        serialBT.unpairDevice(reinterpret_cast<uint8_t*>(pDevice->getAddress().getNative()));
        // create bond
        confirmRequestDone = false;
        if (!serialBT.connect(pDevice->getAddress(), channel, (ESP_SPP_SEC_ENCRYPT | ESP_SPP_SEC_AUTHENTICATE), ESP_SPP_ROLE_MASTER)) {
            Logging::fatal("loop", "failed to pair classic BT");
        }
        while (!confirmRequestDone) {
            delay(1000);
        }
        serialBT.disconnect();
        serialBT.end();

        // stuck here
        while (true) {
            // nop
        }
    }
}
