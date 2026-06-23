package info.skyblond.nsp.ble

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.time.ZoneOffset
import java.time.ZonedDateTime
import kotlin.math.absoluteValue
import kotlin.random.Random

/**
 * Generates a fake 41-byte GEO payload for protocol debugging.
 */
object GeoPayloadGenerator {

    private const val HEADER: Short = 0x007F

    fun buildFake(): ByteArray {
        val lat = Random.nextDouble(-90.0, 90.0)
        val lon = Random.nextDouble(-180.0, 180.0)
        val alt = Random.nextInt(0, 5000)
        val satellites = Random.nextInt(3, 13)
        val now = ZonedDateTime.now(ZoneOffset.UTC)

        val latCoord = decimalToNikon(lat, 'N', 'S')
        val lonCoord = decimalToNikon(lon, 'E', 'W')

        val buffer = ByteBuffer.allocate(41).order(ByteOrder.LITTLE_ENDIAN)
        buffer.putShort(HEADER)
        buffer.put(latCoord.direction.code.toByte())
        buffer.put(latCoord.degrees.toByte())
        buffer.put(latCoord.minutes.toByte())
        buffer.put(latCoord.submin1.toByte())
        buffer.put(latCoord.submin2.toByte())
        buffer.put(lonCoord.direction.code.toByte())
        buffer.put(lonCoord.degrees.toByte())
        buffer.put(lonCoord.minutes.toByte())
        buffer.put(lonCoord.submin1.toByte())
        buffer.put(lonCoord.submin2.toByte())
        buffer.put(satellites.toByte())
        buffer.put('P'.code.toByte()) // altitude ref = positive
        buffer.putShort(alt.toShort())
        // Embedded 7-byte time: year LE, month, day, hour, minute, second
        buffer.putShort(now.year.toShort())
        buffer.put(now.monthValue.toByte())
        buffer.put(now.dayOfMonth.toByte())
        buffer.put(now.hour.toByte())
        buffer.put(now.minute.toByte())
        buffer.put(now.second.toByte())
        buffer.put(Random.nextInt(0, 100).toByte()) // subseconds
        buffer.put(0x01.toByte()) // valid
        buffer.put("WGS-84".toByteArray(Charsets.US_ASCII))
        // 10 bytes padding
        repeat(10) { buffer.put(0x00.toByte()) }

        return buffer.array()
    }

    private data class DirectionalCoordinate(
        val direction: Char,
        val degrees: Int,
        val minutes: Int,
        val submin1: Int,
        val submin2: Int
    )

    private fun decimalToNikon(
        decimal: Double,
        positiveDirection: Char,
        negativeDirection: Char
    ): DirectionalCoordinate {
        val direction = if (decimal < 0) negativeDirection else positiveDirection
        val abs = decimal.absoluteValue
        val degrees = abs.toInt()
        val minutesFull = (abs - degrees) * 60.0
        val minutes = minutesFull.toInt()
        val submin1Full = (minutesFull - minutes) * 100.0
        val submin1 = submin1Full.toInt()
        val submin2Full = (submin1Full - submin1) * 100.0
        val submin2 = submin2Full.toInt()
        return DirectionalCoordinate(
            direction = direction,
            degrees = degrees,
            minutes = minutes,
            submin1 = submin1,
            submin2 = submin2
        )
    }
}
