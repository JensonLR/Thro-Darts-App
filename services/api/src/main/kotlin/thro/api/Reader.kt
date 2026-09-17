package thro.api

import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.time.Duration
import thro.api.http.Contract

/**
 * A reading of what somebody wrote (PD-118): typed judgments from a System One model — a category, probabilities,
 * a place on a scale — never prose and never a decision. THRØ's code owns what happens next.
 *
 * A reader may answer null for any reason of its own: no key, no answer in time, an answer it could not read. The
 * caller carries on without a reading. Nothing a reader does may reach a report or a name.
 */
public interface Reader {
    /** What a report is about, whether it describes a risk to a child, and how serious it is. */
    public fun readReport(subjectKind: String, subjectName: String, reason: String): Reading?

    /** Whether a name somebody chose — a display name, a team name — is abuse, or claims to be somebody it is not. */
    public fun readName(kind: String, name: String): NameReading?
}

/**
 * A System One model as code sees it (PD-119): one request carrying a state and a map of typed questions, the answers
 * back by the same names — or null, for anything other than a whole answer in time. The JSON is written by the
 * caller, which knows its own questions; the wire is [TypeSafeReader]'s.
 */
public interface SystemOne {
    public fun answers(state: String, questions: String): Map<String, Any?>?
}

/** THRØ's reading of a report. [severity] sits on the levels in [TypeSafeReader.SEVERITY], 0 to 3. */
public data class Reading(val category: String, val categoryConfidence: Double, val childSafety: Double, val severity: Double, val model: String)

/** THRØ's reading of a name: the probability that it is abuse, and that it impersonates somebody. */
public data class NameReading(val abusive: Double, val impersonates: Double, val model: String)

/**
 * The reader over TypeSafe's System One endpoint, model `jev-latest` — one request per reading, the questions asked
 * together, the answers read back by name. The key is sent as a bearer token; it lives in the server's environment
 * and nowhere else, and the phone and the web never see it or the endpoint.
 */
public class TypeSafeReader(
    private val apiKey: String,
    private val endpoint: URI = URI("https://api.typesafe.ai/v1/systemone"),
    private val timeout: Duration = Duration.ofSeconds(3),
    private val model: String = "jev-latest",
) : Reader, SystemOne {
    public companion object {
        /** What the report is about. One of these wins; the distribution says how clearly. */
        public val CATEGORIES: Map<String, String> = linkedMapOf(
            "harassment" to "Unwanted contact, threats, intimidation, or persistent pestering of a person",
            "hate_or_slur" to "A slur, or abuse aimed at a group by race, religion, sex, sexuality, disability or the like",
            "sexual" to "Sexual content, advances, or suggestion, especially towards somebody young",
            "impersonation_or_fraud" to "Pretending to be an official body, a THRØ staff member, or another person; a scam",
            "cheating_or_dispute" to "A result, score or match that somebody says was recorded wrongly or dishonestly",
            "spam" to "Advertising, nonsense, or a report that says nothing about anybody",
            "other" to "None of the above",
        )
        /** Where a report sits, from nothing to act on to serious harm. Each level stands on its own. */
        public val SEVERITY: List<String> = listOf(
            "Nothing to act on: no rule is broken and nobody is harmed",
            "Mildly unpleasant: rude or careless, but nobody is at risk and no rule of the app is clearly broken",
            "Clearly against the rules: abuse, a slur, a false result, or impersonation, with no immediate danger",
            "Serious harm or danger: a child at risk, a threat of violence, sexual advances, or somebody's safety",
        )
        /** What the model is told about the place the words come from; the same for every question. */
        public const val CONTEXT: String =
            "THRØ is a darts league app used in pubs and clubs in the UK. Players may be under 18. Names are read by other " +
                "players and shown on public pages. A report is written by a player about a name or a match."
        private val client: HttpClient by lazy { HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(3)).build() }
    }

    override fun readReport(subjectKind: String, subjectName: String, reason: String): Reading? {
        val state = obj(
            "report" to obj("about" to subjectKind, "name_reported" to subjectName, "reason" to reason),
            "context" to CONTEXT,
        )
        val questions = obj(
            "category" to obj(
                "type" to "choice",
                "instructions" to "What is `report.reason` reporting about `report.name_reported`?",
                "criteria" to obj(*CATEGORIES.entries.map { it.key to it.value }.toTypedArray()),
            ),
            "child_safety" to obj(
                "type" to "noul",
                "instructions" to "Does `report.reason` describe a risk to a child, or an adult behaving inappropriately towards somebody under 18?",
                "criteria" to obj("true" to "A child is, or may be, at risk from what is described", "false" to "No child is involved, or nothing described puts one at risk"),
            ),
            "severity" to obj(
                "type" to "score",
                "instructions" to "How serious is what `report.reason` describes, for the person reported and for anybody around them?",
                "criteria" to arr(*SEVERITY.toTypedArray()),
            ),
        )
        val answers = ask(state, questions) ?: return null
        val category = answers["category"] as? Map<*, *> ?: return null
        val child = answers["child_safety"] as? Map<*, *> ?: return null
        val severity = answers["severity"] as? Map<*, *> ?: return null
        return Reading(
            category = category["choice"] as? String ?: return null,
            categoryConfidence = num(category["confidence"]) ?: return null,
            childSafety = num(child["noul"]) ?: return null,
            severity = num(severity["score"]) ?: return null,
            model = model,
        )
    }

    override fun readName(kind: String, name: String): NameReading? {
        val state = obj("name" to name, "kind" to "$kind name", "context" to CONTEXT)
        val questions = obj(
            "abusive" to obj(
                "type" to "noul",
                "instructions" to "Is `name` abusive: a slur, hateful towards a group, sexual, or a threat?",
                "criteria" to obj("true" to "A reasonable adult would find it abusive, hateful, sexual or threatening", "false" to "Ordinary, including a pub's name, a joke, or an edgy but harmless name"),
            ),
            "impersonates" to obj(
                "type" to "noul",
                "instructions" to "Does `name` claim to be an official body, THRØ itself or its staff, or a well-known real person?",
            ),
        )
        val answers = ask(state, questions) ?: return null
        val abusive = (answers["abusive"] as? Map<*, *>)?.let { num(it["noul"]) } ?: return null
        val impersonates = (answers["impersonates"] as? Map<*, *>)?.let { num(it["noul"]) } ?: return null
        return NameReading(abusive, impersonates, model)
    }

    /** One request; the answers by name, or null for anything other than a whole answer in time. */
    override fun answers(state: String, questions: String): Map<String, Any?>? = ask(state, questions)

    private fun ask(state: String, questions: String): Map<String, Any?>? = try {
        val body = """{"state":$state,"model":${Contract.q(model)},"questions":$questions}"""
        val request = HttpRequest.newBuilder(endpoint).timeout(timeout)
            .header("Authorization", "Bearer $apiKey").header("Content-Type", "application/json")
            .POST(HttpRequest.BodyPublishers.ofString(body)).build()
        val response = client.send(request, HttpResponse.BodyHandlers.ofString())
        if (response.statusCode() != 200) null
        else {
            @Suppress("UNCHECKED_CAST")
            Json.parseObject(response.body())["answers"] as? Map<String, Any?>
        }
    } catch (e: Exception) {
        // A reading that does not come is no reading: a timeout, a refused connection, a body that is not JSON.
        null
    }

    private fun num(v: Any?): Double? = (v as? Number)?.toDouble()
    private fun obj(vararg pairs: Pair<String, Any?>): String = pairs.joinToString(",", "{", "}") { (k, v) -> "${Contract.q(k)}:${json(v)}" }
    private fun arr(vararg items: Any?): String = items.joinToString(",", "[", "]") { json(it) }
    /** Values are strings, numbers, or JSON already written by [obj] and [arr] (a String starting with `{` or `[`). */
    private fun json(v: Any?): String = when (v) {
        null -> "null"
        is Number, is Boolean -> v.toString()
        is String -> if (v.startsWith("{") || v.startsWith("[")) v else Contract.q(v)
        else -> Contract.q(v.toString())
    }
}
