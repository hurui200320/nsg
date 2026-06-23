package info.skyblond.nsp.ui

import android.annotation.SuppressLint
import android.app.Application
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import androidx.core.content.ContextCompat
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import info.skyblond.nsp.data.DiscoveredCamera
import info.skyblond.nsp.data.PairedCamera
import info.skyblond.nsp.service.CameraConnectionService
import info.skyblond.nsp.service.ConnectionState
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.update

@SuppressLint("StaticFieldLeak")
class MainViewModel(application: Application) : AndroidViewModel(application) {

    private var service: CameraConnectionService? = null

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    private var startedService = false
    private val serviceJobs = mutableListOf<Job>()

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            val localBinder = binder as? CameraConnectionService.LocalBinder ?: return
            service = localBinder.service
            _uiState.update { it.copy(serviceBound = true) }
            collectServiceData()
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            service = null
            _uiState.update { it.copy(serviceBound = false) }
            serviceJobs.forEach { it.cancel() }
            serviceJobs.clear()
        }
    }

    fun startAndBindService() {
        val context = getApplication<Application>()
        if (!startedService) {
            ContextCompat.startForegroundService(
                context,
                Intent(context, CameraConnectionService::class.java)
            )
            startedService = true
        }
        context.bindService(
            Intent(context, CameraConnectionService::class.java),
            serviceConnection,
            Context.BIND_AUTO_CREATE
        )
    }

    fun unbindService() {
        val context = getApplication<Application>()
        try {
            service?.let { context.unbindService(serviceConnection) }
        } catch (_: IllegalArgumentException) {
            // already unbound
        }
    }

    private fun collectServiceData() {
        val svc = service ?: return
        serviceJobs.forEach { it.cancel() }
        serviceJobs.clear()

        svc.state
            .onEach { state -> _uiState.update { it.copy(connectionState = state) } }
            .launchIn(viewModelScope)
            .also { serviceJobs.add(it) }

        svc.discoveredCameras
            .onEach { list -> _uiState.update { it.copy(discoveredCameras = list) } }
            .launchIn(viewModelScope)
            .also { serviceJobs.add(it) }

        svc.savedCameras
            .onEach { list -> _uiState.update { it.copy(savedCameras = list) } }
            .launchIn(viewModelScope)
            .also { serviceJobs.add(it) }

        svc.events
            .onEach { message ->
                _uiState.update { state ->
                    val events = (listOf(message) + state.lastEvents).take(5)
                    state.copy(lastEvents = events)
                }
            }
            .launchIn(viewModelScope)
            .also { serviceJobs.add(it) }
    }

    fun onPairClicked() {
        service?.startPairingScan()
        _uiState.update { it.copy(showDiscoveredDialog = true) }
    }

    fun onConnectClicked() {
        _uiState.update { it.copy(showSavedDialog = true) }
    }

    fun onSendClicked() {
        service?.sendFakeGeo()
    }

    fun onDisconnectClicked() {
        service?.disconnect()
    }

    fun onDiscoveredCameraSelected(camera: DiscoveredCamera) {
        service?.selectDiscoveredCamera(camera)
        _uiState.update { it.copy(showDiscoveredDialog = false) }
    }

    fun onSavedCameraSelected(camera: PairedCamera) {
        service?.connectToSavedCamera(camera)
        _uiState.update { it.copy(showSavedDialog = false) }
    }

    fun onDismissDiscoveredDialog() {
        service?.stopScan()
        _uiState.update { it.copy(showDiscoveredDialog = false) }
    }

    fun onDismissSavedDialog() {
        _uiState.update { it.copy(showSavedDialog = false) }
    }

    data class UiState(
        val serviceBound: Boolean = false,
        val connectionState: ConnectionState = ConnectionState.Idle,
        val discoveredCameras: List<DiscoveredCamera> = emptyList(),
        val savedCameras: List<PairedCamera> = emptyList(),
        val showDiscoveredDialog: Boolean = false,
        val showSavedDialog: Boolean = false,
        val lastEvents: List<String> = emptyList()
    )
}
