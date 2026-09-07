package ai.routin.mytoken.provider

import ai.routin.mytoken.provider.volcengine.VolcengineSigner
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.Test

/**
 * Fixed test vectors produced from the same inputs used by the macOS
 * `VolcengineSigningTests` (RoutinUsageTests/VolcengineSigningTests.swift):
 * POST https://ark.test/?Action=GetAFPUsage&Version=2024-01-01, body {},
 * access-key / secret-key / cn-beijing at 2023-11-14T22:13:20Z.
 */
class VolcengineSignerTest {

    private val signer = VolcengineSigner()
    private val credential = VolcengineSigner.Credential(
        accessKeyID = "access-key",
        secretAccessKey = "secret-key",
        region = "cn-beijing"
    )

    private fun sign(): Map<String, String> = signer.sign(
        method = "POST",
        url = "https://ark.test/?Action=GetAFPUsage&Version=2024-01-01",
        headers = mapOf("Content-Type" to "application/json"),
        body = "{}".toByteArray(),
        credential = credential,
        timestamp = Instant.ofEpochSecond(1_700_000_000)
    )

    @Test
    fun sign_producesStableTimestampAndBodyHash() {
        val headers = sign()

        assertEquals("20231114T221320Z", headers["X-Date"])
        assertEquals(
            "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a",
            headers["X-Content-Sha256"]
        )
        assertEquals("ark.test", headers["Host"])
    }

    @Test
    fun sign_producesTheExpectedAuthorizationValue() {
        val authorization = sign()["Authorization"]!!

        assertEquals(
            "HMAC-SHA256 Credential=access-key/20231114/cn-beijing/ark/request, " +
                "SignedHeaders=content-type;host;x-content-sha256;x-date, " +
                "Signature=311b60b48afb6ce9b50828c5706dcde991b60fc77463bfa93d5f14f6573f14f9",
            authorization
        )
    }

    @Test
    fun sign_isDeterministicForFixedInput() {
        assertEquals(sign()["Authorization"], sign()["Authorization"])
        assertTrue(sign()["Authorization"]!!.startsWith("HMAC-SHA256 Credential=access-key/"))
    }
}
