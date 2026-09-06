package info.skyblond.nsp

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import info.skyblond.nsp.data.SettingsRepository
import info.skyblond.nsp.service.ConnectionState
import info.skyblond.nsp.ui.DiscoveredCameraDialog
import info.skyblond.nsp.ui.MainViewModel
import info.skyblond.nsp.ui.PermissionHandler
import info.skyblond.nsp.ui.RequiredPermissions
import info.skyblond.nsp.ui.BluetoothEnableGate
import info.skyblond.nsp.ui.SavedCameraDialog
import info.skyblond.nsp.ui.theme.NikonSmartGPSTheme
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : ComponentActivity() {

    private val viewModel: MainViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            NikonSmartGPSTheme {
                PermissionHandler(
                    onPermissionsGranted = { viewModel.startAndBindService() }
                ) {
                    BluetoothEnableGate {
                        MainScreen(viewModel = viewModel)
                    }
                }
            }
        }
    }

    override fun onStart() {
        super.onStart()
        // Android 14+ requires the runtime permissions to be held before the
        // foreground service can call startForeground() with the connectedDevice
        // / location types; starting it without them crashes (SecurityException).
        if (RequiredPermissions.allGranted(this)) {
            viewModel.startAndBindService()
        }
    }

    override fun onStop() {
        super.onStop()
        viewModel.unbindService()
    }
}

@Composable
private fun MainScreen(viewModel: MainViewModel) {
    val uiState by viewModel.uiState.collectAsState()
    val context = LocalContext.current
    val settingsRepo = remember { SettingsRepository(context) }
    var spoofName by remember { mutableStateOf(settingsRepo.spoofControllerName() ?: "") }
    var fixedDeviceId by remember { mutableStateOf(settingsRepo.fixedDeviceIdRaw() ?: "") }
    var showAdvancedSettingsPage by remember { mutableStateOf(false) }
    val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    val batteryExempt = powerManager.isIgnoringBatteryOptimizations(context.packageName)
    val onBatteryClick = {
        val intent = Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:${context.packageName}")
        )
        try {
            context.startActivity(intent)
        } catch (_: Exception) {
            context.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
    }
    val onSpoofNameChange: (String) -> Unit = { value ->
        val sanitized = value.filter { c -> c.code < 128 }.take(32)
        spoofName = sanitized
        settingsRepo.setSpoofControllerName(sanitized)
    }
    val onFixedDeviceIdChange: (String) -> Unit = { value ->
        val sanitized = value.filter { c -> c.code < 128 }.take(16)
        fixedDeviceId = sanitized
        settingsRepo.setFixedDeviceId(sanitized)
    }

    // Check the battery-optimization exemption on startup and request it if missing.
    LaunchedEffect(Unit) {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        if (!pm.isIgnoringBatteryOptimizations(context.packageName)) {
            val intent = Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:${context.packageName}")
            )
            try {
                context.startActivity(intent)
            } catch (_: Exception) {
                context.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            }
        }
    }

    val connected = uiState.connectionState is ConnectionState.Ready ||
        uiState.connectionState is ConnectionState.Busy
    val connectionInProgress = uiState.connectionState is ConnectionState.Scanning ||
        uiState.connectionState is ConnectionState.Connecting ||
        uiState.connectionState is ConnectionState.Discovering ||
        uiState.connectionState is ConnectionState.Pairing ||
        uiState.connectionState is ConnectionState.Bonding
    val pairingButtonsEnabled = !connected && !connectionInProgress

    // BackHandler: the system back key returns from the advanced-settings page to the main screen
    BackHandler(enabled = showAdvancedSettingsPage) {
        showAdvancedSettingsPage = false
    }

    if (showAdvancedSettingsPage) {
        AdvancedSettingsPage(
            spoofName = spoofName,
            onSpoofNameChange = onSpoofNameChange,
            fixedDeviceId = fixedDeviceId,
            onFixedDeviceIdChange = onFixedDeviceIdChange,
            onBack = { showAdvancedSettingsPage = false }
        )
        return
    }

    Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
        BoxWithConstraints(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(12.dp)
        ) {
            val isLandscape = maxWidth > maxHeight
            if (isLandscape) {
                Row(
                    modifier = Modifier.fillMaxSize(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Column(
                        modifier = Modifier
                            .width(230.dp)
                            .fillMaxHeight(),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        StatusSection(uiState = uiState, compact = true)
                        BatteryButton(batteryExempt = batteryExempt, onClick = onBatteryClick)
                    }
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight(),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        TitleRow(
                            onOpenAdvanced = { showAdvancedSettingsPage = true }
                        )
                        EventsSection(uiState = uiState, modifier = Modifier.weight(1f))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            ActionButton(
                                text = stringResource(R.string.btn_pair_new_camera),
                                enabled = pairingButtonsEnabled,
                                loading = uiState.connectionState is ConnectionState.Scanning,
                                onClick = { viewModel.onPairClicked() },
                                modifier = Modifier.weight(1f)
                            )
                            ActionButton(
                                text = stringResource(R.string.btn_connect_saved),
                                enabled = pairingButtonsEnabled,
                                loading = uiState.connectionState is ConnectionState.Connecting ||
                                    uiState.connectionState is ConnectionState.Discovering ||
                                    uiState.connectionState is ConnectionState.Pairing ||
                                    uiState.connectionState is ConnectionState.Bonding,
                                onClick = { viewModel.onConnectClicked() },
                                modifier = Modifier.weight(1f)
                            )
                            ActionButton(
                                text = stringResource(R.string.btn_send_gps),
                                enabled = uiState.connectionState is ConnectionState.Ready,
                                onClick = { viewModel.onSendClicked() },
                                modifier = Modifier.weight(1f)
                            )
                            ActionButton(
                                text = stringResource(R.string.action_disconnect),
                                enabled = connected || connectionInProgress,
                                onClick = { viewModel.onDisconnectClicked() },
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }
                }
            } else {
                Column(
                    modifier = Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    TitleRow(
                        onOpenAdvanced = { showAdvancedSettingsPage = true }
                    )
                    StatusSection(uiState = uiState)
                    EventsSection(
                        uiState = uiState,
                        modifier = Modifier
                            .weight(1f)
                            .heightIn(min = 56.dp)
                    )
                    Column(
                        modifier = Modifier.verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        ActionButton(
                            text = stringResource(R.string.btn_pair_new_camera),
                            enabled = pairingButtonsEnabled,
                            loading = uiState.connectionState is ConnectionState.Scanning,
                            onClick = { viewModel.onPairClicked() },
                            modifier = Modifier.fillMaxWidth()
                        )
                        ActionButton(
                            text = stringResource(R.string.btn_connect_saved),
                            enabled = pairingButtonsEnabled,
                            loading = uiState.connectionState is ConnectionState.Connecting ||
                                uiState.connectionState is ConnectionState.Discovering ||
                                uiState.connectionState is ConnectionState.Pairing ||
                                uiState.connectionState is ConnectionState.Bonding,
                            onClick = { viewModel.onConnectClicked() },
                            modifier = Modifier.fillMaxWidth()
                        )
                        ActionButton(
                            text = stringResource(R.string.btn_send_gps_now),
                            enabled = uiState.connectionState is ConnectionState.Ready,
                            onClick = { viewModel.onSendClicked() },
                            modifier = Modifier.fillMaxWidth()
                        )
                        ActionButton(
                            text = stringResource(R.string.action_disconnect),
                            enabled = connected || connectionInProgress,
                            onClick = { viewModel.onDisconnectClicked() },
                            modifier = Modifier.fillMaxWidth()
                        )
                        BatteryButton(batteryExempt = batteryExempt, onClick = onBatteryClick)
                    }
                }
            }
        }
    }

    if (uiState.showDiscoveredDialog) {
        DiscoveredCameraDialog(
            cameras = uiState.discoveredCameras,
            onSelect = { viewModel.onDiscoveredCameraSelected(it) },
            onDismiss = { viewModel.onDismissDiscoveredDialog() }
        )
    }

            if (uiState.showSavedDialog) {
                SavedCameraDialog(
                    cameras = uiState.savedCameras,
                    onSelect = { viewModel.onSavedCameraSelected(it) },
                    onAutoExtract = { viewModel.onAutoExtractClicked(it) },
                    onSetDefault = { viewModel.onSetDefaultCamera(it) },
                    onDelete = { viewModel.onDeleteCamera(it) },
                    defaultCameraName = uiState.defaultCameraName,
                    onDismiss = { viewModel.onDismissSavedDialog() }
                )
            }
}

@Composable
private fun StatusSection(uiState: MainViewModel.UiState, compact: Boolean = false) {
    val context = LocalContext.current
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            text = stringResource(R.string.status_label, uiState.connectionState.label(context)),
            style = MaterialTheme.typography.bodyLarge
        )
        Text(
            text = stringResource(R.string.status_service_running, uiState.serviceBound),
            style = MaterialTheme.typography.bodySmall
        )
        val gps = uiState.gpsState
        Text(
            text = buildString {
                append(stringResource(R.string.gps_label))
                when {
                    !gps.enabled -> append(stringResource(R.string.gps_off_auto_start))
                    !gps.hasFix -> append(stringResource(R.string.gps_locating))
                    else -> append(
                        String.format(
                            Locale.US,
                            "%.5f, %.5f +/-%dm",
                            gps.latitude ?: 0.0,
                            gps.longitude ?: 0.0,
                            gps.accuracyMeters?.toInt() ?: 0
                        )
                    )
                }
                gps.lastSentTime?.let {
                    append(stringResource(R.string.gps_sent_at, formatTime(it)))
                }
            },
            style = MaterialTheme.typography.bodySmall,
            maxLines = if (compact) 3 else 2,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun EventsSection(uiState: MainViewModel.UiState, modifier: Modifier = Modifier) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            text = stringResource(R.string.events_title),
            style = MaterialTheme.typography.titleMedium
        )
        if (uiState.lastEvents.isEmpty()) {
            Text(
                text = stringResource(R.string.events_empty),
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.heightIn(min = 48.dp)
            )
        } else {
            LazyColumn(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
            ) {
                items(uiState.lastEvents) { event ->
                    Text(
                        text = "• $event",
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }
        }
    }
}

@Composable
private fun TitleRow(onOpenAdvanced: () -> Unit) {
    var menuOpen by remember { mutableStateOf(false) }
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = stringResource(R.string.app_name),
            style = MaterialTheme.typography.titleLarge,
            modifier = Modifier.weight(1f)
        )
        Box {
            IconButton(onClick = { menuOpen = true }) {
                Icon(
                    imageVector = Icons.Filled.MoreVert,
                    contentDescription = stringResource(R.string.cd_more)
                )
            }
            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.menu_advanced_settings_hint)) },
                    onClick = {
                        menuOpen = false
                        onOpenAdvanced()
                    }
                )
            }
        }
    }
}

/** Standalone advanced-settings page with the two input fields and a back button. */
@Composable
private fun AdvancedSettingsPage(
    spoofName: String,
    onSpoofNameChange: (String) -> Unit,
    fixedDeviceId: String,
    onFixedDeviceIdChange: (String) -> Unit,
    onBack: () -> Unit
) {
    Surface(
        modifier = Modifier
            .fillMaxSize(),
        color = MaterialTheme.colorScheme.background
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = onBack) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                        contentDescription = stringResource(R.string.cd_back)
                    )
                }
                Text(
                    text = stringResource(R.string.advanced_settings_title),
                    style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier.weight(1f)
                )
            }
            Text(
                text = stringResource(R.string.advanced_settings_description),
                style = MaterialTheme.typography.bodySmall
            )
            SpoofNameField(
                value = spoofName,
                onValueChange = onSpoofNameChange,
                modifier = Modifier.fillMaxWidth()
            )
            FixedDeviceIdField(
                value = fixedDeviceId,
                onValueChange = onFixedDeviceIdChange,
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
}

@Composable
private fun SpoofNameField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier
) {
        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            label = { Text(stringResource(R.string.spoof_name_label)) },
            placeholder = { Text(stringResource(R.string.spoof_name_placeholder)) },
            supportingText = {
                Text(
                    stringResource(R.string.spoof_name_support)
                )
            },
        singleLine = true,
        modifier = modifier
    )
}

@Composable
private fun FixedDeviceIdField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier
) {
        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            label = { Text(stringResource(R.string.fixed_device_id_label)) },
            placeholder = { Text(stringResource(R.string.fixed_device_id_placeholder)) },
            supportingText = {
                Text(
                    stringResource(R.string.fixed_device_id_support)
                )
            },
        singleLine = true,
        modifier = modifier
    )
}

@Composable
private fun ActionButton(
    text: String,
    enabled: Boolean,
    loading: Boolean = false,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Button(onClick = onClick, enabled = enabled, modifier = modifier) {
        if (loading) {
            CircularProgressIndicator(
                modifier = Modifier.size(20.dp),
                strokeWidth = 2.dp,
                color = MaterialTheme.colorScheme.onPrimary
            )
        } else {
            Text(text)
        }
    }
}

@Composable
private fun BatteryButton(batteryExempt: Boolean, onClick: () -> Unit) {
    Button(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        Text(
            if (batteryExempt) {
                stringResource(R.string.battery_exempt)
            } else {
                stringResource(R.string.battery_not_exempt)
            }
        )
    }
}

private fun formatTime(epochMillis: Long): String =
    SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date(epochMillis))
