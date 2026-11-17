package org.avoperformance.horse.core.engine

/**
 * Minimal JSON reader for the engine output (pure Kotlin, no Android dependency, testable on the JVM).
 * Objects -> Map<String, Any?>, arrays -> List<Any?>, numbers -> Double, true/false -> Boolean, null -> null.
 */
object MiniJson {
    class ParseException(msg: String) : Exception(msg)

    fun parse(text: String): Any? {
        val p = Parser(text)
        val v = p.value()
        p.ws()
        if (p.i != text.length) throw ParseException("texto sobrante en ${p.i}")
        return v
    }

    private class Parser(val s: String) {
        var i = 0
        fun ws() { while (i < s.length && (s[i] == ' ' || s[i] == '\n' || s[i] == '\r' || s[i] == '\t')) i++ }
        fun value(): Any? {
            ws()
            if (i >= s.length) throw ParseException("fin inesperado")
            return when (val c = s[i]) {
                '{' -> obj()
                '[' -> arr()
                '"' -> str()
                't' -> lit("true", true)
                'f' -> lit("false", false)
                'n' -> lit("null", null)
                else -> if (c == '-' || c.isDigit()) num() else throw ParseException("valor no reconocido en $i")
            }
        }
        fun lit(w: String, v: Any?): Any? { if (!s.startsWith(w, i)) throw ParseException("literal no válido en $i"); i += w.length; return v }
        fun num(): Double {
            val st = i
            while (i < s.length && (s[i].isDigit() || s[i] in "+-.eE")) i++
            return s.substring(st, i).toDoubleOrNull() ?: throw ParseException("número no válido en $st")
        }
        fun str(): String {
            i++
            val b = StringBuilder()
            while (i < s.length) {
                val c = s[i++]
                when {
                    c == '"' -> return b.toString()
                    c != '\\' -> b.append(c)
                    else -> {
                        val e = s[i++]
                        when (e) {
                            '"' -> b.append('"'); '\\' -> b.append('\\'); '/' -> b.append('/')
                            'b' -> b.append('\b'); 'f' -> b.append('\u000C'); 'n' -> b.append('\n'); 'r' -> b.append('\r'); 't' -> b.append('\t')
                            'u' -> { b.append(s.substring(i, i + 4).toInt(16).toChar()); i += 4 }
                            else -> throw ParseException("escape no válido en $i")
                        }
                    }
                }
            }
            throw ParseException("cadena sin cerrar")
        }
        fun obj(): Map<String, Any?> {
            i++
            val m = LinkedHashMap<String, Any?>()
            ws()
            if (s[i] == '}') { i++; return m }
            while (true) {
                ws(); if (s[i] != '"') throw ParseException("se esperaba clave en $i")
                val k = str(); ws()
                if (s[i++] != ':') throw ParseException("se esperaba ':' en $i")
                m[k] = value(); ws()
                when (s[i++]) { ',' -> continue; '}' -> return m; else -> throw ParseException("se esperaba ',' o '}' en $i") }
            }
        }
        fun arr(): List<Any?> {
            i++
            val l = ArrayList<Any?>()
            ws()
            if (s[i] == ']') { i++; return l }
            while (true) {
                l.add(value()); ws()
                when (s[i++]) { ',' -> continue; ']' -> return l; else -> throw ParseException("se esperaba ',' o ']' en $i") }
            }
        }
    }
}

/** Typed accessors over the parsed tree. */
@Suppress("UNCHECKED_CAST")
class J(val v: Any?) {
    operator fun get(k: String) = J((v as? Map<String, Any?>)?.get(k))
    operator fun get(i: Int) = J((v as? List<Any?>)?.getOrNull(i))
    val list: List<J> get() = (v as? List<Any?>)?.map { J(it) } ?: emptyList()
    val keys: Set<String> get() = (v as? Map<String, Any?>)?.keys ?: emptySet()
    val isNull: Boolean get() = v == null
    fun d(): Double = (v as? Double) ?: Double.NaN
    fun dOrNull(): Double? = (v as? Double)?.takeIf { it.isFinite() }
    fun i(def: Int = 0): Int = (v as? Double)?.toInt() ?: def
    fun l(): Long? = (v as? Double)?.toLong()
    fun s(def: String = ""): String = (v as? String) ?: def
    fun b(def: Boolean = false): Boolean = (v as? Boolean) ?: def
    fun doubles(): DoubleArray = (v as? List<Any?>)?.map { (it as? Double) ?: Double.NaN }?.toDoubleArray() ?: DoubleArray(0)
    fun ints(): IntArray = (v as? List<Any?>)?.map { (it as? Double)?.toInt() ?: -1 }?.toIntArray() ?: IntArray(0)
    fun strings(): List<String> = (v as? List<Any?>)?.map { it as? String ?: "" } ?: emptyList()
}
