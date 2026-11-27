package com.vervali.chatarchiver

import org.json.JSONArray
import org.json.JSONObject

/** Converts between plain Maps/Lists (what platform channels use) and org.json. */
object JsonUtil {
    fun toJson(value: Any?): Any? = when (value) {
        null -> JSONObject.NULL
        is Map<*, *> -> JSONObject().also { o ->
            value.forEach { (k, v) -> o.put(k.toString(), toJson(v)) }
        }
        is Iterable<*> -> JSONArray().also { a -> value.forEach { a.put(toJson(it)) } }
        else -> value
    }

    fun fromJson(value: Any?): Any? = when {
        value == null || value == JSONObject.NULL -> null
        value is JSONObject -> {
            val m = LinkedHashMap<String, Any?>()
            val keys = value.keys()
            while (keys.hasNext()) {
                val k = keys.next()
                m[k] = fromJson(value.get(k))
            }
            m
        }
        value is JSONArray -> (0 until value.length()).map { fromJson(value.get(it)) }
        else -> value
    }

    fun mapToString(m: Map<String, Any?>): String = toJson(m).toString()

    @Suppress("UNCHECKED_CAST")
    fun stringToMap(s: String): Map<String, Any?>? =
        try {
            fromJson(JSONObject(s)) as? Map<String, Any?>
        } catch (_: Exception) {
            null
        }
}
