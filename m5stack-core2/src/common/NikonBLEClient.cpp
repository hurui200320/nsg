#include "NikonBLEClient.h"

#include <BLEDevice.h>

#include "Config.h"
#include "Logging.h"
#include "NikonUUID.h"
#include "Utils.h"

NikonBLEClient::NikonBLEClient()
    : rnd(),
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

NikonBLEClient::NikonBLEClient(const uint32_t savedDevice, const uint32_t savedNonce)
    : rnd(),
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

void handshakeLoggingDebug(BLEAddress address, const std::string& msg) {
    Logging::debug("NikonBLEClient::doHandshake/" + address.toString(), String(msg.c_str()));
}
void handshakeLoggingInfo(BLEAddress address, const std::string& msg) {
    Logging::info("NikonBLEClient::doHandshake/" + address.toString(), String(msg.c_str()));
}
void handshakeLoggingWarn(BLEAddress address, const std::string& msg) {
    Logging::warn("NikonBLEClient::doHandshake/" + address.toString(), String(msg.c_str()));
}
void handshakeLoggingError(BLEAddress address, const std::string& msg) {
    Logging::error("NikonBLEClient::doHandshake/" + address.toString(), String(msg.c_str()));
}

bool NikonBLEClient::doHandshake(BLEAddress address, const uint8_t addrType) {
    if (!pClient) {
        handshakeLoggingError(address, "BLEClient is nullptr");
        return false;
    }
    if (pClient->isConnected()) {
        auto addr = pClient->getPeerAddress();
        handshakeLoggingError(address, "BLEClient is already connect to " + std::string(addr.toString().c_str()));
        return false;
    }

    handshakeLoggingDebug(address, "Connecting to " + std::string(address.toString().c_str()) + "...");
    // connect with timeout 45s, when camera goes to idle, it still broadcast, but takes longer to connect
    if (!pClient->connect(address, addrType, 45000)) {
        handshakeLoggingError(address, "Failed to connect");
        return false;
    }
    handshakeLoggingInfo(address, "Connected to " + std::string(address.toString().c_str()));

    // request MTU, 517 bytes is the max
    if (!pClient->setMTU(517)) {
        handshakeLoggingError(address, "Failed to set MTU");
        return false;
    }

    // create nikon service
    nikonService = pClient->getService(NikonUUID::SERVICE);
    if (nikonService == nullptr) {
        handshakeLoggingError(address, "Failed to get Nikon Service");
        return false;
    }

    // for PAIR, we don't register callback, we just read it.
    auto pairChar = nikonService->getCharacteristic(NikonUUID::PAIR_CHR);
    if (pairChar == nullptr) {
        handshakeLoggingError(address, "Failed to get PAIR characteristic");
        return false;
    }
    // NOT1 and NOT2 seems return nothing, so we don't setup notify on them.

    // start doing handshake
    stage1Message = engine.createStage1(&device, &nonce);
    uint8_t stage1bytes[PairingMessage::SIZE];
    stage1Message.encode(stage1bytes);
    handshakeLoggingInfo(address, "Sending stage 1 message: " + stage1Message.toString());
    pairChar->writeValue(stage1bytes, PairingMessage::SIZE, true);
    handshakeLoggingInfo(address, "Sent stage 1 message: " + Utils::hexStr(stage1bytes, PairingMessage::SIZE));

    handshakeLoggingDebug(address, "Reading stage 2 message...");
    auto stage2str = pairChar->readValue();
    handshakeLoggingInfo(address, "Received stage 2 message: " + std::to_string(stage2str.length()));
    if (stage2str.length() < PairingMessage::SIZE) {
        return false;
    }
    stage2Message = PairingMessage::decode(reinterpret_cast<const uint8_t*>(stage2str.c_str()));
    handshakeLoggingInfo(address, "Decoded stage 2 message: " + stage2Message.toString());

    stage3Message = engine.verifyStage2AndBuildStage3(stage1Message, stage2Message);
    if (stage3Message.stage == 0) {
        handshakeLoggingError(address, "failed to create stage 3 message");
        return false;
    }
    uint8_t stage3bytes[PairingMessage::SIZE];
    stage3Message.encode(stage3bytes);
    handshakeLoggingInfo(address, "Sending stage 3 message: " + stage3Message.toString());
    pairChar->writeValue(stage3bytes, PairingMessage::SIZE, true);
    handshakeLoggingInfo(address, "Sent stage 3 message: " + Utils::hexStr(stage3bytes, PairingMessage::SIZE));

    handshakeLoggingInfo(address, "Reading stage 4 message...");
    auto stage4str = pairChar->readValue();
    handshakeLoggingInfo(address, "Received stage 4 message: " + std::to_string(stage4str.length()));
    if (stage4str.length() < PairingMessage::SIZE) {
        return false;
    }
    stage4Message = PairingMessage::decode(reinterpret_cast<const uint8_t*>(stage4str.c_str()));
    handshakeLoggingInfo(address, "Decoded stage 4 message: " + stage4Message.toString());

    // writing controller name
    handshakeLoggingDebug(address, "Writing controller name characteristic...");
    auto idChar = nikonService->getCharacteristic(NikonUUID::ID_CHR);
    if (idChar == nullptr) {
        handshakeLoggingError(address, "Failed to get ID characteristic");
        return false;
    }
    uint8_t idPadded[32];
    memset(idPadded, 0, sizeof(idPadded));
    auto idStr = Utils::generateFullId(Config::getOrGenerateId());
    if (idStr.length() >= 32) {
        handshakeLoggingError(address, "Device name length >= 32, too long");
        return false;
    }
    memcpy(idPadded, idStr.c_str(), idStr.length());
    handshakeLoggingDebug(address, "Writing controller name: " + idStr);
    idChar->writeValue(idPadded, sizeof(idPadded), true);
    handshakeLoggingInfo(address, "Controller name written: " + Utils::hexStr(idPadded, sizeof(idPadded)));

    handshakeLoggingInfo(address, "handshake complete");

    // create timeChar and geoChar
    timeChar = nikonService->getCharacteristic(NikonUUID::TIME_CHR);
    geoChar = nikonService->getCharacteristic(NikonUUID::GEO_CHR);

    // Done. At this point:
    // + if new pair, the camera's classic BT should be broadcasting
    // + if reconnect, the camera should be ready for BLE communication
    return true;
}

bool NikonBLEClient::isConnnected() {
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
    message.encode(buffer);
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
    message.encode(buffer);
    return geoChar->writeValue(buffer, GeoMessage::SIZE, true);
}
