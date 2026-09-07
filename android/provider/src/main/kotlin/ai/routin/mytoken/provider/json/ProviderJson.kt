package ai.routin.mytoken.provider.json

import java.math.BigDecimal
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull

/** Shared JSON parsing helpers for provider adapters (responses may mix numbers and strings). */
object ProviderJson {
    val default: Json = Json { ignoreUnknownKeys = true }

    fun parse(text: String): JsonElement = default.parseToJsonElement(text)
}

fun JsonElement.asObjectOrNull(): JsonObject? = this as? JsonObject

fun JsonElement.asArrayOrNull(): JsonArray? = this as? JsonArray

fun JsonObject.objOrNull(key: String): JsonObject? {
    val value = this[key] ?: return null
    return value as? JsonObject
}

fun JsonObject.arrayOrNull(key: String): JsonArray? {
    val value = this[key] ?: return null
    return value as? JsonArray
}

fun JsonObject.stringOrNull(key: String): String? {
    val value = this[key] as? JsonPrimitive ?: return null
    return if (value.isString) value.contentOrNull else value.contentOrNull
}

fun JsonObject.intOrNull(key: String): Int? {
    val value = this[key] as? JsonPrimitive ?: return null
    return value.contentOrNull?.trim()?.toIntOrNull()
}

fun JsonObject.longOrNull(key: String): Long? {
    val value = this[key] as? JsonPrimitive ?: return null
    return value.contentOrNull?.trim()?.toLongOrNull()
}

fun JsonObject.boolOrNull(key: String): Boolean? {
    val value = this[key] as? JsonPrimitive ?: return null
    return value.booleanOrNull
}

/** Accepts JSON numbers and numeric strings, mirroring the macOS Decimal decoding behavior. */
fun JsonObject.decimalOrNull(key: String): BigDecimal? {
    val value = this[key] as? JsonPrimitive ?: return null
    return value.contentOrNull?.trim()?.let { raw ->
        runCatching { BigDecimal(raw) }.getOrNull()
    }
}
