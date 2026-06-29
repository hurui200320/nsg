#include "NikonBLEClient.h"

#include <BLEDevice.h>

#include "Config.h"
#include "Logging.h"
#include "NikonUUID.h"
#include "Utils.h"

NikonBLEClient::NikonBLEClient(RandomGenerator& randomGenerator)
    : rnd(randomGenerator),
      hasher(),
      engine(rnd, hasher),
      stage1Message(0, 0, 0, 0),
      stage2Message(0, 0, 0, 0),
      stage3Message(0, 0, 0, 0),
      stage4Message(0, 0, 0, 0),
      nikonService(nullptr),
      timeChar(nullptr),
      geoChar(nullptr) {
    // generate device and nonce right now
    device = engine.generateDeviceId();
    nonce = engine.generateNonce();
    pClient = BLEDevice::createClient();
}

NikonBLEClient::NikonBLEClient(RandomGenerator& randomGenerator, const uint32_t savedDevice, const uint32_t savedNonce)
    : rnd(randomGenerator),
      hasher(),
      engine(rnd, hasher),
      device(savedDevice),
      nonce(savedNonce),
      stage1Message(0, 0, 0, 0),
      stage2Message(0, 0, 0, 0),
      stage3Message(0, 0, 0, 0),
      stage4Message(0, 0, 0, 0),
      nikonService(nullptr),
      timeChar(nullptr),
      geoChar(nullptr) {
    pClient = BLEDevice::createClient();
}

NikonBLEClient::~NikonBLEClient() {
    disconnect();
    if (pClient != nullptr) {
        delete pClient;
        pClient = nullptr;
    }
}

bool NikonBLEClient::doHandshake(BLEAddress address, const uint8_t addrType) {
    if (!pClient) {
        NSG_LOG_ERROR("NikonBLEClient::doHandshake", "[%s] BLEClient is nullptr", address.toString().c_str());
        return false;
    }
    if (pClient->isConnected()) {
        auto addr = pClient->getPeerAddress();
        NSG_LOG_ERROR("NikonBLEClient::doHandshake", "[%s] BLEClient is already connect to %s", address.toString().c_str(), addr.toString().c_str());
        return false;
    }

    NSG_LOG_DEBUG("NikonBLEClient::doHandshake", "[%s] BLE connecting...", address.toString().c_str());
    // connect with timeout 45s, when camera goes to idle, it still broadcast, but takes longer to connect
    if (!pClient->connect(address, addrType, 45000)) {
        NSG_LOG_ERROR("NikonBLEClient::doHandshake", "[%s] BLE failed to connect", address.toString().c_str());
        return false;
    }
    NSG_LOG_INFO("NikonBLEClient::doHandshake", "[%s] BLE connected", address.toString().c_str());

    // request MTU, 517 bytes is the max
    if (!pClient->setMTU(517)) {
        NSG_LOG_ERROR("NikonBLEClient::doHandshake", "[%s] Failed to set MTU", address.toString().c_str());
        pClient->disconnect();
        return false;
    }

    // create nikon service
    nikonService = pClient->getService(NikonUUID::SERVICE);
    if (nikonService == nullptr) {
        NSG_LOG_ERROR("NikonBLEClient::doHandshake", "[%s] Failed to get Nikon Service", address.toString().c_str());
        pClient->disconnect();
        return false;
    }

    // for PAIR, we don't register callback, we just read it.
    auto pairChar = nikonService->getCharacteristic(NikonUUID::PAIR_CHR);
    if (pairChar == nullptr) {
        NSG_LOG_ERROR("NikonBLEClient::doHandshake", "[%s] Failed to get PAIR characteristic", address.toString().c_str());
        pClient->disconnect();
        return false;
    }
    // NOT1 and NOT2 seems return nothing, so we don't setup notify on them.

    // start doing handshake
    stage1Message = engine.createStage1(&device, &nonce);
    uint8_t stage1bytes[PairingMessage::SIZE];
    stage1Message.encode(stage1bytes, sizeof(stage1bytes));
    NSG_LOG_INFO("NikonBLEClient::doHandshake", "[%s] Sending stage 1 message: %s", address.toString().c_str(), stage1Message.toString().c_str());
    if (!pairChar->writeValue(stage1bytes, PairingMessage::SIZE, true)) {
        NSG_LOG_ERROR("NikonBLEClient::doHandshake", "[%s] Failed to write stage 1 message", address.toString().c_str());
        pClient->disconnect();
        return false;
    }
    NSG_LOG_DEBUG("NikonBLEClient::doHandshake", "[%s] Sent stage 1 message: %s", address.toString().c_str(),
                  Utils::hexStr(stage1bytes, PairingMessage::SIZE).c_str());

    NSG_LOG_DEBUG("NikonBLEClient::doHandshake", "[%s] Reading stage 2 message...", address.toString().c_str());
    auto stage2str = pairChar->readValue();
    NSG_LOG_DEBUG("NikonBLEClient::doHandshake", "[%s] Received stage 2 message: %zu", address.toString().c_str(), stage2str.length());
    if (stage2str.length() < PairingMessage::SIZE) {
        pClient->disconnect();
        return false;
    }
    stage2Message = PairingMessage::decode(reinterpret_cast<const uint8_t*>(stage2str.c_str()), stage2str.length());
    NSG_LOG_INFO("NikonBLEClient::doHandshake", "[%s] Decoded stage 2 message: %s", address.toString().c_str(), stage2Message.toString().c_str());

    stage3Message = engine.verifyStage2AndBuildStage3(stage1Message, stage2Message);
    if (stage3Message.stage == 0) {
        NSG_LOG_ERROR("NikonBLEClient::doHandshake", "[%s] Failed to create stage 3 message", address.toString().c_str());
        pClient->disconnect();
        return false;
    }
    uint8_t stage3bytes[PairingMessage::SIZE];
    stage3Message.encode(stage3bytes, sizeof(stage3bytes));
    NSG_LOG_INFO("NikonBLEClient::doHandshake", "[%s] Sending stage 3 message: %s", address.toString().c_str(), stage3Message.toString().c_str());
    if (!pairChar->writeValue(stage3bytes, PairingMessage::SIZE, true)) {
        NSG_LOG_ERROR("NikonBLEClient::doHandshake", "[%s] Failed to write stage 3 message", address.toString().c_str());
        pClient->disconnect();
        return false;
    }
    NSG_LOG_DEBUG("NikonBLEClient::doHandshake", "[%s] Sent stage 3 message: %s", address.toString().c_str(),
                  Utils::hexStr(stage3bytes, PairingMessage::SIZE).c_str());

    NSG_LOG_DEBUG("NikonBLEClient::doHandshake", "[%s] Reading stage 4 message...", address.toString().c_str());
    auto stage4str = pairChar->readValue();
    NSG_LOG_DEBUG("NikonBLEClient::doHandshake", "[%s] Received stage 4 message: %zu", address.toString().c_str(), stage4str.length());
    if (stage4str.length() < PairingMessage::SIZE) {
        pClient->disconnect();
        return false;
    }
    stage4Message = PairingMessage::decode(reinterpret_cast<const uint8_t*>(stage4str.c_str()), stage4str.length());
    NSG_LOG_DEBUG("NikonBLEClient::doHandshake", "[%s] Decoded stage 4 message: %s", address.toString().c_str(), stage4Message.toString().c_str());

    // writing controller name
    NSG_LOG_INFO("NikonBLEClient::doHandshake", "[%s] Writing controller name characteristic...", address.toString().c_str());
    auto idChar = nikonService->getCharacteristic(NikonUUID::ID_CHR);
    if (idChar == nullptr) {
        NSG_LOG_ERROR("NikonBLEClient::doHandshake", "[%s] Failed to get ID characteristic", address.toString().c_str());
        pClient->disconnect();
        return false;
    }
    // max allowed lenght is 31
    uint8_t idPadded[32];
    memset(idPadded, 0, sizeof(idPadded));
    auto idStr = Utils::generateFullId(Config::getOrGenerateId(rnd));
    if (idStr.length() >= 32) {
        NSG_LOG_ERROR("NikonBLEClient::doHandshake", "[%s] Device name length >= 32, too long", address.toString().c_str());
        pClient->disconnect();
        return false;
    }
    memcpy(idPadded, idStr.c_str(), idStr.length());
    NSG_LOG_DEBUG("NikonBLEClient::doHandshake", "[%s] Writing controller name: %s", address.toString().c_str(), idStr.c_str());
    if (!idChar->writeValue(idPadded, sizeof(idPadded), true)) {
        NSG_LOG_ERROR("NikonBLEClient::doHandshake", "[%s] Failed to write controller name", address.toString().c_str());
        pClient->disconnect();
        return false;
    }
    NSG_LOG_DEBUG("NikonBLEClient::doHandshake", "[%s] Controller name written: %s", address.toString().c_str(),
                  Utils::hexStr(idPadded, sizeof(idPadded)).c_str());

    NSG_LOG_INFO("NikonBLEClient::doHandshake", "[%s] handshake success and complete", address.toString().c_str());

    // create timeChar and geoChar
    timeChar = nikonService->getCharacteristic(NikonUUID::TIME_CHR);
    geoChar = nikonService->getCharacteristic(NikonUUID::GEO_CHR);

    // Done. At this point:
    // + if new pair, the camera's classic BT should be broadcasting
    // + if reconnect, the camera should be ready for BLE communication
    return true;
}

bool NikonBLEClient::isConnected() {
    if (pClient != nullptr) {
        return pClient->isConnected();
    } else {
        return false;
    }
}

void NikonBLEClient::disconnect() {
    timeChar = nullptr;
    geoChar = nullptr;
    nikonService = nullptr;
    if (pClient != nullptr && pClient->isConnected()) {
        pClient->disconnect();
    }
}

uint32_t NikonBLEClient::getDevice() { return device; }

uint32_t NikonBLEClient::getNonce() { return nonce; }

bool NikonBLEClient::sendTimePayload(TimeMessage& message) {
    if (pClient == nullptr || !pClient->isConnected()) {
        return false;
    }
    if (timeChar == nullptr) {
        return false;
    }
    uint8_t buffer[TimeMessage::SIZE];
    if (!message.encode(buffer, sizeof(buffer))) {
        return false;
    }
    return timeChar->writeValue(buffer, TimeMessage::SIZE, true);
}

bool NikonBLEClient::sendGeoPayload(GeoMessage& message) {
    if (pClient == nullptr || !pClient->isConnected()) {
        return false;
    }
    if (geoChar == nullptr) {
        return false;
    }
    uint8_t buffer[GeoMessage::SIZE];
    if (!message.encode(buffer, sizeof(buffer))) {
        return false;
    }
    return geoChar->writeValue(buffer, GeoMessage::SIZE, true);
}
