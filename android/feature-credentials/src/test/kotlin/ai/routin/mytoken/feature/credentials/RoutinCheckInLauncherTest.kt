package ai.routin.mytoken.feature.credentials

import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.CredentialMetadataKey
import ai.routin.mytoken.domain.model.ProviderId
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.UUID

/**
 * URL construction for the Routin check-in launcher. `launch()` is never invoked
 * against a real activity — only its silent-degradation path is pinned.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class RoutinCheckInLauncherTest {

    private fun routinCredential(metadata: Map<CredentialMetadataKey, String> = emptyMap()) = Credential(
        id = UUID.fromString("00000000-0000-0000-0000-000000000001"),
        providerId = ProviderId.Routin,
        credentialKind = CredentialKind.BearerApiKey,
        name = "Routin 主号",
        metadata = metadata,
    )

    // ---- URL construction -----------------------------------------------------

    @Test
    fun withoutWebsiteUrlUsesOfficialCheckInPage() {
        assertEquals(
            "https://routin.ai/dashboard/lottery",
            RoutinCheckInLauncher.checkInUrl(routinCredential()),
        )
    }

    @Test
    fun websiteUrlMetadataWins() {
        val credential = routinCredential(
            mapOf(CredentialMetadataKey.WebsiteURL to "https://custom.example.com/dashboard/lottery"),
        )
        assertEquals(
            "https://custom.example.com/dashboard/lottery",
            RoutinCheckInLauncher.checkInUrl(credential),
        )
    }

    @Test
    fun nonHttpsWebsiteUrlFallsBackToOfficialPage() {
        listOf(
            "http://custom.example.com/dashboard",
            "javascript:alert(1)",
            "not a url",
            "",
        ).forEach { raw ->
            val credential = routinCredential(mapOf(CredentialMetadataKey.WebsiteURL to raw))
            assertEquals(
                "websiteURL=$raw",
                "https://routin.ai/dashboard/lottery",
                RoutinCheckInLauncher.checkInUrl(credential),
            )
        }
    }

    // ---- non-Routin credentials and silent degradation --------------------------

    @Test
    fun nonRoutinCredentialsNeverLaunch() {
        val credential = Credential(
            id = UUID.fromString("00000000-0000-0000-0000-000000000002"),
            providerId = ProviderId.DeepSeek,
            credentialKind = CredentialKind.ApiKey,
            name = "DeepSeek",
        )
        val context = ApplicationProvider.getApplicationContext<Context>()
        assertFalse(RoutinCheckInLauncher.launch(context, credential))
    }

    @Test
    fun launchForRoutinCredentialDispatchesCustomTabWithoutCrashing() {
        // Robolectric has no real Custom Tabs provider; the launcher must not throw
        // and must attempt the (recorded, never executed) Custom Tabs launch.
        val context = ApplicationProvider.getApplicationContext<Context>()
        assertTrue(RoutinCheckInLauncher.launch(context, routinCredential()))
    }
}
