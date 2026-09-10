package ai.routin.mytoken.feature.home

import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.model.UsageMetric
import ai.routin.mytoken.domain.model.UsageMetricHealthState
import ai.routin.mytoken.domain.model.UsageMetricPresentation
import ai.routin.mytoken.domain.model.UsageMetricSemantic
import ai.routin.mytoken.domain.model.UsageMetricUnit
import ai.routin.mytoken.domain.model.UsageSnapshot
import ai.routin.mytoken.domain.usage.RefreshStatus
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollTo
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w400dp-h1200dp")
class CommandCodeDetailScreenTest {
    @get:Rule val composeRule = createComposeRule()

    @Test
    fun detailUsesCommandCodeLayoutAndAccountSections() {
        val credential = Credential(
            id = UUID.randomUUID(),
            providerId = ProviderId.CommandCode,
            credentialKind = CredentialKind.BearerApiKey,
            name = "邵",
        )
        val metrics = listOf(
            metric("five-hour", "5 小时", "2.45", "14", "11.55"),
            metric("weekly", "周", "2.45", "35", "32.55"),
            metric("credit-progress", "月", "2.45", "70", "67.55"),
            valueMetric("purchased-remaining", "购买剩余", "0"),
            valueMetric("free-remaining", "赠送剩余", "0"),
            valueMetric("request-count", "累计请求", "474", UsageMetricUnit.Request),
        )
        val card = CredentialCardUi(
            credential = credential,
            status = RefreshStatus.Ready,
            snapshot = UsageSnapshot(
                credentialId = credential.id,
                fetchedAt = Instant.parse("2026-09-10T14:32:22Z"),
                metrics = metrics,
                planName = "GOAT",
                subscriptionStartAt = Instant.parse("2026-09-01T00:00:00Z"),
                subscriptionEndAt = Instant.parse("2026-10-01T00:00:00Z"),
                statusText = "有效",
                billingMode = "active",
                usageKind = "periodic",
                allowedModels = listOf("claude-sonnet-5", "deepseek-v4-flash"),
            ),
            isStale = false,
            error = null,
            freshness = Freshness(FreshnessLevel.JUST_NOW, "刚刚更新"),
        )

        composeRule.setContent {
            MaterialTheme {
                CredentialDetailScreen(
                    card = card,
                    onBack = {},
                    onRefresh = {},
                    onEdit = {},
                    onDelete = {},
                )
            }
        }

        listOf("5 小时", "周", "月", "购买剩余", "赠送剩余").forEach { label ->
            composeRule.onNodeWithText(label).assertIsDisplayed()
        }
        listOf("套餐状态", "订阅与周期", "账户与模型").forEach { label ->
            composeRule.onNodeWithText(label).performScrollTo().assertIsDisplayed()
        }
        listOf("有效", "周期订阅", "claude-sonnet-5").forEach { value ->
            composeRule.onNodeWithText(value).performScrollTo().assertIsDisplayed()
        }
    }

    private fun metric(
        id: String,
        label: String,
        used: String,
        limit: String,
        remaining: String,
    ) = UsageMetric(
        id = id,
        label = label,
        used = BigDecimal(used),
        limit = BigDecimal(limit),
        remaining = BigDecimal(remaining),
        unit = UsageMetricUnit.Currency,
        presentation = UsageMetricPresentation.Progress,
        semantic = UsageMetricSemantic.UsedQuota,
        currencyCode = "$",
        healthState = UsageMetricHealthState.Normal,
    )

    private fun valueMetric(
        id: String,
        label: String,
        value: String,
        unit: UsageMetricUnit = UsageMetricUnit.Currency,
    ) = UsageMetric(
        id = id,
        label = label,
        value = BigDecimal(value),
        unit = unit,
        presentation = UsageMetricPresentation.Value,
        semantic = UsageMetricSemantic.Value,
        currencyCode = if (unit == UsageMetricUnit.Currency) "$" else null,
        healthState = UsageMetricHealthState.Normal,
    )
}
