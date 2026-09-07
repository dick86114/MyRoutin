package ai.routin.mytoken.feature.home

import ai.routin.mytoken.domain.model.AppError
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
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.Density
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w400dp-h1100dp")
class HomeScreenTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val now = Instant.parse("2026-09-07T12:00:00Z")

    /** Brings the first node whose text contains [text] fully into the visible viewport. */
    private fun scrollToText(text: String) {
        composeRule.onNodeWithText(text, substring = true).performScrollTo()
    }

    private class Callbacks {
        var openedCredentialId: UUID? = null
        var refreshedAll = 0
        var refreshedCredentialId: UUID? = null
        var toggledProvider: ProviderId? = null
        var importFromMac = 0
        var addedManually = 0
    }

    private fun credential(
        name: String,
        provider: ProviderId,
    ) = Credential(
        id = UUID.randomUUID(),
        providerId = provider,
        credentialKind = CredentialKind.ApiKey,
        name = name,
    )

    private fun progressMetric(
        id: String,
        label: String,
        used: Double,
        limit: Double,
        remaining: Double? = null,
        windowEnd: Instant? = null,
    ) = UsageMetric(
        id = id,
        label = label,
        used = BigDecimal.valueOf(used),
        limit = BigDecimal.valueOf(limit),
        remaining = remaining?.let { BigDecimal.valueOf(it) },
        unit = UsageMetricUnit.Token,
        presentation = UsageMetricPresentation.Progress,
        semantic = UsageMetricSemantic.UsedQuota,
        windowEnd = windowEnd,
        healthState = UsageMetricHealthState.Unknown,
    )

    private fun balanceMetric(value: Double) = UsageMetric(
        id = "balance",
        label = "余额",
        value = BigDecimal.valueOf(value),
        unit = UsageMetricUnit.Currency,
        presentation = UsageMetricPresentation.Balance,
        semantic = UsageMetricSemantic.Balance,
        currencyCode = "CNY",
        healthState = UsageMetricHealthState.Normal,
    )

    private fun readyCard(
        credential: Credential,
        metrics: List<UsageMetric>,
    ) = CredentialCardUi(
        credential = credential,
        status = RefreshStatus.Ready,
        snapshot = UsageSnapshot(credential.id, now, metrics),
        isStale = false,
        error = null,
        freshness = Freshness(FreshnessLevel.JUST_NOW, "刚刚更新"),
    )

    private fun group(
        provider: ProviderId,
        cards: List<CredentialCardUi>,
        isCollapsed: Boolean = false,
    ) = ProviderGroupUi(
        providerId = provider,
        displayName = ProviderCatalog.displayName(provider),
        isCollapsed = isCollapsed,
        cards = cards,
    )

    @Test
    fun rendersMultipleProviderGroupsWithCards() {
        val rt = credential("RT 主力", ProviderId.Routin)
        val ds = credential("DS 备用", ProviderId.DeepSeek)
        val callbacks = Callbacks()
        composeRule.setContent {
            MaterialTheme {
                HomeScreen(
                    state = HomeUiState(
                        isLoading = false,
                        groups = listOf(
                            group(ProviderId.Routin, listOf(readyCard(rt, listOf(balanceMetric(20.0))))),
                            group(ProviderId.DeepSeek, listOf(readyCard(ds, listOf(balanceMetric(10.0))))),
                        ),
                        credentialCount = 2,
                        lastUpdatedAt = now,
                        lastUpdatedText = "刚刚更新",
                    ),
                    onRefreshAll = { callbacks.refreshedAll++ },
                    onRefreshCredential = { callbacks.refreshedCredentialId = it },
                    onToggleGroup = { callbacks.toggledProvider = it },
                    onOpenCredential = { callbacks.openedCredentialId = it },
                    onImportFromMac = { callbacks.importFromMac++ },
                    onAddManually = { callbacks.addedManually++ },
                )
            }
        }

        composeRule.onNodeWithText("Routin").assertIsDisplayed()
        composeRule.onNodeWithText("RT 主力").assertIsDisplayed()

        scrollToText("DS 备用")
        composeRule.onNodeWithText("DeepSeek").assertIsDisplayed()
        composeRule.onNodeWithText("DS 备用").assertIsDisplayed()
    }

    @Test
    fun usageCardShowsProgressMetricsWithAmounts() {
        val rt = credential("RT 主力", ProviderId.Routin)
        composeRule.setContent {
            MaterialTheme {
                HomeScreen(
                    state = HomeUiState(
                        isLoading = false,
                        groups = listOf(
                            group(
                                ProviderId.Routin,
                                listOf(
                                    readyCard(
                                        rt,
                                        listOf(
                                            progressMetric(
                                                "fiveHour",
                                                "5 小时",
                                                used = 4.2,
                                                limit = 10.0,
                                                remaining = 5.8,
                                            ),
                                        ),
                                    ),
                                ),
                            ),
                        ),
                        credentialCount = 1,
                    ),
                    onRefreshAll = {},
                    onRefreshCredential = {},
                    onToggleGroup = {},
                    onOpenCredential = {},
                    onImportFromMac = {},
                    onAddManually = {},
                )
            }
        }

        composeRule.onNodeWithText("42%").assertIsDisplayed()
        composeRule.onNodeWithText("已用 4.2 / 10", substring = true).assertIsDisplayed()
        composeRule.onNodeWithText("剩余 5.8", substring = true).assertIsDisplayed()
    }

    @Test
    fun balanceCardHidesUnsupportedMetrics() {
        val ds = credential("DS 备用", ProviderId.DeepSeek)
        composeRule.setContent {
            MaterialTheme {
                HomeScreen(
                    state = HomeUiState(
                        isLoading = false,
                        groups = listOf(group(ProviderId.DeepSeek, listOf(readyCard(ds, listOf(balanceMetric(12.5)))))),
                        credentialCount = 1,
                    ),
                    onRefreshAll = {},
                    onRefreshCredential = {},
                    onToggleGroup = {},
                    onOpenCredential = {},
                    onImportFromMac = {},
                    onAddManually = {},
                )
            }
        }

        composeRule.onNodeWithText("账户余额").assertIsDisplayed()
        composeRule.onNodeWithText("12.5 CNY", substring = true).assertIsDisplayed()
        composeRule.onNodeWithText("重置", substring = true).assertDoesNotExist()
        composeRule.onNodeWithText("%", substring = true).assertDoesNotExist()
    }

    @Test
    fun failedCardKeepsLastSnapshotWithStaleLabelAndRetry() {
        val rt = credential("RT 主力", ProviderId.Routin)
        val callbacks = Callbacks()
        composeRule.setContent {
            MaterialTheme {
                HomeScreen(
                    state = HomeUiState(
                        isLoading = false,
                        groups = listOf(
                            group(
                                ProviderId.Routin,
                                listOf(
                                    CredentialCardUi(
                                        credential = rt,
                                        status = RefreshStatus.Failed,
                                        snapshot = UsageSnapshot(rt.id, now, listOf(balanceMetric(20.0))),
                                        isStale = true,
                                        error = AppError.Authentication("凭证无效或没有该供应商权限"),
                                        freshness = Freshness(FreshnessLevel.EXPIRED, "数据已过期"),
                                    ),
                                ),
                            ),
                        ),
                        credentialCount = 1,
                    ),
                    onRefreshAll = { callbacks.refreshedAll++ },
                    onRefreshCredential = { callbacks.refreshedCredentialId = it },
                    onToggleGroup = {},
                    onOpenCredential = {},
                    onImportFromMac = {},
                    onAddManually = {},
                )
            }
        }

        composeRule.onNodeWithText("更新失败", substring = true).assertIsDisplayed()
        composeRule.onNodeWithText("上次成功数据", substring = true).assertIsDisplayed()
        composeRule.onNodeWithText("凭证无效或没有该供应商权限").assertIsDisplayed()
        composeRule.onNodeWithText("20 CNY", substring = true).assertIsDisplayed()

        scrollToText("重试")
        composeRule.onNodeWithText("重试").performClick()
        assertEquals(rt.id, callbacks.refreshedCredentialId)
    }

    @Test
    fun loadingCardShowsRefreshingNotError() {
        val rt = credential("RT 主力", ProviderId.Routin)
        composeRule.setContent {
            MaterialTheme {
                HomeScreen(
                    state = HomeUiState(
                        isLoading = false,
                        groups = listOf(
                            group(
                                ProviderId.Routin,
                                listOf(
                                    CredentialCardUi(
                                        credential = rt,
                                        status = RefreshStatus.Loading,
                                        snapshot = null,
                                        isStale = false,
                                        error = null,
                                        freshness = Freshness(FreshnessLevel.NEVER, "从未刷新"),
                                    ),
                                ),
                            ),
                        ),
                        credentialCount = 1,
                    ),
                    onRefreshAll = {},
                    onRefreshCredential = {},
                    onToggleGroup = {},
                    onOpenCredential = {},
                    onImportFromMac = {},
                    onAddManually = {},
                )
            }
        }

        composeRule.onNodeWithText("刷新中", substring = true).assertIsDisplayed()
        composeRule.onNodeWithText("更新失败", substring = true).assertDoesNotExist()
        composeRule.onNodeWithText("重试").assertDoesNotExist()
    }

    @Test
    fun disabledCardShowsDisabledLabel() {
        val glm = credential("GLM 停用", ProviderId.Glm)
        composeRule.setContent {
            MaterialTheme {
                HomeScreen(
                    state = HomeUiState(
                        isLoading = false,
                        groups = listOf(
                            group(
                                ProviderId.Glm,
                                listOf(
                                    CredentialCardUi(
                                        credential = glm,
                                        status = RefreshStatus.Disabled,
                                        snapshot = null,
                                        isStale = false,
                                        error = null,
                                        freshness = Freshness(FreshnessLevel.NEVER, "从未刷新"),
                                    ),
                                ),
                            ),
                        ),
                        credentialCount = 1,
                    ),
                    onRefreshAll = {},
                    onRefreshCredential = {},
                    onToggleGroup = {},
                    onOpenCredential = {},
                    onImportFromMac = {},
                    onAddManually = {},
                )
            }
        }

        composeRule.onNodeWithText("已停用").assertIsDisplayed()
    }

    @Test
    fun emptyStateOffersImportAndManualAdd() {
        val callbacks = Callbacks()
        composeRule.setContent {
            MaterialTheme {
                HomeScreen(
                    state = HomeUiState(isLoading = false, groups = emptyList(), credentialCount = 0),
                    onRefreshAll = {},
                    onRefreshCredential = {},
                    onToggleGroup = {},
                    onOpenCredential = {},
                    onImportFromMac = { callbacks.importFromMac++ },
                    onAddManually = { callbacks.addedManually++ },
                )
            }
        }

        composeRule.onNodeWithText("从 Mac 导入").performClick()
        composeRule.onNodeWithText("手动添加").performClick()
        assertEquals(1, callbacks.importFromMac)
        assertEquals(1, callbacks.addedManually)
    }

    @Test
    fun collapsedGroupHidesCardsButKeepsHeader() {
        val rt = credential("RT 主力", ProviderId.Routin)
        composeRule.setContent {
            MaterialTheme {
                HomeScreen(
                    state = HomeUiState(
                        isLoading = false,
                        groups = listOf(group(ProviderId.Routin, listOf(readyCard(rt, listOf(balanceMetric(1.0)))), isCollapsed = true)),
                        credentialCount = 1,
                    ),
                    onRefreshAll = {},
                    onRefreshCredential = {},
                    onToggleGroup = {},
                    onOpenCredential = {},
                    onImportFromMac = {},
                    onAddManually = {},
                )
            }
        }

        composeRule.onNodeWithText("Routin").assertIsDisplayed()
        composeRule.onNodeWithText("RT 主力").assertDoesNotExist()
    }

    @Test
    fun cardClickOpensDetailCallback() {
        val rt = credential("RT 主力", ProviderId.Routin)
        val callbacks = Callbacks()
        composeRule.setContent {
            MaterialTheme {
                HomeScreen(
                    state = HomeUiState(
                        isLoading = false,
                        groups = listOf(group(ProviderId.Routin, listOf(readyCard(rt, listOf(balanceMetric(1.0)))))),
                        credentialCount = 1,
                    ),
                    onRefreshAll = {},
                    onRefreshCredential = {},
                    onToggleGroup = {},
                    onOpenCredential = { callbacks.openedCredentialId = it },
                    onImportFromMac = {},
                    onAddManually = {},
                )
            }
        }

        composeRule.onNodeWithText("RT 主力").performClick()
        assertEquals(rt.id, callbacks.openedCredentialId)
    }

    @Test
    fun darkModeRendersGroupsAndCards() {
        val rt = credential("RT 深色", ProviderId.Routin)
        composeRule.setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                HomeScreen(
                    state = HomeUiState(
                        isLoading = false,
                        groups = listOf(group(ProviderId.Routin, listOf(readyCard(rt, listOf(balanceMetric(9.0)))))),
                        credentialCount = 1,
                    ),
                    onRefreshAll = {},
                    onRefreshCredential = {},
                    onToggleGroup = {},
                    onOpenCredential = {},
                    onImportFromMac = {},
                    onAddManually = {},
                )
            }
        }

        composeRule.onNodeWithText("RT 深色").assertIsDisplayed()
        composeRule.onNodeWithText("账户余额").assertIsDisplayed()
    }

    @Test
    fun largeFontScaleRendersWithoutLossOfKeyText() {
        val rt = credential("RT 大字体", ProviderId.Routin)
        composeRule.setContent {
            CompositionLocalProvider(
                LocalDensity provides Density(density = 2f, fontScale = 1.8f),
            ) {
                MaterialTheme {
                    HomeScreen(
                        state = HomeUiState(
                            isLoading = false,
                            groups = listOf(group(ProviderId.Routin, listOf(readyCard(rt, listOf(balanceMetric(9.0)))))),
                            credentialCount = 1,
                        ),
                        onRefreshAll = {},
                        onRefreshCredential = {},
                        onToggleGroup = {},
                        onOpenCredential = {},
                        onImportFromMac = {},
                        onAddManually = {},
                    )
                }
            }
        }

        composeRule.onNodeWithText("RT 大字体").assertIsDisplayed()

        scrollToText("账户余额")
        composeRule.onNodeWithText("账户余额").assertIsDisplayed()
    }

    @Test
    fun detailScreenShowsAllMetricsTimeErrorAndActions() {
        val rt = credential("RT 主力", ProviderId.Routin)
        val callbacks = Callbacks()
        val card = CredentialCardUi(
            credential = rt,
            status = RefreshStatus.Failed,
            snapshot = UsageSnapshot(
                rt.id,
                now,
                listOf(
                    progressMetric("fiveHour", "5 小时", 4.2, 10.0, 5.8, windowEnd = now),
                    progressMetric("weekly", "本周", 1.0, 20.0, 19.0),
                    balanceMetric(3.25),
                ),
            ),
            isStale = true,
            error = AppError.Network("请求过于频繁，请稍后重试"),
            freshness = Freshness(FreshnessLevel.RECENT, "5分钟前更新"),
        )

        composeRule.setContent {
            MaterialTheme {
                CredentialDetailScreen(
                    card = card,
                    onBack = {},
                    onRefresh = { callbacks.refreshedCredentialId = rt.id },
                    onEdit = {},
                    onDelete = {},
                )
            }
        }

        composeRule.onNodeWithText("RT 主力").assertIsDisplayed()
        composeRule.onNodeWithText("5 小时").assertIsDisplayed()

        scrollToText("本周")
        composeRule.onNodeWithText("本周").assertIsDisplayed()

        scrollToText("账户余额")
        composeRule.onNodeWithText("账户余额").assertIsDisplayed()

        scrollToText("更新时间")
        composeRule.onNodeWithText("更新时间", substring = true).assertIsDisplayed()
        composeRule.onNodeWithText("请求过于频繁，请稍后重试").assertIsDisplayed()

        composeRule.onNodeWithText("刷新").performClick()
        assertEquals(rt.id, callbacks.refreshedCredentialId)
        composeRule.onNodeWithText("编辑").assertIsDisplayed()
        composeRule.onNodeWithText("删除").assertIsDisplayed()
    }

    @Test
    fun detailScreenSupportsCardWithoutSnapshot() {
        val rt = credential("RT 空数据", ProviderId.Routin)
        composeRule.setContent {
            MaterialTheme {
                CredentialDetailScreen(
                    card = CredentialCardUi(
                        credential = rt,
                        status = RefreshStatus.Failed,
                        snapshot = null,
                        isStale = false,
                        error = AppError.Authentication("凭证无效或没有该供应商权限"),
                        freshness = Freshness(FreshnessLevel.NEVER, "从未刷新"),
                    ),
                    onBack = {},
                    onRefresh = {},
                    onEdit = {},
                    onDelete = {},
                )
            }
        }

        composeRule.onNodeWithText("从未刷新", substring = true).assertIsDisplayed()
        composeRule.onNodeWithText("凭证无效或没有该供应商权限").assertIsDisplayed()
        composeRule.onNodeWithText("刷新").assertIsDisplayed()
    }
}
