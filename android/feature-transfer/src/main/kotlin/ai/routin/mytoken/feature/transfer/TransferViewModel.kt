package ai.routin.mytoken.feature.transfer

import ai.routin.mytoken.domain.model.AppError
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** UI state machine for the scan → connect → preview → import flow. */
sealed interface TransferUiState {
    data object Idle : TransferUiState
    data object Connecting : TransferUiState
    data class PreviewReady(
        val preview: ImportPreview,
        val items: List<TransferImportItem>,
        val exportedAt: String
    ) : TransferUiState
    data object Importing : TransferUiState
    data class Completed(val summary: ImportSummary) : TransferUiState
    data class Failed(val message: String) : TransferUiState
}

/**
 * Drives the transfer import flow. The scanned QR content is consumed
 * immediately and never logged; only redacted state transitions are exposed.
 */
class TransferViewModel(
    private val repository: TransferRepository,
    private val payloadDecoder: (String) -> TransferQrCodePayload = { raw ->
        TransferQrCodePayload.decode(raw, java.time.Instant.now())
    }
) : ViewModel() {

    private val _state = MutableStateFlow<TransferUiState>(TransferUiState.Idle)
    val state: StateFlow<TransferUiState> = _state.asStateFlow()

    private var pendingPackage: TransferPackageV1? = null
    private var pendingPayload: TransferQrCodePayload? = null

    fun onQrCodeScanned(raw: String) {
        if (_state.value !is TransferUiState.Idle && _state.value !is TransferUiState.Failed) return
        _state.value = TransferUiState.Connecting
        viewModelScope.launch {
            val payload = try {
                payloadDecoder(raw)
            } catch (cause: Exception) {
                _state.value = TransferUiState.Failed(failureMessage(cause))
                return@launch
            }
            pendingPayload = payload
            val connected = repository.connect(payload)
            val encrypted = connected.getOrElse { cause ->
                _state.value = TransferUiState.Failed(failureMessage(cause))
                return@launch
            }
            val decrypted = repository.decrypt(encrypted)
            val packageData = decrypted.getOrElse { cause ->
                _state.value = TransferUiState.Failed(failureMessage(cause))
                return@launch
            }
            pendingPackage = packageData
            val preview = repository.preview(packageData)
            val items = runCatching { repository.previewItems(packageData) }.getOrDefault(emptyList())
            _state.value = TransferUiState.PreviewReady(
                preview = preview,
                items = items,
                exportedAt = packageData.exportedAt
            )
        }
    }

    fun confirmImport(conflictMode: ImportConflictMode) {
        val packageData = pendingPackage ?: run {
            _state.value = TransferUiState.Failed("nothing to import")
            return
        }
        _state.value = TransferUiState.Importing
        viewModelScope.launch {
            val result = repository.import(packageData, conflictMode)
            val summary = result.getOrElse { cause ->
                _state.value = TransferUiState.Failed(failureMessage(cause))
                return@launch
            }
            _state.value = TransferUiState.Completed(summary)
        }
    }

    /** User cancels before confirming; nothing has been written to storage. */
    fun cancel() {
        pendingPackage = null
        pendingPayload = null
        _state.value = TransferUiState.Idle
    }

    private fun failureMessage(cause: Throwable): String = when (cause) {
        is TransferQrCodePayloadException -> when (cause.reason) {
            TransferQrCodePayload.Reason.EXPIRED -> "迁移二维码已过期，请在 Mac 上重新生成"
            else -> "二维码内容无效，请扫描 MyToken 生成的迁移二维码"
        }
        is AppError.Network -> "无法连接 Mac，请确认两台设备在同一网络"
        is AppError.Authentication -> "连接验证失败，请在 Mac 上重新发起迁移"
        is AppError.Decode -> "传输内容格式无效"
        is AppError.Storage -> "导入存储失败，未保存任何更改"
        else -> "迁移失败，请重试"
    }
}
