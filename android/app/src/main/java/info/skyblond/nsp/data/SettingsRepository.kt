package info.skyblond.nsp.data

import android.content.Context
import android.content.SharedPreferences

/**
 * Lightweight persistence for paired cameras. Stores a JSON string per camera.
 */
class SettingsRepository(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun loadSavedCameras(): List<PairedCamera> {
        return prefs.getStringSet(KEY_CAMERAS, emptySet())?.map {
            PairedCamera.fromJson(it)
        }?.sortedBy { it.name } ?: emptyList()
    }

    fun saveCamera(camera: PairedCamera) {
        val current = loadSavedCameras().toMutableList()
        // The camera name is the stable identifier; the BLE address is random and changes
        // between sessions, so replace any existing entry with the same name.
        current.removeAll { it.name == camera.name }
        current.add(camera)
        store(current)
    }

    fun removeCamera(camera: PairedCamera) {
        val current = loadSavedCameras().toMutableList()
        current.removeAll { it.name == camera.name }
        store(current)
    }

    private fun store(cameras: List<PairedCamera>) {
        prefs.edit()
            .putStringSet(KEY_CAMERAS, cameras.map { it.toJson() }.toSet())
            .apply()
    }

    companion object {
        private const val PREFS_NAME = "nsg_camera_prefs"
        private const val KEY_CAMERAS = "paired_cameras"
    }
}
