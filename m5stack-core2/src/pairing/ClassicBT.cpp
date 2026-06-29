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
    NSG_LOG_DEBUG("ClassicBT", "Initializing up classic BT");
    serialBT.enableSSP(true, true);
    serialBT.onConfirmRequest([this](uint32_t numVal) {
        pairCode = numVal;
        char buffer[10];
        snprintf(buffer, sizeof(buffer), "%06u", numVal);
        NSG_LOG_INFO("ClassicBT", "The pairing PIN is: %s", buffer);
        pairCodeReady = true;
    });
    serialBT.onAuthComplete([this](boolean success) {
        authDone = true;
        authSuccess = success;
        if (success) {
            NSG_LOG_INFO("ClassicBT::onAuthComplete", "pairing success");
        } else {
            NSG_LOG_ERROR("ClassicBT::onAuthComplete", "pairing failed");
        }
    });
    // we must use SPP slave mode so camera will find our SPP profile
    // otherwise camera will fail pairing.
    // also the name doesn't matter, camera didn't check it.
    serialBT.begin("nsg", false);
}

ClassicBT::~ClassicBT() { serialBT.end(); }

bool ClassicBT::searchAndInitiatePair(uint32_t searchTimeoutMs) {
    NSG_LOG_INFO("ClassicBT::searchAndInitiatePair", "Scanning classic BT...");
    bool deviceFound = false;
    // the native BT addr for target device
    uint8_t classicAddr[ESP_BD_ADDR_LEN];
    uint32_t scanStartTime = millis();
    while (!deviceFound && millis() - scanStartTime < searchTimeoutMs) {
        // scan for 10s
        auto pResults = serialBT.discover(10000);
        for (size_t i = 0; i < pResults->getCount(); i++) {
            auto device = pResults->getDevice(i);
            if (!device->haveName()) continue;
            if (targetName == device->getName()) {
                NSG_LOG_INFO("ClassicBT::searchAndInitiatePair",
                             "Find camera %s, addr=%s",
                             targetName.c_str(),
                             device->getAddress().toString().c_str());
                memcpy(classicAddr, device->getAddress().getNative(), ESP_BD_ADDR_LEN);
                deviceFound = true;
                break;
            }
        }
        serialBT.discoverClear();
    }

    if (!deviceFound) {
        NSG_LOG_WARN("ClassicBT::searchAndInitiatePair", "Timeout on searching for %s", targetName.c_str());
        return false;
    }

    NSG_LOG_INFO("ClassicBT::searchAndInitiatePair", "Initiating GAP bonding via BTA_DmBond...");
    pairCodeReady = false;
    authDone = false;
    authSuccess = false;
    BTA_DmBond(classicAddr);

    uint32_t bondStart = millis();
    while (!pairCodeReady && millis() - bondStart < 30000) {
        delay(100);
    }

    if (!pairCodeReady) {
        NSG_LOG_ERROR("ClassicBT::searchAndInitiatePair", "Classic BT bonding timed out (30s)");
        return false;
    }

    return true;
}

uint32_t ClassicBT::getPairCode() { return pairCode; }

bool ClassicBT::confirmPairCode(bool accept) {
    serialBT.confirmReply(accept);
    if (!accept) {
        NSG_LOG_INFO("ClassicBT::confirmPairCode", "Pair code rejected by user");
        return false;
    }

    uint32_t authStart = millis();
    // wait 2 mins for auth, aka user click confirm on camera
    while (!authDone && millis() - authStart < 120000) {
        delay(100);
    }

    if (!authDone) {
        NSG_LOG_ERROR("ClassicBT::confirmPairCode", "Classic BT auth timed out (120s)");
        return false;
    }

    if (authSuccess) {
        // give camera sometime to make the connection
        delay(10000);
        NSG_LOG_INFO("ClassicBT::confirmPairCode", "Classic BT bond established");
    }

    return authSuccess;
}
