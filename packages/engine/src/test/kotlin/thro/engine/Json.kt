package thro.engine

/**
 * A minimal JSON reader, test-only.
 *
 * Hand-written rather than pulled in as a dependency so that running the conformance corpus never
 * depends on resolving a library. The corpus is the contract between three platforms and must be
 * runnable anywhere, including on a machine with no network.
 */
internal sealed interface J {
    data class S(val v: String) : J
    data class N(val v: Long) : J
    data class B(val v: Boolean) : J
    data object Null : J
    data class A(val v: List<J>) : J
    data class O(val v: Map<String, J>) : J
}

internal fun parseJson(text: String): J = Parser(text).value()

private class Parser(private val s: String) {
    private var i = 0
    private fun ws() { while (i < s.length && s[i].isWhitespace()) i++ }
    fun value(): J {
        ws()
        return when (s[i]) {
            '{' -> obj()
            '[' -> arr()
            '"' -> J.S(str())
            't' -> { i += 4; J.B(true) }
            'f' -> { i += 5; J.B(false) }
            'n' -> { i += 4; J.Null }
            else -> num()
        }
    }
    private fun obj(): J {
        i++; val m = LinkedHashMap<String, J>()
        ws(); if (s[i] == '}') { i++; return J.O(m) }
        while (true) {
            ws(); val k = str(); ws(); i++
            m[k] = value(); ws()
            if (s[i] == ',') i++ else { i++; return J.O(m) }
        }
    }
    private fun arr(): J {
        i++; val l = ArrayList<J>()
        ws(); if (s[i] == ']') { i++; return J.A(l) }
        while (true) {
            l += value(); ws()
            if (s[i] == ',') i++ else { i++; return J.A(l) }
        }
    }
    private fun str(): String {
        i++; val b = StringBuilder()
        while (s[i] != '"') {
            if (s[i] == '\\') {
                i++
                when (s[i]) {
                    'n' -> b.append('\n')
                    't' -> b.append('\t')
                    'r' -> b.append('\r')
                    'u' -> { b.append(s.substring(i + 1, i + 5).toInt(16).toChar()); i += 4 }
                    else -> b.append(s[i])
                }
            } else b.append(s[i])
            i++
        }
        i++
        return b.toString()
    }
    private fun num(): J {
        val start = i
        while (i < s.length && (s[i].isDigit() || s[i] in "-+.eE")) i++
        return J.N(s.substring(start, i).toLong())
    }
}

internal fun J.obj(): Map<String, J> = (this as J.O).v
internal fun J.arr(): List<J> = (this as J.A).v
internal fun J.str(): String = (this as J.S).v
internal fun J.int(): Int = (this as J.N).v.toInt()
internal fun Map<String, J>.opt(k: String): J? = this[k]?.takeIf { it !is J.Null }
