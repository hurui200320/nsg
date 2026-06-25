package info.skyblond.nsg.protocol

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.time.ZoneOffset
import java.time.ZonedDateTime
import kotlin.math.absoluteValue

/**
 * Generates a 10-byte TIME payload.
 */
object TimePayloadGenerator {

    fun buildPackage(): ByteArray {
        val now = ZonedDateTime.now(ZoneOffset.UTC)

        val buffer = ByteBuffer.allocate(10).order(ByteOrder.LITTLE_ENDIAN)
        // Embedded 7-byte time: year LE, month, day, hour, minute, second
        buffer.putShort(now.year.toShort())
        buffer.put(now.monthValue.toByte())
        buffer.put(now.dayOfMonth.toByte())
        buffer.put(now.hour.toByte())
        buffer.put(now.minute.toByte())
        buffer.put(now.second.toByte())
        // daylight saving offset
        buffer.put(0)
        // timezone offset hours
        buffer.put(8)
        // timezone offset minutes
        buffer.put(0)


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
