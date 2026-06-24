package info.skyblond.nsg

import com.welie.blessed.ScanResult
import com.welie.blessed.bluez.AbstractBluetoothObject
import com.welie.blessed.bluez.BluezDeviceType
import org.bluez.Adapter1
import org.bluez.Agent1
import org.bluez.AgentManager1
import org.bluez.Device1
import org.bluez.exceptions.BluezRejectedException
import org.freedesktop.dbus.DBusPath
import org.freedesktop.dbus.connections.impl.DBusConnection
import org.freedesktop.dbus.connections.impl.DBusConnectionBuilder
import org.freedesktop.dbus.interfaces.DBusInterface
import org.freedesktop.dbus.interfaces.ObjectManager
import org.freedesktop.dbus.interfaces.Properties
import org.freedesktop.dbus.types.UInt16
import org.freedesktop.dbus.types.UInt32
import org.freedesktop.dbus.types.Variant
import org.slf4j.LoggerFactory
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.TimeoutException

private val bondLogger = LoggerFactory.getLogger("ClassicBond")

fun ByteArray.toHex(separator: String = "") = this.joinToString(separator) { "%02x".format(it) }

fun formatManufacturerData(record: ScanResult): String {
    val data = record.manufacturerData
    if (data.isEmpty()) return "none"
    return data.keys.map { key ->
        val bytes = data[key] ?: byteArrayOf()
        val keyString = "company=0x%04X".format(key)
        val valueString = bytes.toHex(" ")
        listOf(keyString, valueString).joinToString(" ")
    }.joinToString(separator = "; ")
}

// Convert Long type device (actual uint32) to 4 bytes in little endian
private fun Long.toDeviceLittleEndianBytes(): ByteArray {
    val buffer = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN)
    buffer.putInt((this and 0xFFFFFFFFL).toInt())
    return buffer.array()
}

fun verifyManufacturerData(record: ScanResult, expectedDevice: Long): Boolean {
    // 921 -> 0x0399 -> Nikon
    val bytes = record.manufacturerData[921] ?: byteArrayOf()
    if (bytes.size < 4) return false
    val deviceBytes = bytes.copyOfRange(0, 4)
    val expectedBytes = expectedDevice.toDeviceLittleEndianBytes()
    return deviceBytes.contentEquals(expectedBytes)
}

/**
 * Pair with a classic Bluetooth device that has the same name as the camera.
 *
 * The PC side will auto-accept the pairing request.
 *
 * @param name the camera name to look for
 * @param adapter the BlueZ adapter name, e.g. "hci0"
 * @param timeoutMs maximum time to wait for discovery and pairing
 * @return the MAC address of the bonded classic device
 */
fun createClassicBond(
    name: String,
    adapter: String = "hci0",
    timeoutMs: Long = 120_000L
): String {
    val deadline = System.currentTimeMillis() + timeoutMs
    val agentPath = "/info/skyblond/nsg/classic/agent"
    val connection = DBusConnectionBuilder.forSystemBus().withShared(false).build()

    return connection.use { conn ->
        val agent = AutoAcceptAgent(agentPath, conn)
        conn.exportObject(agentPath, agent)

        val agentManager = conn.getRemoteObject("org.bluez", "/org/bluez", AgentManager1::class.java)
        val adapter1 = conn.getRemoteObject("org.bluez", "/org/bluez/$adapter", Adapter1::class.java)
        val objectManager = conn.getRemoteObject("org.bluez", "/", ObjectManager::class.java)

        try {
            agentManager.RegisterAgent(DBusPath(agentPath), "KeyboardDisplay")
            agentManager.RequestDefaultAgent(DBusPath(agentPath))

            val filter: MutableMap<String, Variant<*>> = HashMap()
            filter["Transport"] = Variant<Any>("bredr")
            adapter1.SetDiscoveryFilter(filter)
            adapter1.StartDiscovery()

            bondLogger.info("Started BR/EDR discovery for classic device named '{}'", name)

            val devicePath = findClassicDeviceByName(objectManager, name, deadline)
            bondLogger.info("Found classic device at {}", devicePath)

            adapter1.StopDiscovery()

            val device1 = conn.getRemoteObject("org.bluez", devicePath, Device1::class.java)
            val properties = conn.getRemoteObject("org.bluez", devicePath, Properties::class.java)

            if (properties.Get<Boolean>("org.bluez.Device1", "Paired")) {
                bondLogger.info("Classic device already paired")
            } else {
                bondLogger.info("Initiating classic pairing")
                device1.Pair()
                waitForPaired(properties, deadline)
            }

            val address: String = properties.Get("org.bluez.Device1", "Address")
            bondLogger.info("Classic bond complete: {}", address)
            address
        } finally {
            try {
                adapter1.StopDiscovery()
            } catch (_: Exception) {
                // ignore
            }
            try {
                agentManager.UnregisterAgent(DBusPath(agentPath))
            } catch (_: Exception) {
                // ignore; the agent will be released when the connection closes
            }
        }
    }
}

private class AutoAcceptAgent(
    agentPath: String,
    connection: DBusConnection
) : AbstractBluetoothObject(BluezDeviceType.AGENT, connection, agentPath), Agent1 {

    override fun getInterfaceClass(): Class<out DBusInterface> = Agent1::class.java

    override fun isRemote(): Boolean = false
    override fun getObjectPath(): String = dbusPath

    override fun Release() {
        bondLogger.debug("Agent released")
    }

    override fun RequestPinCode(device: DBusPath): String {
        bondLogger.info("Camera requested PIN code for {}", device.path)
        throw BluezRejectedException("PIN code entry is not supported by auto-accept agent")
    }

    override fun DisplayPinCode(device: DBusPath, pincode: String) {
        bondLogger.info("Camera displayed PIN code for {}: {}", device.path, pincode)
    }

    override fun RequestPasskey(device: DBusPath): UInt32 {
        bondLogger.info("Camera requested passkey for {}", device.path)
        throw BluezRejectedException("Passkey entry is not supported by auto-accept agent")
    }

    override fun DisplayPasskey(device: DBusPath, passkey: UInt32, entered: UInt16) {
        bondLogger.info(
            "Camera displayed passkey for {}: {} (entered: {})",
            device.path,
            String.format("%06d", passkey.toInt()),
            entered
        )
    }

    override fun RequestConfirmation(device: DBusPath, passkey: UInt32) {
        bondLogger.info(
            "Auto-confirming classic pairing for {} with passkey {}",
            device.path,
            String.format("%06d", passkey.toInt())
        )
    }

    override fun RequestAuthorization(device: DBusPath) {
        bondLogger.info("Auto-authorizing classic pairing for {}", device.path)
    }

    override fun AuthorizeService(device: DBusPath, uuid: String) {
        bondLogger.info("Auto-authorizing service {} for {}", uuid, device.path)
    }

    override fun Cancel() {
        bondLogger.debug("Agent cancel received")
    }
}

private fun findClassicDeviceByName(objectManager: ObjectManager, name: String, deadline: Long): String {
    while (System.currentTimeMillis() < deadline) {
        val objects = objectManager.GetManagedObjects()
        for ((path, interfaces) in objects) {
            val deviceProps = interfaces["org.bluez.Device1"] ?: continue
            val deviceName = deviceProps["Name"]?.value as? String ?: continue
            if (deviceName == name) {
                return path.path
            }
        }
        Thread.sleep(500)
    }
    throw TimeoutException("Classic device '$name' not found within timeout")
}

private fun waitForPaired(properties: Properties, deadline: Long) {
    while (System.currentTimeMillis() < deadline) {
        if (properties.Get<Boolean>("org.bluez.Device1", "Paired")) {
            return
        }
        Thread.sleep(500)
    }
    throw TimeoutException("Classic pairing did not complete within timeout")
}
