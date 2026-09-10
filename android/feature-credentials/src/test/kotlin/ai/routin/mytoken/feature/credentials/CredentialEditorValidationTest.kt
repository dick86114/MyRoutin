package ai.routin.mytoken.feature.credentials

import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.CredentialMetadataKey
import ai.routin.mytoken.domain.model.CredentialSecret
import ai.routin.mytoken.domain.model.ProviderId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Aligned with the macOS CredentialEditorValidation (RoutinUsage/Views/CredentialEditorView.swift)
 * and KeyEditorValidationTests. Only the Android metadata allowlist keys are persisted
 * (baseURL, userID, region, planType, usageKind, websiteURL).
 */
class CredentialEditorValidationTest {

    private fun validate(
        providerId: ProviderId,
        name: String,
        apiKey: String = "",
        accessKeyID: String = "",
        secretAccessKey: String = "",
        region: String = "",
        newAPIBaseURL: String = "",
        newAPIUserID: String = "",
        websiteURL: String = "",
    ) = CredentialEditorValidation.validate(
        providerId = providerId,
        fields = CredentialEditorValidation.FormFields(
            name = name,
            apiKey = apiKey,
            accessKeyID = accessKeyID,
            secretAccessKey = secretAccessKey,
            region = region,
            newAPIBaseURL = newAPIBaseURL,
            newAPIUserID = newAPIUserID,
            websiteURL = websiteURL,
        ),
    )

    private fun failure(
        providerId: ProviderId,
        name: String,
        apiKey: String = "",
        accessKeyID: String = "",
        secretAccessKey: String = "",
        region: String = "",
        newAPIBaseURL: String = "",
        newAPIUserID: String = "",
        websiteURL: String = "",
    ): String = try {
        validate(
            providerId, name, apiKey, accessKeyID, secretAccessKey,
            region, newAPIBaseURL, newAPIUserID, websiteURL,
        )
        ""
    } catch (error: CredentialValidationException) {
        requireNotNull(error.message)
    }

    @Test
    fun emptyNameFailsWithChineseError() {
        assertEquals("请输入 Key 名称", failure(ProviderId.Routin, name = " \n "))
    }

    @Test
    fun emptyPlanKeyFailsWithChineseError() {
        assertEquals("请输入 plan Key", failure(ProviderId.Routin, name = "主账号"))
    }

    @Test
    fun nonPlanKeyFailsWithChineseError() {
        assertEquals("Key 必须以 plan- 开头", failure(ProviderId.Routin, name = "主账号", apiKey = "sk-invalid"))
    }

    @Test
    fun shortPlanKeyPayloadFailsWithChineseError() {
        assertEquals("plan Key 内容至少需要 4 位", failure(ProviderId.Routin, name = "主账号", apiKey = "plan-abc"))
    }

    @Test
    fun displayNameMatchingPlanSecretFailsWithChineseError() {
        assertEquals(
            "显示名称不能是 plan Key",
            failure(ProviderId.Routin, name = "plan-sensitive-8F2A", apiKey = "plan-sensitive-8F2A"),
        )
    }

    @Test
    fun validRoutinKeyNormalizesNameKeepsSecretAndSetsPlanType() {
        val input = validate(ProviderId.Routin, name = "  主账号 \n", apiKey = "plan-AbC-8F2A ")
        assertEquals("主账号", input.name)
        assertEquals(CredentialKind.BearerApiKey, input.credentialKind)
        assertEquals("plan-AbC-8F2A ", (input.secret as CredentialSecret.BearerToken).token)
        assertEquals("agent", input.metadata[CredentialMetadataKey.PlanType])
    }

    @Test
    fun routinKeySupportsWebsiteMetadata() {
        val input = validate(
            ProviderId.Routin,
            name = "主账号",
            apiKey = "plan-main-8F2A",
            websiteURL = "https://routin.ai/pricing",
        )
        assertEquals("https://routin.ai/pricing", input.metadata[CredentialMetadataKey.WebsiteURL])
    }

    @Test
    fun invalidWebsiteURLFails() {
        assertEquals("请输入有效的网址", failure(ProviderId.Routin, name = "主账号", apiKey = "plan-main-8F2A", websiteURL = "not a url"))
    }

    @Test
    fun deepSeekAndGlmRequireNonEmptyApiKey() {
        assertEquals("请输入 API Key", failure(ProviderId.DeepSeek, name = "备用"))
        assertEquals("请输入 API Key", failure(ProviderId.Glm, name = "备用"))
        val input = validate(ProviderId.DeepSeek, name = "备用", apiKey = "  sk-abc  ")
        assertEquals(CredentialKind.ApiKey, input.credentialKind)
        assertEquals("sk-abc", (input.secret as CredentialSecret.ApiKey).key)
    }

    @Test
    fun volcengineRequiresAccessKeyPairWithDefaultRegion() {
        assertEquals("请输入 Access Key ID", failure(ProviderId.Volcengine, name = "方舟", secretAccessKey = "sk"))
        assertEquals("请输入 Secret Access Key", failure(ProviderId.Volcengine, name = "方舟", accessKeyID = "AK"))
        val input = validate(
            ProviderId.Volcengine,
            name = "方舟",
            accessKeyID = " AKTP ",
            secretAccessKey = " c2VjcmV0 ",
        )
        assertEquals(CredentialKind.AccessKeyPair, input.credentialKind)
        assertEquals("AKTP", (input.secret as CredentialSecret.AccessKeyPair).accessKeyID)
        assertEquals("c2VjcmV0", (input.secret as CredentialSecret.AccessKeyPair).secretAccessKey)
        assertEquals("cn-beijing", input.metadata[CredentialMetadataKey.Region])
        assertEquals("agent", input.metadata[CredentialMetadataKey.PlanType])
        val withRegion = validate(
            ProviderId.Volcengine,
            name = "方舟",
            accessKeyID = "AKTP",
            secretAccessKey = "c2VjcmV0",
            region = "cn-shanghai",
        )
        assertEquals("cn-shanghai", withRegion.metadata[CredentialMetadataKey.Region])
    }

    @Test
    fun newAPIRequiresKeyUserIDAndBaseURL() {
        assertEquals("请输入 API Key", failure(ProviderId.NewAPI, name = "中转", newAPIBaseURL = "https://api.example.com", newAPIUserID = "1"))
        assertEquals("请输入有效的用户 ID", failure(ProviderId.NewAPI, name = "中转", apiKey = "sk-1", newAPIBaseURL = "https://api.example.com", newAPIUserID = "0"))
        assertEquals("请输入有效的用户 ID", failure(ProviderId.NewAPI, name = "中转", apiKey = "sk-1", newAPIBaseURL = "https://api.example.com", newAPIUserID = "abc"))
        assertEquals("请输入有效的接口地址", failure(ProviderId.NewAPI, name = "中转", apiKey = "sk-1", newAPIBaseURL = "not-a-url", newAPIUserID = "1"))
        assertEquals("请输入有效的接口地址", failure(ProviderId.NewAPI, name = "中转", apiKey = "sk-1", newAPIBaseURL = "ftp://api.example.com", newAPIUserID = "1"))
    }

    @Test
    fun validNewAPINormalizesBaseURLAndStoresUserID() {
        val input = validate(
            ProviderId.NewAPI,
            name = "中转",
            apiKey = "sk-1",
            newAPIBaseURL = "https://api.example.com/api/",
            newAPIUserID = "42",
        )
        assertEquals(CredentialKind.BearerApiKey, input.credentialKind)
        assertEquals("https://api.example.com", input.metadata[CredentialMetadataKey.BaseURL])
        assertEquals("42", input.metadata[CredentialMetadataKey.UserID])
        assertEquals("sk-1", (input.secret as CredentialSecret.BearerToken).token)
    }

    @Test
    fun onlyAllowlistedMetadataKeysAreEmitted() {
        val allowlist = CredentialMetadataKey.entries.map { it.rawValue }.toSet()
        val input = validate(ProviderId.NewAPI, name = "中转", apiKey = "sk-1", newAPIBaseURL = "https://api.example.com", newAPIUserID = "42")
        assertTrue(input.metadata.keys.all { it.rawValue in allowlist })
        assertFalse(input.metadata.isEmpty())
    }

    @Test
    fun commandCodeRequiresBearerKeyAndKeepsWebsite() {
        assertEquals("请输入 API Key", failure(ProviderId.CommandCode, name = "Command Code"))
        val input = validate(
            ProviderId.CommandCode,
            name = "Command Code",
            apiKey = "  cmd-key  ",
            websiteURL = "https://commandcode.ai/",
        )
        assertEquals(CredentialKind.BearerApiKey, input.credentialKind)
        assertEquals("cmd-key", (input.secret as CredentialSecret.BearerToken).token)
        assertEquals("https://commandcode.ai/", input.metadata[CredentialMetadataKey.WebsiteURL])
    }
}
