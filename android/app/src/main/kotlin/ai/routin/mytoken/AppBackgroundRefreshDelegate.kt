package ai.routin.mytoken

import ai.routin.mytoken.core.refresh.BackgroundRefreshDelegate
import ai.routin.mytoken.core.refresh.RefreshOutcome
import ai.routin.mytoken.domain.usage.RefreshStatus
import java.time.Clock
import kotlinx.coroutines.flow.first

/**
 * Background refresh delegate wired to the same [AppGraph] the foreground uses.
 * Reuses the shared [RefreshCredentialsUseCase] instance, so a background pass and
 * an in-app refresh can never duplicate requests: the use case's per-credential
 * states and concurrency limits are shared.
 */
class AppBackgroundRefreshDelegate(
    private val graph: AppGraph,
    private val clock: Clock = Clock.systemUTC(),
) : BackgroundRefreshDelegate {

    override suspend fun refreshAll(): RefreshOutcome {
        graph.refreshUseCase.refreshAll()

        val credentials = graph.credentialRepository.observeCredentials()
            .first()
            .filter { it.isEnabled }
        val states = graph.refreshUseCase.states.value
        val anyFailed = credentials.any { states[it.id]?.status == RefreshStatus.Failed }

        val now = clock.instant().toEpochMilli()
        if (anyFailed) {
            graph.refreshStatusStore.recordFailure(now)
        } else {
            graph.refreshStatusStore.recordSuccess(now)
        }

        // Threshold / invalid-credential alerts are evaluated after every completed
        // background pass; notifications degrade silently without permission.
        graph.usageAlertDispatcher.dispatchAfterRefresh()

        return if (anyFailed) RefreshOutcome.Failed else RefreshOutcome.Succeeded
    }
}
