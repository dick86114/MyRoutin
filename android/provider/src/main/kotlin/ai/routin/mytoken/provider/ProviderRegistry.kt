package ai.routin.mytoken.provider

import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.usage.UsageProvider
import ai.routin.mytoken.provider.deepseek.DeepSeekUsageProvider
import ai.routin.mytoken.provider.glm.GLMUsageProvider
import ai.routin.mytoken.provider.http.JavaHttpTransport
import ai.routin.mytoken.provider.routin.RoutinUsageProvider
import ai.routin.mytoken.provider.volcengine.VolcengineUsageProvider

/**
 * Builds the production provider registry with a shared Android HTTP transport.
 * Kept inside :provider so callers (e.g. the app module) never need to touch
 * [JavaHttpTransport]'s constructor default arguments directly.
 */
fun defaultUsageProviders(): Map<ProviderId, UsageProvider> {
    val transport = JavaHttpTransport()
    return mapOf(
        ProviderId.Routin to RoutinUsageProvider(transport),
        ProviderId.DeepSeek to DeepSeekUsageProvider(transport),
        ProviderId.Glm to GLMUsageProvider(transport),
        ProviderId.Volcengine to VolcengineUsageProvider(transport),
    )
}
