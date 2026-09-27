#include "NormalMode.h"

#include <sys/time.h>

#include <cmath>

#include "Config.h"
#include "Logging.h"
#include "UBlox.h"
#include "common/StatusLED.h"

NormalMode::NormalMode() {}

NormalMode::~NormalMode() { bleWorker.stop(); }

void NormalMode::setup() {
    // init GNSS
    gnss.setRxBufferSize(GNSS_RX_BUFFER_SIZE);
    gnss.begin(UBLOX_GNSS_TARGET_BAUD_RATE, SERIAL_8N1, UBLOX_GNSS_RX_PIN, UBLOX_GNSS_TX_PIN);

    // send signal config with fallback baud rate
    NSG_LOG_INFO("NormalMode::setup", "Config UBlox GNSS...");
    bool onFallbackBaudRate = false;
    while (true) {
        // drain rx buffer before send ublox command
        while (gnss.available()) gnss.read();
        if (UBlox::sendConfig(gnss)) {
            // give ublox GNSS subsystem a bit time to restart after satellite config changes
            delay(500);
            break;
        }
        // still fail, try the fallback baud rate
        if (!onFallbackBaudRate) {
            NSG_LOG_INFO("NormalMode::setup", "Change GNSS baud rate from %lu to %d...", (unsigned long)gnss.baudRate(), UBLOX_GNSS_FALLBACK_BAUD_RATE);
            gnss.updateBaudRate(UBLOX_GNSS_FALLBACK_BAUD_RATE);
            onFallbackBaudRate = true;
        } else {
            // already on default baud rate but still not working
            esp_restart();
        }
    }
    // update baud rate to target
    if (onFallbackBaudRate) {
        if (UBlox::setBaudRate(gnss, UBLOX_GNSS_TARGET_BAUD_RATE)) {
            gnss.updateBaudRate(UBLOX_GNSS_TARGET_BAUD_RATE);
            NSG_LOG_DEBUG("NormalMode::setup", "Upgraded GNSS baud rate to %d", UBLOX_GNSS_TARGET_BAUD_RATE);
        } else {
            esp_restart();
        }
    }

    // start the BLE worker on core 0 (loads saved cameras + scanner internally)
    if (!bleWorker.start()) {
        NSG_LOG_FATAL("NormalMode::setup", "failed to start BLE worker");
    }
}

void NormalMode::loop() {
    // first process GNSS UART
    bool nmeaGotNewCommand = false;
    while (gnss.available()) {
        if (nmea.process(gnss.read())) {
            nmeaGotNewCommand = true;
        }
    }

    uint8_t gnssValid = nmea.isValid() ? 1 : 0;
    // lat and lon returned in millionths of a degree
    double lat = ((double)nmea.getLatitude()) / 1000000.0;
    double lon = ((double)nmea.getLongitude()) / 1000000.0;
    int32_t altitude = 0;
    if (!nmea.getAltitude(altitude)) {
        altitude = 0;
        gnssValid = 0;
    }
    // altitude returned in millimeter
    altitude = altitude / 1000;
    uint8_t satellites = nmea.getNumSatellites();

    GnssSnapshot gnssSnapshot{lat, lon, altitude, satellites, gnssValid};

    BleStatusSnapshot bleStatus = bleWorker.getBleStatusSnapshot();
    printStatus(gnssSnapshot, bleStatus);

    // status LED: G on = normal mode, B on = at least one camera connected
    statusLed.setColor(STATUS_LED_OFF, STATUS_LED_ON, bleStatus.activeConnections > 0 ? STATUS_LED_ON : STATUS_LED_OFF);

    // if we got update from GPS
    if (nmeaGotNewCommand) {
        // sync time from GNSS periodically
        if (nmea.isValid() && (millis() - nmeaLastSync > GNSS_TIME_SYNC_INTERVAL_MS || nmeaLastSync == 0)) {
            uint16_t year = nmea.getYear();
            uint8_t month = nmea.getMonth();
            uint8_t day = nmea.getDay();
            uint8_t hour = nmea.getHour();
            uint8_t minute = nmea.getMinute();
            uint8_t second = nmea.getSecond();
            // ensure we have valid time after fix, maybe RMC sentence will come after location fixed
            if (year >= 2026) {
                // hold the BLE worker's lock so it cannot read the RTC mid-write
                {
                    BleWorker::Lock lk(bleWorker);
                    // rtc holds UTC; TZ=GMT so mktime treats tm as UTC
                    struct tm t{};
                    t.tm_year = year - 1900;
                    t.tm_mon = month - 1;
                    t.tm_mday = day;
                    t.tm_hour = hour;
                    t.tm_min = minute;
                    t.tm_sec = second;
                    t.tm_isdst = -1;
                    struct timeval tv{};
                    tv.tv_sec = mktime(&t);
                    settimeofday(&tv, nullptr);
                }
                NSG_LOG_INFO("NormalMode::loop", "Synced time from GNSS: %04d/%02d/%02d %02d:%02d:%02d", year, month, day, hour, minute, second);
                nmeaLastSync = millis();
            }
        }

        // push current GNSS/RTC state to the BLE worker for payload building
        bleWorker.setGnssSnapshot(gnssSnapshot);
    }
}

void NormalMode::printStatus(GnssSnapshot const& gnssStatus, BleStatusSnapshot const& bleStatus) {
    if (millis() - lastStatusPrint <= 10000) return;
    lastStatusPrint = millis();
    NSG_LOG_INFO("GPS Status", "FIX: %s", gnssStatus.gnssValid ? "VALID" : "INVALID");
    // latitude
    auto latAbs = std::fabs(gnssStatus.lat);
    uint8_t latD = static_cast<uint8_t>(latAbs);
    double latM = (latAbs - latD) * 60.0;
    NSG_LOG_INFO("GPS Status", "LAT: %s %3d deg %06.3f'", gnssStatus.lat >= 0 ? "N" : "S", latD, latM);
    // longitude
    auto lonAbs = std::fabs(gnssStatus.lon);
    uint8_t lonD = static_cast<uint8_t>(lonAbs);
    double lonM = (lonAbs - lonD) * 60.0;
    NSG_LOG_INFO("GPS Status", "LON: %s %3d deg %06.3f'", gnssStatus.lon >= 0 ? "E" : "W", lonD, lonM);
    // altitude, some extra space to cover digits change
    NSG_LOG_INFO("GPS Status", "ALT: %s %ld M", gnssStatus.altitudeMeters >= 0 ? "+" : "-",  //
                 (long)(gnssStatus.altitudeMeters >= 0 ? gnssStatus.altitudeMeters : -gnssStatus.altitudeMeters));
    // satellites count
    NSG_LOG_INFO("GPS Status", "SAT: %d", gnssStatus.satellites);
    // BLE connection
    NSG_LOG_INFO("GPS Status", "BLE: %lu / %d", (unsigned long)bleStatus.activeConnections, CONFIG_BTDM_CTRL_BLE_MAX_CONN);
    // Paired devices
    NSG_LOG_INFO("GPS Status", "CAM: %lu paired", (unsigned long)bleStatus.pairedCount);
}
