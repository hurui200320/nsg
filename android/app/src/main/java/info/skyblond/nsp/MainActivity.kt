package info.skyblond.nsp

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import info.skyblond.nsp.service.ConnectionState
import info.skyblond.nsp.ui.DiscoveredCameraDialog
import info.skyblond.nsp.ui.MainViewModel
import info.skyblond.nsp.ui.PermissionHandler
import info.skyblond.nsp.ui.BluetoothEnableGate
import info.skyblond.nsp.ui.SavedCameraDialog
import info.skyblond.nsp.ui.theme.NikonSmartGPSTheme

class MainActivity : ComponentActivity() {

    private val viewModel: MainViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            NikonSmartGPSTheme {
                PermissionHandler {
                    BluetoothEnableGate {
                        MainScreen(viewModel = viewModel)
                    }
                }
            }
        }
    }

    override fun onStart() {
        super.onStart()
        viewModel.startAndBindService()
    }

    override fun onStop() {
        super.onStop()
        viewModel.unbindService()
    }
}

@Composable
private fun MainScreen(viewModel: MainViewModel) {
    val uiState by viewModel.uiState.collectAsState()

    Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = "Nikon Smart GPS",
                style = MaterialTheme.typography.headlineMedium
            )
            Text(
                text = "Status: ${uiState.connectionState.label}",
                style = MaterialTheme.typography.bodyLarge
            )
            Text(
                text = "Service bound: ${uiState.serviceBound}",
                style = MaterialTheme.typography.bodySmall
            )

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = "Recent events:",
                style = MaterialTheme.typography.titleMedium
            )
            if (uiState.lastEvents.isEmpty()) {
                Text(text = "No events yet", style = MaterialTheme.typography.bodyMedium)
            } else {
                uiState.lastEvents.forEach { event ->
                    Text(
                        text = "• $event",
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            Button(
                onClick = { viewModel.onPairClicked() },
                modifier = Modifier.fillMaxWidth(),
                enabled = uiState.connectionState !is ConnectionState.Scanning
            ) {
                Text("Pair new camera")
            }
            Button(
                onClick = { viewModel.onConnectClicked() },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Connect to saved camera")
            }
            Button(
                onClick = { viewModel.onSendClicked() },
                modifier = Modifier.fillMaxWidth(),
                enabled = uiState.connectionState is ConnectionState.Ready
            ) {
                Text("Send fake GPS")
            }
            Button(
                onClick = { viewModel.onDisconnectClicked() },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Disconnect")
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
            onDismiss = { viewModel.onDismissSavedDialog() }
        )
    }
}
