#include "ClassicBT.h"

#include <Arduino.h>
#include <esp_bt.h>

#include <cstring>

#include "Logging.h"

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
// request directly at the ACL level, with no L2CAP/profile connection. The
// full call chain is:
//   BTA_DmBond → bta_sys_sendmsg → bta_dm_bond → BTM_SecBond
//   → btm_sec_bond_by_transport → (ACL creation + HCI_Authentication_Requested)
//
// Reimplementing this ourselves is not possible: every function in the chain
// is internal to Bluedroid, and Bluedroid owns the HCI interface to the BT
// controller. Disabling Bluedroid to use VHCI directly would kill BLE, which
// is needed for the Nikon handshake.
//
// This is a hard link dependency — if a future ESP-IDF removes BTA_DmBond,
// the build will fail at link time with an undefined symbol error. That is
// intentional: we want to fail fast so the issue is caught immediately.
// To fix, find the replacement symbol:
//   nm <arduino-sdk>/tools/sdk/esp32/lib/libbt.a | grep -i bond
// Candidates: BTA_DmBond, BTA_DmBondByTransport, BTM_SecBond
//
// Tested with: Arduino-ESP32 3.x (ESP-IDF 4.4), espressif32 @ 7.0.1
// =============================================================================
extern "C" void BTA_DmBond(uint8_t* bd_addr);

ClassicBT::ClassicBT(std::string name) : serialBT(), targetName(name), pairCode(0) {
    Logging::debug("ClassicBT", "Initializing up classic BT");
    serialBT.enableSSP(true, true);
    serialBT.onConfirmRequest([this](uint32_t numVal) {
        pairCode = numVal;
        char buffer[10];
        sprintf(buffer, "%06lu", numVal);
        Logging::info("ClassicBT", String("The pairing PIN is: ") + buffer);
        pairCodeReady = true;
    });
    serialBT.onAuthComplete([this](boolean success) {
        authDone = true;
        authSuccess = success;
        if (success) {
            Logging::info("ClassicBT::onAuthComplete", "pairing success");
        } else {
            Logging::error("ClassicBT::onAuthComplete", "pairing failed");
        }
    });
    // we must use SPP slave mode so camera will find our SPP profile
    // otherwise camera will fail pairing.
    // also the name doesn't matter, camera didn't check it.
    serialBT.begin("nsg", false);
}

ClassicBT::~ClassicBT() { serialBT.end(); }

bool ClassicBT::searchAndInitiatePair() {
    Logging::info("ClassicBT::searchAndInitiatePair", "Scanning classic BT...");
    BTAdvertisedDevice* pDevice = nullptr;
    while (!pDevice) {
        // scan for 10s
        auto pResults = serialBT.discover(10000);
        for (size_t i = 0; i < pResults->getCount(); i++) {
            auto device = pResults->getDevice(i);
            if (!device->haveName()) continue;
            if (targetName == device->getName()) {
                pDevice = device;
                break;
            }
        }
    }

    Logging::info("ClassicBT::searchAndInitiatePair", "Find camera " + String(pDevice->getName().c_str()) + ", addr=" + pDevice->getAddress().toString().c_str());

    Logging::info("ClassicBT::searchAndInitiatePair", "Initiating GAP bonding via BTA_DmBond...");
    uint8_t classicAddr[ESP_BD_ADDR_LEN];
    memcpy(classicAddr, pDevice->getAddress().getNative(), ESP_BD_ADDR_LEN);

    pairCodeReady = false;
    authDone = false;
    authSuccess = false;
    BTA_DmBond(classicAddr);

    unsigned long bondStart = millis();
    while (!pairCodeReady && millis() - bondStart < 30000) {
        delay(100);
    }

    if (!pairCodeReady) {
        Logging::error("ClassicBT::searchAndInitiatePair", "Classic BT bonding timed out (30s)");
        return false;
    }

    return true;
}

uint32_t ClassicBT::getPairCode() { return pairCode; }

bool ClassicBT::confirmPairCode(bool accept) {
    serialBT.confirmReply(accept);
    if (!accept) {
        Logging::info("ClassicBT::confirmPairCode", "Pair code rejected by user");
        return false;
    }

    unsigned long authStart = millis();
    // wait 2 mins for auth, aka user click confirm on camera
    while (!authDone && millis() - authStart < 120000) {
        delay(100);
    }

    if (!authDone) {
        Logging::error("ClassicBT::confirmPairCode", "Classic BT auth timed out (120s)");
        return false;
    }

    if (authSuccess) {
        // give camera sometime to make the connection
        delay(10000);
        Logging::info("ClassicBT::confirmPairCode", "Classic BT bond established");
    }

    return authSuccess;
}
