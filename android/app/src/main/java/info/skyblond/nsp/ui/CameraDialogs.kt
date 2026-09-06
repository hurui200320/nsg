package info.skyblond.nsp.ui

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import info.skyblond.nsp.R
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
        title = { Text(stringResource(R.string.dialog_select_camera_to_pair)) },
        text = {
            if (cameras.isEmpty()) {
                Text(stringResource(R.string.dialog_no_camera_found))
            } else {
                LazyColumn {
                    items(cameras, key = { it.address }) { camera ->
                        Card(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 4.dp),
                            onClick = { onSelect(camera) }
                        ) {
                            Text(
                                text = buildString {
                                    append(camera.name)
                                    append("\n")
                                    append(camera.address)
                                    if (camera.manufacturerData != null) {
                                        append("\n[" + stringResource(R.string.dialog_already_paired_hint) + "]")
                                    }
                                },
                                style = MaterialTheme.typography.bodyMedium,
                                modifier = Modifier.padding(16.dp)
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.action_cancel))
            }
        }
    )
}

@Composable
fun SavedCameraDialog(
    cameras: List<PairedCamera>,
    onSelect: (PairedCamera) -> Unit,
    onAutoExtract: (PairedCamera) -> Unit,
    onSetDefault: (PairedCamera) -> Unit,
    onDelete: (PairedCamera) -> Unit,
    defaultCameraName: String?,
    onDismiss: () -> Unit
) {
    var pendingDelete by remember { mutableStateOf<PairedCamera?>(null) }
    AlertDialog(
        onDismissRequest = {
            pendingDelete = null
            onDismiss()
        },
        title = { Text(stringResource(R.string.dialog_select_saved_camera)) },
        text = {
            if (cameras.isEmpty()) {
                Text(stringResource(R.string.dialog_no_saved_cameras))
            } else {
                LazyColumn {
                    if (cameras.size > 1) {
                        item {
                            Text(
                                text = pluralStringResource(
                                    R.plurals.dialog_saved_count_hint,
                                    cameras.size,
                                    cameras.size
                                ),
                                style = MaterialTheme.typography.bodySmall
                            )
                        }
                    }
                    items(cameras, key = { it.address }) { camera ->
                        Card(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 4.dp)
                        ) {
                            val isDefault = defaultCameraName == camera.name
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(start = 12.dp, top = 16.dp, end = 12.dp, bottom = 8.dp),
                                verticalArrangement = Arrangement.spacedBy(2.dp),
                                horizontalAlignment = Alignment.CenterHorizontally
                            ) {
                                Text(
                                    text = "${camera.name}\n${camera.address}",
                                    style = MaterialTheme.typography.bodyMedium,
                                    textAlign = TextAlign.Center
                                )
                                if (isDefault) {
                                        Text(
                                            text = stringResource(R.string.default_at_startup),
                                        style = MaterialTheme.typography.labelMedium,
                                        color = MaterialTheme.colorScheme.primary
                                    )
                                }
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.Center
                                ) {
                                    TextButton(onClick = { onSelect(camera) }) {
                                        Text(stringResource(R.string.action_connect))
                                    }
                                    TextButton(onClick = { onAutoExtract(camera) }) {
                                        Text(stringResource(R.string.action_auto_extract_id))
                                    }
                                    if (cameras.size > 1) {
                                        TextButton(onClick = { onSetDefault(camera) }) {
                                            Text(if (isDefault) stringResource(R.string.action_unset_default) else stringResource(R.string.action_set_default))
                                        }
                                    }
                                    TextButton(onClick = { pendingDelete = camera }) {
                                        Text(stringResource(R.string.action_delete))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                pendingDelete = null
                onDismiss()
            }) {
                Text(stringResource(R.string.action_cancel))
            }
        }
    )
    pendingDelete?.let { camera ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = { Text(stringResource(R.string.dialog_delete_camera_title)) },
            text = {
                Text(
                    stringResource(R.string.dialog_delete_camera_message, camera.name)
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    pendingDelete = null
                    onDelete(camera)
                }) {
                    Text(stringResource(R.string.action_delete))
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingDelete = null }) {
                    Text(stringResource(R.string.action_cancel))
                }
            }
        )
    }
}
