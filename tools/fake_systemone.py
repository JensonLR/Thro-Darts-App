#!/usr/bin/env python3
"""A stand-in for TypeSafe's System One endpoint, for looking at Tell THRØ (PD-119) without a key.

It answers `POST /v1/systemone` the way the real endpoint does — one answer per question, by name — but it
reads nothing: each Choice is answered by the option whose description shares the most words with the text,
each Noul is 0.1, each Score its first level. Enough to drive the desk's card end to end on a laptop; never a
measure of the model. Run it, then start the API with:

    THRO_TYPESAFE_API_KEY=fake THRO_TYPESAFE_ENDPOINT=http://localhost:8797/v1/systemone …

Nothing here is deployed, and the API only honours THRO_TYPESAFE_ENDPOINT when it is set by hand.
"""
import json
import re
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8797
WORD = re.compile(r"[a-z0-9]+")


def words(s):
    return set(WORD.findall(str(s).lower()))


def overlap_of(have, wanted):
    """Whole words, and a word of three letters or more that begins one — "Oct" for October, "Riverside" for Riverside A."""
    return sum(1 for w in wanted if w in have or any(len(h) >= 3 and w.startswith(h) for h in have))


def choose(text, question):
    criteria = question.get("criteria", {})
    keys = list(criteria)
    have = words(text)
    asks = str(question.get("instructions", "")).lower()
    scored = []
    for key in keys:
        desc = criteria.get(key) or ""
        overlap = overlap_of(have, words(desc) | words(key.replace("_", " ")))
        # "the one named first" / "named second": among the names that match, the earliest or the latest in the text.
        first_word = (WORD.findall(str(desc).lower()) or [""])[0]
        at = text.lower().find(first_word) if first_word and overlap else -1
        if at >= 0 and "named second" in asks:
            overlap += at / 1000.0
        elif at >= 0 and "named first" in asks:
            overlap += (1000 - at) / 100000.0
        scored.append((overlap, key))
    scored.sort(key=lambda kv: (-kv[0], keys.index(kv[1])))
    best, second = scored[0], (scored[1] if len(scored) > 1 else (0, None))
    total = sum(max(o, 0.1) for o, _ in scored)
    probabilities = {k: round(max(o, 0.1) / total, 3) for o, k in scored}
    if best[0] == 0:                      # nothing matched: the last option is the way out, if there is one
        key = "none" if "none" in criteria else best[1]
    else:
        key = best[1]
    p = probabilities.get(key, 0.5)
    if best[0] > 0 and best[0] == second[0]:
        p = min(p, 0.55)                  # a tie is a doubt
    probabilities[key] = max(probabilities[key], p)
    return {"type": "choice", "choice": key, "probabilities": probabilities, "confidence": round(p, 3)}


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        state = body.get("state", "")
        text = (state.get("text") or state.get("line") or json.dumps(state)) if isinstance(state, dict) else str(state)
        answers = {}
        for qid, q in body.get("questions", {}).items():
            kind = q.get("type")
            if kind == "choice":
                answers[qid] = choose(text, q)
            elif kind == "noul":
                # The one yes/no the desk asks that a stand-in can answer: a fixture is two names either side of a "v".
                fixture = "fixture" in str(q.get("instructions", "")).lower() and re.search(r"\sv\.?\s", text.lower()) is not None
                answers[qid] = {"type": "noul", "noul": 0.93 if fixture else 0.06}
            elif kind == "score":
                levels = q.get("criteria", [])
                answers[qid] = {"type": "score", "score": 0.0, "legend": {str(i): l for i, l in enumerate(levels)},
                                "probabilities": {str(i): (1.0 if i == 0 else 0.0) for i in range(len(levels))}, "confidence": 0.9}
        out = json.dumps({"model": "fake-systemone", "answers": answers, "usage": {"input_tokens": 0, "output_tokens": 0}}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)

    def log_message(self, fmt, *args):  # quiet
        pass


if __name__ == "__main__":
    print(f"fake System One on http://localhost:{PORT}/v1/systemone (answers by word overlap; reads nothing)")
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
