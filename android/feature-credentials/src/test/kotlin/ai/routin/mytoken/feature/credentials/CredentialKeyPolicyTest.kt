package ai.routin.mytoken.feature.credentials

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Port of the macOS KeyCredentialPolicy / KeyDisplayMask validation rules
 * (RoutinUsage/Models/KeyConfiguration.swift, KeyDisplayMask.swift).
 */
class CredentialKeyPolicyTest {

    @Test
    fun emptyOrBlankDisplayNameIsUnsafe() {
        assertFalse(CredentialKeyPolicy.isSafeDisplayName(""))
        assertFalse(CredentialKeyPolicy.isSafeDisplayName("  \n "))
    }

    @Test
    fun displayNameThatLooksLikePlanSecretIsUnsafe() {
        assertFalse(CredentialKeyPolicy.isSafeDisplayName("plan-sensitive-8F2A"))
        assertFalse(CredentialKeyPolicy.isSafeDisplayName("  PLAN-main  "))
        assertTrue(CredentialKeyPolicy.isSafeDisplayName("主账号"))
    }

    @Test
    fun secretMustStartWithPlanPrefix() {
        assertTrue(CredentialKeyPolicy.hasValidPrefix("plan-AbC-8F2A"))
        assertFalse(CredentialKeyPolicy.hasValidPrefix("sk-invalid"))
        assertFalse(CredentialKeyPolicy.hasValidPrefix(""))
    }

    @Test
    fun secretPayloadMustHaveAtLeastFourCharacters() {
        assertTrue(CredentialKeyPolicy.hasSufficientSecretPayload("plan-8F2A"))
        assertFalse(CredentialKeyPolicy.hasSufficientSecretPayload("plan-abc"))
        assertFalse(CredentialKeyPolicy.hasSufficientSecretPayload("sk-long-but-wrong-prefix"))
    }

    @Test
    fun metadataSuffixReturnsLastFourCharactersOnlyForValidSecrets() {
        assertEquals("8F2A", CredentialKeyPolicy.metadataSuffix("plan-sensitive-8F2A"))
        assertEquals("", CredentialKeyPolicy.metadataSuffix("plan-abc"))
        assertEquals("", CredentialKeyPolicy.metadataSuffix("sk-invalid"))
    }

    @Test
    fun maskedDisplayShowsFixedMaskPlusFourCharacterSuffix() {
        assertEquals("plan-••••8F2A", CredentialKeyPolicy.maskedDisplay("8F2A"))
    }

    @Test
    fun shortOrLegacySuffixesAreFullyMasked() {
        for (suffix in listOf("abc", "an-a", "n-ab", "-abc")) {
            val display = CredentialKeyPolicy.maskedDisplay(suffix)
            assertEquals("plan-••••", display)
            assertFalse(display.contains(suffix))
        }
    }

    @Test
    fun safeDisplayNameTrimsWhitespace() {
        assertEquals("主账号", CredentialKeyPolicy.safeDisplayName("  主账号 \n"))
        assertEquals("未命名 Key", CredentialKeyPolicy.safeDisplayName("plan-secret"))
    }
}
