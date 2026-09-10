package ai.routin.mytoken.feature.home

import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.model.UsageSnapshot
import ai.routin.mytoken.domain.usage.RefreshStatus
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import java.time.Instant
import java.util.UUID
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w400dp-h1100dp")
class ModelChipDetailTest {
    @get:Rule val composeRule = createComposeRule()

    @Test
    fun detailShowsVolcenginePlanFieldsAndCopyableModelChips() {
        val id = UUID.randomUUID()
        val credential = Credential(
            id = id,
            providerId = ProviderId.Volcengine,
            credentialKind = CredentialKind.AccessKeyPair,
            name = "火山方舟",
        )
        val snapshot = UsageSnapshot(
            credentialId = id,
            fetchedAt = Instant.parse("2026-09-10T08:00:00Z"),
            metrics = emptyList(),
            planName = "medium Plan",
            subscriptionStartAt = Instant.parse("2026-08-01T00:00:00Z"),
            subscriptionEndAt = Instant.parse("2026-09-01T00:00:00Z"),
            statusText = "Running",
            billingMode = "自动续费",
            allowedModels = listOf("ark-code-latest", "glm-5.3"),
        )

        composeRule.setContent {
            MaterialTheme {
                CredentialDetailScreen(
                    card = CredentialCardUi(
                        credential = credential,
                        status = RefreshStatus.Ready,
                        snapshot = snapshot,
                        isStale = false,
                        error = null,
                        freshness = Freshness(FreshnessLevel.JUST_NOW, "刚刚更新"),
                    ),
                    onBack = {},
                    onRefresh = {},
                    onEdit = {},
                    onDelete = {},
                )
            }
        }

        composeRule.onNodeWithText("自动续费").performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithText("Running").performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithText("ark-code-latest").performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithContentDescription("复制模型 ID glm-5.3").performScrollTo()
        composeRule.onNodeWithContentDescription("复制模型 ID glm-5.3").performClick()
        composeRule.onNodeWithContentDescription("已复制模型 ID glm-5.3").assertIsDisplayed()
    }
}
