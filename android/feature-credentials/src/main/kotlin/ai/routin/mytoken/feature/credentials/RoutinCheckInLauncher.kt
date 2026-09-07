package ai.routin.mytoken.feature.credentials

import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialMetadataKey
import ai.routin.mytoken.domain.model.ProviderId
import android.content.ActivityNotFoundException
import android.content.Context
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import java.net.URI

/**
 * Opens the official Routin check-in page in a Custom Tab. The launcher is strictly a
 * viewer: it never reads the page DOM, passwords, verification codes or cookies, and
 * never writes web content to logs. The page's own authentication state decides what
 * the user can do there (same contract as the macOS `RoutinWebSession`).
 */
object RoutinCheckInLauncher {

    /** Official Routin check-in page, mirroring the macOS `RoutinWebSession.lotteryURL`. */
    const val DEFAULT_CHECK_IN_URL = "https://routin.ai/dashboard/lottery"

    /**
     * Resolves the check-in URL: the credential's `websiteURL` metadata when it is a
     * valid https URL, otherwise the official Routin check-in page.
     */
    fun checkInUrl(credential: Credential): String {
        val custom = credential.metadata[CredentialMetadataKey.WebsiteURL]
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: return DEFAULT_CHECK_IN_URL
        val parsed = runCatching { URI(custom) }.getOrNull() ?: return DEFAULT_CHECK_IN_URL
        return if (parsed.scheme == "https") parsed.toString() else DEFAULT_CHECK_IN_URL
    }

    /** Opens the check-in URL in a Custom Tab; returns false on silent degradation. */
    fun launch(context: Context, credential: Credential): Boolean {
        if (credential.providerId != ProviderId.Routin) return false
        return try {
            val intent = CustomTabsIntent.Builder()
                .setShowTitle(true)
                .build()
            // Safe from any context (worker/service code paths included).
            intent.intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            intent.launchUrl(context, Uri.parse(checkInUrl(credential)))
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: IllegalArgumentException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }
}
