package info.skyblond.nsp.ui

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import info.skyblond.nsp.data.DiscoveredCamera
import info.skyblond.nsp.data.PairedCamera

@Composable
fun DiscoveredCameraDialog(
    cameras: List<DiscoveredCamera>,
    onSelect: (DiscoveredCamera) -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Select camera to pair") },
        text = {
            LazyColumn {
                items(cameras, key = { it.address }) { camera ->
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 4.dp),
                        onClick = { onSelect(camera) }
                    ) {
                        Text(
                            text = "${camera.name}\n${camera.address}",
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.padding(16.dp)
                        )
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        }
    )
}

@Composable
fun SavedCameraDialog(
    cameras: List<PairedCamera>,
    onSelect: (PairedCamera) -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Select saved camera") },
        text = {
            LazyColumn {
                items(cameras, key = { it.address }) { camera ->
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 4.dp),
                        onClick = { onSelect(camera) }
                    ) {
                        Text(
                            text = "${camera.name}\n${camera.address}",
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.padding(16.dp)
                        )
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        }
    )
}
