package org.avoperformance.horse.core

import org.avoperformance.horse.core.bytes.hexToBytes

object TestRes {
    fun bytes(name: String): ByteArray =
        (TestRes::class.java.getResourceAsStream("/$name") ?: error("missing test resource $name")).use { it.readBytes() }

    fun kv(name: String): Map<String, String> = String(bytes(name), Charsets.UTF_8).lines()
        .filter { it.contains('=') }.associate { it.substringBefore('=') to it.substringAfter('=') }

    fun hex(name: String, key: String): ByteArray = (kv(name)[key] ?: error("missing $key in $name")).hexToBytes()
}
