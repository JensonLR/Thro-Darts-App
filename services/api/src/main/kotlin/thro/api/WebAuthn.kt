package thro.api

import java.math.BigInteger
import java.nio.ByteBuffer
import java.security.AlgorithmParameters
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.PublicKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECParameterSpec
import java.security.spec.ECPoint
import java.security.spec.ECPublicKeySpec
import java.security.spec.RSAPublicKeySpec
import java.util.Base64

/**
 * WebAuthn, the parts THRØ needs (PD-030's fallback sign-in): a registration ceremony that yields a
 * public key, and an assertion ceremony that proves possession of its private key. No library —
 * the formats are small and every byte checked is named here.
 *
 * What is verified: the client data's type, challenge and origin; the authenticator data's relying
 * party hash, user-presence and user-verification flags, and sign count; and, for an assertion,
 * the signature over authenticator data and the client data's hash. What is deliberately not: the
 * attestation statement. THRØ asks for `attestation: none` and trusts no vendor certificate chain;
 * the key is the person's, and which make of authenticator holds it is not THRØ's business.
 */
public class RelyingParty(public val id: String, public val origins: Set<String>, public val name: String = "THRØ") {
    public val idHash: ByteArray = MessageDigest.getInstance("SHA-256").digest(id.toByteArray(Charsets.UTF_8))
}

public object WebAuthn {

    public sealed interface Outcome<out T> {
        public data class Ok<T>(val value: T) : Outcome<T>
        public data class Bad(val why: String) : Outcome<Nothing>
    }

    /** What a registration proves: this credential id, this COSE public key, this counter, verified this way. */
    public data class Registered(val credentialId: ByteArray, val publicKeyCose: ByteArray, val alg: Long, val signCount: Long)

    public const val ES256: Long = -7
    public const val RS256: Long = -257

    public fun register(clientDataJson: ByteArray, attestationObject: ByteArray, challenge: ByteArray, rp: RelyingParty): Outcome<Registered> {
        clientData(clientDataJson, "webauthn.create", challenge, rp).let { if (it is Outcome.Bad) return it }
        val att = try { Cbor.decode(attestationObject) as? Map<*, *> } catch (e: Exception) { null } ?: return Outcome.Bad("attestation object is not a CBOR map")
        val authData = att["authData"] as? ByteArray ?: return Outcome.Bad("no authenticator data")
        val parsed = authenticatorData(authData, rp).let { if (it is Outcome.Bad) return it; (it as Outcome.Ok).value }
        val cred = parsed.credential ?: return Outcome.Bad("no credential in the authenticator data")
        val cose = try { Cbor.decode(cred.second) as? Map<*, *> } catch (e: Exception) { null } ?: return Outcome.Bad("public key is not a COSE map")
        val alg = (cose[3L] as? Long) ?: return Outcome.Bad("public key names no algorithm")
        if (alg != ES256 && alg != RS256) return Outcome.Bad("algorithm $alg is not accepted (ES256 or RS256)")
        // Build the key now, so a malformed one is refused at registration and not at first sign-in.
        publicKey(cred.second).let { if (it is Outcome.Bad) return it }
        return Outcome.Ok(Registered(cred.first, cred.second, alg, parsed.signCount))
    }

    /** Verifies an assertion and returns the new sign count to store. */
    public fun assert(
        clientDataJson: ByteArray, authenticatorData: ByteArray, signature: ByteArray,
        challenge: ByteArray, rp: RelyingParty, publicKeyCose: ByteArray, storedSignCount: Long,
    ): Outcome<Long> {
        clientData(clientDataJson, "webauthn.get", challenge, rp).let { if (it is Outcome.Bad) return it }
        val parsed = authenticatorData(authenticatorData, rp).let { if (it is Outcome.Bad) return it; (it as Outcome.Ok).value }
        // A counter that did not advance is the sign of a cloned authenticator — unless both are zero,
        // which is what synced passkeys (iCloud Keychain) report by design.
        if (!(parsed.signCount == 0L && storedSignCount == 0L) && parsed.signCount <= storedSignCount) {
            return Outcome.Bad("sign count did not advance: ${parsed.signCount} after $storedSignCount")
        }
        val key = publicKey(publicKeyCose).let { if (it is Outcome.Bad) return it; (it as Outcome.Ok).value }
        val signed = authenticatorData + MessageDigest.getInstance("SHA-256").digest(clientDataJson)
        val ok = try {
            Signature.getInstance(key.second).run { initVerify(key.first); update(signed); verify(signature) }
        } catch (e: Exception) { false }
        if (!ok) return Outcome.Bad("signature does not verify")
        return Outcome.Ok(parsed.signCount)
    }

    // --- pieces --------------------------------------------------------------------------------

    private fun clientData(json: ByteArray, type: String, challenge: ByteArray, rp: RelyingParty): Outcome<Unit> {
        val m = try { Json.parseObject(String(json, Charsets.UTF_8)) } catch (e: Exception) { return Outcome.Bad("client data is not JSON") }
        if (m["type"] != type) return Outcome.Bad("client data type is ${m["type"]}, not $type")
        val c = m["challenge"] as? String ?: return Outcome.Bad("client data carries no challenge")
        val presented = try { Base64.getUrlDecoder().decode(c) } catch (e: IllegalArgumentException) { return Outcome.Bad("challenge is not base64url") }
        if (!MessageDigest.isEqual(presented, challenge)) return Outcome.Bad("challenge mismatch")
        val origin = m["origin"] as? String
        if (origin !in rp.origins) return Outcome.Bad("origin $origin is not this relying party")
        return Outcome.Ok(Unit)
    }

    private class AuthData(val signCount: Long, val credential: Pair<ByteArray, ByteArray>?)

    private fun authenticatorData(bytes: ByteArray, rp: RelyingParty): Outcome<AuthData> {
        if (bytes.size < 37) return Outcome.Bad("authenticator data too short")
        if (!MessageDigest.isEqual(bytes.copyOfRange(0, 32), rp.idHash)) return Outcome.Bad("relying party id hash is not ${rp.id}")
        val flags = bytes[32].toInt()
        if (flags and 0x01 == 0) return Outcome.Bad("user presence not asserted")
        if (flags and 0x04 == 0) return Outcome.Bad("user verification not asserted")
        val count = ByteBuffer.wrap(bytes, 33, 4).int.toLong() and 0xFFFFFFFFL
        if (flags and 0x40 == 0) return Outcome.Ok(AuthData(count, null))
        if (bytes.size < 55) return Outcome.Bad("attested credential data too short")
        val len = ((bytes[53].toInt() and 0xFF) shl 8) or (bytes[54].toInt() and 0xFF)
        if (len == 0 || len > 1023 || bytes.size < 55 + len) return Outcome.Bad("credential id length $len is not credible")
        val credId = bytes.copyOfRange(55, 55 + len)
        val cose = bytes.copyOfRange(55 + len, bytes.size)
        // The COSE key is the next CBOR item; anything after it is extensions, which are ignored.
        val coseLen = try { Cbor.lengthOfFirstItem(cose) } catch (e: Exception) { return Outcome.Bad("public key is not CBOR") }
        return Outcome.Ok(AuthData(count, credId to cose.copyOfRange(0, coseLen)))
    }

    /** A JCA public key and the signature algorithm that goes with it, from a COSE key. */
    public fun publicKey(cose: ByteArray): Outcome<Pair<PublicKey, String>> {
        val m = try { Cbor.decode(cose) as? Map<*, *> } catch (e: Exception) { null } ?: return Outcome.Bad("public key is not a COSE map")
        return try {
            val alg = m[3L]
            when (m[1L]) {
                2L -> { // EC2
                    if (alg != ES256) return Outcome.Bad("an EC key signs ES256, not $alg")
                    if (m[-1L] != 1L) return Outcome.Bad("only curve P-256 is accepted")
                    val x = m[-2L] as ByteArray; val y = m[-3L] as ByteArray
                    val params = AlgorithmParameters.getInstance("EC").apply { init(ECGenParameterSpec("secp256r1")) }.getParameterSpec(ECParameterSpec::class.java)
                    val key = KeyFactory.getInstance("EC").generatePublic(ECPublicKeySpec(ECPoint(BigInteger(1, x), BigInteger(1, y)), params))
                    Outcome.Ok(key to "SHA256withECDSA")
                }
                3L -> { // RSA
                    if (alg != RS256) return Outcome.Bad("an RSA key signs RS256, not $alg")
                    val n = m[-1L] as ByteArray; val e = m[-2L] as ByteArray
                    if (n.size < 256) return Outcome.Bad("an RSA key is at least 2048 bits")
                    Outcome.Ok(KeyFactory.getInstance("RSA").generatePublic(RSAPublicKeySpec(BigInteger(1, n), BigInteger(1, e))) to "SHA256withRSA")
                }
                else -> Outcome.Bad("key type ${m[1L]} is not accepted")
            }
        } catch (e: Exception) {
            Outcome.Bad("public key is malformed")
        }
    }
}

/**
 * Enough CBOR to read WebAuthn: definite-length integers, byte and text strings, arrays, maps,
 * and the simple values. Indefinite lengths and tags are refused; nothing in a registration uses
 * them and a decoder that accepts more than it needs is a decoder with more to get wrong.
 */
public object Cbor {
    public fun decode(bytes: ByteArray): Any? = Reader(bytes).item()

    /** The encoded length of the first item, so a key can be cut out from what follows it. */
    public fun lengthOfFirstItem(bytes: ByteArray): Int = Reader(bytes).also { it.item() }.pos

    private class Reader(val b: ByteArray) {
        var pos = 0
        var depth = 0
        fun item(): Any? {
            require(++depth <= 16) { "CBOR nested too deep" }
            try {
                val ib = next()
                val major = ib shr 5; val info = ib and 0x1f
                return when (major) {
                    0 -> arg(info).toLong()
                    1 -> -1L - arg(info).toLong()
                    2 -> bytes(arg(info))
                    3 -> String(bytes(arg(info)), Charsets.UTF_8)
                    // A count is a claim; every item costs at least one byte, so a count larger than
                    // what remains is refused before anything is allocated for it.
                    4 -> { val n = count(arg(info)); val l = ArrayList<Any?>(); repeat(n) { l.add(item()) }; l }
                    5 -> { val n = count(arg(info)); val m = LinkedHashMap<Any?, Any?>(); repeat(n) { val k = item(); m[k] = item() }; m }
                    7 -> when (info) { 20 -> false; 21 -> true; 22 -> null; else -> throw IllegalArgumentException("simple value $info not accepted") }
                    else -> throw IllegalArgumentException("CBOR major type $major not accepted")
                }
            } finally { depth-- }
        }
        fun next(): Int { require(pos < b.size) { "CBOR truncated" }; return b[pos++].toInt() and 0xFF }
        fun count(n: Long): Int { require(n in 0..(b.size - pos).toLong()) { "CBOR count $n exceeds input" }; return n.toInt() }
        fun arg(info: Int): Long = when {
            info < 24 -> info.toLong()
            info == 24 -> next().toLong()
            info == 25 -> (next().toLong() shl 8) or next().toLong()
            info == 26 -> (0 until 4).fold(0L) { acc, _ -> (acc shl 8) or next().toLong() }
            info == 27 -> (0 until 8).fold(0L) { acc, _ -> (acc shl 8) or next().toLong() }
            else -> throw IllegalArgumentException("indefinite length not accepted")
        }
        fun bytes(n: Long): ByteArray {
            require(n in 0..(b.size - pos).toLong()) { "CBOR string length $n exceeds input" }
            return b.copyOfRange(pos, pos + n.toInt()).also { pos += n.toInt() }
        }
    }
}
