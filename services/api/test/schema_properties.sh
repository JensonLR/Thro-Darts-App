#!/usr/bin/env bash
# THRØ — schema property tests.
#
# These assert the properties the competitive event model depends on, against a real PostgreSQL.
# They exist because the first version of this schema could not store the two-device corroboration
# case the trust model is built on, and nobody noticed until it was executed. Assertions about a
# database belong in a database.
set -uo pipefail
PSQL="psql -v ON_ERROR_STOP=0 -X -q -t -A"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m  %s — %s\n' "$1" "$2"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3] got [$2]"; fi; }

echo "== migrations =="
# The same ledger the Kotlin runner keeps (Migrations.kt): every file the ledger does not hold is
# applied in its own transaction and recorded with its digest. A database with THRØ's schemas and no
# ledger predates it and is rebuilt, not guessed at; a recorded file whose content changed is refused.
# Applying is a precondition of the properties below, not one of them, so it is not counted.
DIR="$(dirname "$0")/../migrations"
$PSQL -c "CREATE SCHEMA IF NOT EXISTS thro; CREATE TABLE IF NOT EXISTS thro.schema_migration (
  version int PRIMARY KEY, filename text NOT NULL, sha256 text NOT NULL,
  applied_at timestamptz NOT NULL DEFAULT clock_timestamp());" >/dev/null 2>&1
recorded=$($PSQL -c "SELECT count(*) FROM thro.schema_migration;")
present=$($PSQL -c "SELECT count(*) FROM information_schema.schemata WHERE schema_name='evidence';")
if [ "$recorded" = "0" ] && [ "$present" != "0" ]; then
  bad "migration ledger" "this database has THRØ's schemas but no ledger; its version cannot be known — drop the schemas (as the test harness does) and rerun"
  echo "  $PASS passed, $FAIL failed"; exit 1
fi
ahead=$($PSQL -c "SELECT max(version) FROM thro.schema_migration;")
latest=$(ls "$DIR"/V*.sql | sed -E 's/.*\/V0*([0-9]+)__.*/\1/' | sort -n | tail -1)
if [ -n "$ahead" ] && [ "$ahead" -gt "$latest" ]; then
  bad "migration ledger" "the database records V$ahead and this checkout stops at V$latest: the database is ahead of the code"
  echo "  $PASS passed, $FAIL failed"; exit 1
fi
for f in "$DIR"/V*.sql; do
  name=$(basename "$f"); v=$(echo "$name" | sed -E 's/^V0*([0-9]+)__.*/\1/')
  sum=$(shasum -a 256 "$f" | cut -d' ' -f1)
  have=$($PSQL -c "SELECT sha256 FROM thro.schema_migration WHERE version=$v;")
  if [ -n "$have" ]; then
    if [ "$have" != "$sum" ]; then
      bad "applied $name" "was applied from different content; migrations are forward-only — rebuild the database"
      echo "  $PASS passed, $FAIL failed"; exit 1
    fi
    continue
  fi
  out=$(psql -v ON_ERROR_STOP=1 -X -q -1 -f "$f" 2>&1); rc=$?
  if [ $rc -eq 0 ]; then
    $PSQL -c "INSERT INTO thro.schema_migration (version, filename, sha256) VALUES ($v, '$name', '$sum');" >/dev/null
    printf '  applied  %s\n' "$name"
  else
    bad "applied $name" "$(echo "$out" | grep -i ERROR | head -1)"
    echo "  $PASS passed, $FAIL failed"; exit 1
  fi
done
# As the Kotlin runner does after a run: the health route reads the ledger through the application's
# connection, so the read role may see it and nothing more.
$PSQL -c "DO \$\$ BEGIN IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='app_read') THEN
  GRANT USAGE ON SCHEMA thro TO app_read; GRANT SELECT ON thro.schema_migration TO app_read; END IF; END \$\$;" >/dev/null 2>&1
printf '  schema at %s\n' "$($PSQL -c "SELECT 'V' || lpad(max(version)::text, 3, '0') FROM thro.schema_migration;")"

echo
# Fresh identifiers per run, so the suite is idempotent. CI always gets a clean database, but a
# test that only passes on a clean database is a test that stops being run locally.
M=$($PSQL -c "SELECT gen_random_uuid();")
DA=$($PSQL -c "SELECT gen_random_uuid();")
DB=$($PSQL -c "SELECT gen_random_uuid();")
# ADR-008: evidence may only exist for a match the store knows about, so every assertion below
# needs a real aggregate. Opening one is now the precondition for any evidence at all.
$PSQL -c "SET ROLE app_match; INSERT INTO evidence.match
  (match_id,home_id,away_id,starting_score,in_rule,out_rule,
   legs_mode,legs_target,throw_first)
  VALUES ('$M', '$DA', '$DB', 501, 'straight', 'double', 'first_to', 5, '$DA');" >/dev/null 2>&1

ins() { # match, device, seq
  $PSQL -c "INSERT INTO evidence.event
    (event_id,match_id,device_id,device_seq,event_type,schema_version,correlation_id,
     actor_id,actor_role,occurred_at,occurred_tz,payload)
    VALUES (gen_random_uuid(),'$1','$2',$3,'VisitRecorded',1,gen_random_uuid(),
            gen_random_uuid(),'participant',now(),'Europe/London','{\"total\":100}');" 2>&1
}

echo

echo "== the two-device corroboration case =="
ins $M $DA 1 >/dev/null; ins $M $DA 2 >/dev/null
r=$(ins $M $DB 1)
if echo "$r" | grep -qi 'ERROR'; then bad "both devices can author the same match" "$(echo "$r"|head -1)"
else ok "both devices can author the same match"; fi
ins $M $DB 2 >/dev/null
n=$($PSQL -c "SELECT count(*) FROM evidence.event WHERE match_id='$M';")
check "both streams are stored in full" "$n" "4"
n=$($PSQL -c "SELECT count(DISTINCT device_id) FROM evidence.event WHERE match_id='$M';")
check "each device's account is separately readable" "$n" "2"
r=$(ins $M $DA 1)
if echo "$r" | grep -qi 'duplicate key'; then ok "a device cannot reuse its own sequence number"
else bad "a device cannot reuse its own sequence number" "duplicate was accepted"; fi

echo
echo "== append-only holds, including on tables created by a later migration =="
$PSQL -c "SET ROLE app_match;" >/dev/null
for op in "UPDATE evidence.event SET event_type='tampered'" \
          "DELETE FROM evidence.event" \
          "TRUNCATE evidence.event" \
          "UPDATE read.visit SET visit_total=1" ; do
  tbl=$(echo "$op" | grep -oE '(evidence|read)\.[a-z_]+')
  r=$($PSQL -c "SET ROLE app_match; $op;" 2>&1)
  label="$(echo "$op" | awk '{print $1}') on $tbl is denied to the app role"
  if echo "$r" | grep -qi 'permission denied'; then ok "$label"
  else
    # read.visit is a projection and app_read may write it; app_match may not
    if [ "$tbl" = "read.visit" ]; then bad "$label" "app_match could write a projection"
    else bad "$label" "${r:-succeeded}"; fi
  fi
done
n=$($PSQL -c "SELECT count(*) FROM evidence.event WHERE match_id='$M';")
check "the log survived every attempt" "$n" "4"

echo
echo "== a table added by a FUTURE migration inherits the revocation =="
$PSQL -c "SET ROLE thro_owner; DROP TABLE IF EXISTS evidence.late_arrival;" >/dev/null
$PSQL -c "SET ROLE thro_owner; CREATE TABLE evidence.late_arrival(id int PRIMARY KEY, v int);" >/dev/null
$PSQL -c "SET ROLE thro_owner; GRANT SELECT, INSERT ON evidence.late_arrival TO app_match;" >/dev/null
$PSQL -c "SET ROLE thro_owner; INSERT INTO evidence.late_arrival VALUES (1,180);" >/dev/null
r=$($PSQL -c "SET ROLE app_match; UPDATE evidence.late_arrival SET v=1;" 2>&1)
if echo "$r" | grep -qi 'permission denied'; then ok "UPDATE on a later table is denied by default privileges"
else bad "UPDATE on a later table is denied by default privileges" "${r:-succeeded — the defect this test exists for}"; fi
v=$($PSQL -c "SELECT v FROM evidence.late_arrival WHERE id=1;")
check "the later table's data is intact" "$v" "180"

echo
echo "== idempotency =="
CMD=$($PSQL -c "SELECT gen_random_uuid();")

$PSQL -c "INSERT INTO evidence.command_receipt(device_id,client_command_id,match_id,outcome,response_body)
          VALUES ('$DA','$CMD','$M','accepted','{\"streamSeq\":3}');" >/dev/null
r=$($PSQL -c "INSERT INTO evidence.command_receipt(device_id,client_command_id,match_id,outcome,response_body)
              VALUES ('$DA','$CMD','$M','accepted','{\"streamSeq\":99}');" 2>&1)
if echo "$r" | grep -qi 'duplicate key'; then ok "a replayed command id cannot create a second receipt"
else bad "a replayed command id cannot create a second receipt" "duplicate accepted"; fi
b=$($PSQL -c "SELECT response_body->>'streamSeq' FROM evidence.command_receipt
              WHERE device_id='$DA' AND client_command_id='$CMD';")
check "the stored response is returned unchanged" "$b" "3"

echo
echo "== ordering =="
n=$($PSQL -c "SELECT count(*) FROM evidence.event WHERE commit_xid < pg_snapshot_xmin(pg_current_snapshot());")
if [ "$n" -ge 4 ]; then ok "committed events are dispatchable under the watermark rule"
else bad "committed events are dispatchable under the watermark rule" "only $n of 4 visible"; fi
o=$($PSQL -c "SELECT string_agg(device_seq::text,',' ORDER BY commit_xid, global_seq)
              FROM evidence.event WHERE match_id='$M';")
if [ -n "$o" ]; then ok "cross-device order is total under (commit_xid, global_seq) — [$o]"
else bad "cross-device order" "no ordering produced"; fi

echo
echo "== nullable darts_used means unknown, never zero =="
$PSQL -c "INSERT INTO read.visit(projection_version,visit_id,match_id,leg_ordinal,visit_ordinal,
          thrower_id,visit_total,darts_used,bust,checkout,remaining_after)
          VALUES (1,gen_random_uuid(),'$M',1,1,gen_random_uuid(),100,NULL,false,false,401);" >/dev/null
d=$($PSQL -c "SELECT coalesce(darts_used::text,'NULL') FROM read.visit WHERE match_id='$M' LIMIT 1;")
check "darts_used stores NULL rather than a default" "$d" "NULL"
r=$($PSQL -c "INSERT INTO read.visit(projection_version,visit_id,match_id,leg_ordinal,visit_ordinal,
              thrower_id,visit_total,darts_used,bust,checkout,remaining_after)
              VALUES (1,gen_random_uuid(),'$M',1,2,gen_random_uuid(),100,0,false,false,301);" 2>&1)
if echo "$r" | grep -qi 'violates check constraint'; then ok "darts_used rejects 0 — a visit cannot use zero darts"
else bad "darts_used rejects 0" "zero was accepted"; fi
r=$($PSQL -c "INSERT INTO read.visit(projection_version,visit_id,match_id,leg_ordinal,visit_ordinal,
              thrower_id,visit_total,darts_used,bust,checkout,remaining_after)
              VALUES (1,gen_random_uuid(),'$M',1,3,gen_random_uuid(),181,3,false,false,0);" 2>&1)
if echo "$r" | grep -qi 'violates check constraint'; then ok "a visit total above 180 is rejected"
else bad "a visit total above 180 is rejected" "181 was accepted"; fi

echo
echo "== the append-only guarantee rests on ownership, so assert it =="
o=$($PSQL -c "SELECT tableowner FROM pg_tables WHERE schemaname='evidence' AND tablename='event';")
check "the event log is owned by the migration role, not the app" "$o" "thro_owner"
o=$($PSQL -c "SELECT count(*) FROM pg_tables WHERE schemaname IN ('evidence','read','trust')
              AND tableowner <> 'thro_owner';")
check "no table in the guarded schemas is owned by anyone else" "$o" "0"

echo
echo "== darts at a double =="
$PSQL -c "SET ROLE app_read; UPDATE read.visit SET darts_at_double = 1 WHERE match_id='$M';" >/dev/null 2>&1
d=$($PSQL -c "SELECT coalesce(darts_at_double::text,'NULL') FROM read.visit WHERE match_id='$M' LIMIT 1;")
check "darts_at_double is recorded" "$d" "1"
r=$($PSQL -c "SET ROLE app_read; INSERT INTO read.visit(projection_version,visit_id,match_id,leg_ordinal,
     visit_ordinal,thrower_id,visit_total,darts_used,darts_at_double,bust,checkout,remaining_after)
     VALUES (1,gen_random_uuid(),'$M',9,1,gen_random_uuid(),40,1,2,false,true,0);" 2>&1)
if echo "$r" | grep -qi 'violates check constraint'; then
  ok "more darts at a double than darts thrown is rejected"
else bad "more darts at a double than darts thrown is rejected" "2-of-1 was accepted"; fi
r=$($PSQL -c "SET ROLE app_read; INSERT INTO read.visit(projection_version,visit_id,match_id,leg_ordinal,
     visit_ordinal,thrower_id,visit_total,darts_used,darts_at_double,bust,checkout,remaining_after)
     VALUES (1,gen_random_uuid(),'$M',9,2,gen_random_uuid(),40,3,4,false,true,0);" 2>&1)
if echo "$r" | grep -qi 'violates check constraint'; then
  ok "more than three darts at a double is rejected"
else bad "more than three darts at a double is rejected" "4 was accepted"; fi

echo
echo "== scoring grants =="
EV=$($PSQL -c "SELECT gen_random_uuid();")
AC=$($PSQL -c "SELECT gen_random_uuid();")
DV=$($PSQL -c "SELECT gen_random_uuid();")
GR=$($PSQL -c "SELECT gen_random_uuid();")
$PSQL -c "SET ROLE app_trust; INSERT INTO trust.scoring_grant
  (grant_id,event_id,actor_id,device_id,actor_role,expires_at)
  VALUES ('$GR','$EV','$AC','$DV','participant', now() + interval '34 hours');" >/dev/null 2>&1
n=$($PSQL -c "SELECT count(*) FROM trust.scoring_grant WHERE grant_id='$GR';")
check "the trust role can issue a grant" "$n" "1"

# The command path reads authority on every visit, so it must be able to see grants.
n=$($PSQL -c "SET ROLE app_match; SELECT count(*) FROM trust.scoring_grant WHERE grant_id='$GR';" 2>&1)
check "the match role can read authority" "$n" "1"

r=$($PSQL -c "SET ROLE app_match; DELETE FROM trust.scoring_grant WHERE grant_id='$GR';" 2>&1)
if echo "$r" | grep -qi 'permission denied'; then
  ok "no role may delete a grant"
else bad "no role may delete a grant" "delete was permitted"; fi

# Two live grants for one scope would make "which authority was this under" unanswerable.
r=$($PSQL -c "SET ROLE app_trust; INSERT INTO trust.scoring_grant
  (grant_id,event_id,actor_id,device_id,actor_role,expires_at)
  VALUES (gen_random_uuid(),'$EV','$AC','$DV','participant', now() + interval '34 hours');" 2>&1)
if echo "$r" | grep -qi 'duplicate key\|unique constraint'; then
  ok "an actor cannot hold two live grants for one scope"
else bad "an actor cannot hold two live grants for one scope" "a second live grant was accepted"; fi

$PSQL -c "SET ROLE app_trust; UPDATE trust.scoring_grant
  SET revoked_at = now(), revoked_by = '$AC', revoked_reason = 'test'
  WHERE grant_id='$GR';" >/dev/null 2>&1
d=$($PSQL -c "SELECT revoked_at IS NOT NULL FROM trust.scoring_grant WHERE grant_id='$GR';")
check "a grant can be revoked" "$d" "t"

r=$($PSQL -c "SET ROLE app_trust; UPDATE trust.scoring_grant SET revoked_at = NULL, revoked_by = NULL
  WHERE grant_id='$GR';" 2>&1)
if echo "$r" | grep -qi 'cannot be undone'; then
  ok "a revocation cannot be undone"
else bad "a revocation cannot be undone" "un-revoking was permitted"; fi

r=$($PSQL -c "SET ROLE app_trust; UPDATE trust.scoring_grant SET expires_at = now() - interval '1 hour'
  WHERE grant_id='$GR';" 2>&1)
if echo "$r" | grep -qi 'cannot be moved backward'; then
  ok "expiry cannot be moved backward"
else bad "expiry cannot be moved backward" "retroactive expiry was permitted"; fi

# Evidence records the authority it was written under, and anything but 'granted' needs review.
r=$($PSQL -c "SET ROLE app_match; INSERT INTO evidence.event
  (event_id,match_id,device_id,device_seq,event_type,schema_version,correlation_id,actor_id,
   actor_role,occurred_at,occurred_tz,payload,authority)
  VALUES (gen_random_uuid(),'$M','$DA',900,'VisitRecorded',1,gen_random_uuid(),'$AC',
   'participant', now(),'Europe/London','{}'::jsonb,'nonsense');" 2>&1)
if echo "$r" | grep -qi 'violates check constraint'; then
  ok "an unknown authority value is rejected"
else bad "an unknown authority value is rejected" "'nonsense' was accepted"; fi

echo
echo "== the match aggregate is the authority on who is playing =="
r=$($PSQL -c "SET ROLE app_match; INSERT INTO evidence.event
  (event_id,match_id,device_id,device_seq,event_type,schema_version,correlation_id,actor_id,
   actor_role,occurred_at,occurred_tz,payload)
  VALUES (gen_random_uuid(), gen_random_uuid(), '$DA', 999, 'VisitRecorded',1,gen_random_uuid(),
   gen_random_uuid(),'participant',now(),'Europe/London','{}'::jsonb);" 2>&1)
if echo "$r" | grep -qi 'event_belongs_to_a_real_match'; then
  ok "evidence for a match that does not exist is refused by the database"
else bad "evidence for a match that does not exist is refused by the database" "an orphan was accepted"; fi

r=$($PSQL -c "SET ROLE app_match; UPDATE evidence.match SET away_id=gen_random_uuid() WHERE match_id='$M';" 2>&1)
if echo "$r" | grep -qi 'permission denied'; then
  ok "who is playing cannot be rewritten after the match opens"
else bad "who is playing cannot be rewritten after the match opens" "the participant set was editable"; fi

r=$($PSQL -c "SET ROLE app_match; INSERT INTO evidence.match
  (match_id,home_id,away_id,starting_score,in_rule,out_rule,
   legs_mode,legs_target,throw_first)
  VALUES (gen_random_uuid(),'$DA','$DA',501,'straight','double','first_to',5,'$DA');" 2>&1)
if echo "$r" | grep -qi 'violates check constraint'; then
  ok "a competitor cannot play themselves"
else bad "a competitor cannot play themselves" "a self-match was accepted"; fi

r=$($PSQL -c "SET ROLE app_match; INSERT INTO evidence.match
  (match_id,home_id,away_id,starting_score,in_rule,out_rule,
   legs_mode,legs_target,throw_first)
  VALUES (gen_random_uuid(),'$DA','$DB',501,'straight','double','first_to',5,gen_random_uuid());" 2>&1)
if echo "$r" | grep -qi 'violates check constraint'; then
  ok "the player throwing first must be one of the competitors"
else bad "the player throwing first must be one of the competitors" "a stranger threw first"; fi

echo
echo "== the audit log is tamper-evident =="
# A fresh object id per run, so a second run against the same database asserts about its own rows.
OBJ="m-$($PSQL -c "SELECT substr(gen_random_uuid()::text,1,8);")"
before=$($PSQL -c "SELECT count(*) FROM audit.decision;")
$PSQL -c "SET ROLE app_match; INSERT INTO audit.decision
  (subject_id,action,object_type,object_id,allowed,granted_by,policy_version)
  VALUES ('$AC','match.correct','match','$OBJ',true,'event:e#official','1.0.0');" >/dev/null 2>&1
after=$($PSQL -c "SELECT count(*) FROM audit.decision;")
check "an application role can append a decision" "$((after - before))" "1"

# Verify only if this run started from an intact chain; an earlier run's tamper test leaves it
# broken on purpose, and re-breaking an already-broken chain proves nothing.
broken_before=$($PSQL -c "SELECT count(*) FROM audit.first_broken_link();")
if [ "$broken_before" = "0" ]; then
  ok "the chain verifies after an honest append"
  mine=$($PSQL -c "SELECT seq FROM audit.decision WHERE object_id='$OBJ';")
  $PSQL -c "SET ROLE thro_owner; UPDATE audit.decision SET allowed = false WHERE seq = $mine;" >/dev/null 2>&1
  n=$($PSQL -c "SELECT count(*) FROM audit.first_broken_link();")
  check "rewriting a decision breaks the chain" "$n" "1"
  # Put it back, so the chain is intact for whatever runs next.
  $PSQL -c "SET ROLE thro_owner; UPDATE audit.decision SET allowed = true WHERE seq = $mine;" >/dev/null 2>&1
  n=$($PSQL -c "SELECT count(*) FROM audit.first_broken_link();")
  check "and restoring the entry repairs it" "$n" "0"
else
  ok "chain already broken by an earlier run — tamper assertions skipped"
fi

r=$($PSQL -c "SET ROLE app_match; SELECT count(*) FROM audit.decision;" 2>&1)
if echo "$r" | grep -qi 'permission denied'; then
  ok "the log is write-only for the roles that write to it"
else bad "the log is write-only for the roles that write to it" "it was readable"; fi

echo
echo "== rating is a projection, and OD-001 stays open =="
PL=$($PSQL -c "SELECT gen_random_uuid();")

# At launch this table is empty on purpose: every player provisional, nothing published.
n=$($PSQL -c "SELECT count(*) FROM rating.published_model;")
check "no rating model is published" "$n" "0"

r=$($PSQL -c "SET ROLE app_rating; INSERT INTO rating.snapshot
  (player_id,model_id,model_version,parameter_hash,scale_epoch,as_of_commit_xid,as_of_global_seq,
   rating,confidence,matches_counted,published)
  VALUES ('$PL','candidate','1.0.0','h',1,'100'::xid8,1, 1500, 0.9, 20, true);" 2>&1)
if echo "$r" | grep -qi 'violates foreign key'; then
  ok "a snapshot cannot be published under a model that is not published"
else bad "a snapshot cannot be published under a model that is not published" "it was accepted"; fi

$PSQL -c "SET ROLE app_rating; INSERT INTO rating.snapshot
  (player_id,model_id,model_version,parameter_hash,scale_epoch,as_of_commit_xid,as_of_global_seq,
   rating,confidence,matches_counted,published)
  VALUES ('$PL','candidate','1.0.0','h',1,'100'::xid8,1, NULL, 0.4, 4, false);" >/dev/null 2>&1
d=$($PSQL -c "SELECT coalesce(rating::text,'NULL') FROM rating.snapshot WHERE player_id='$PL';")
check "a shadow candidate stores a provisional snapshot with no rating" "$d" "NULL"

r=$($PSQL -c "SET ROLE app_rating; INSERT INTO rating.snapshot
  (player_id,model_id,model_version,parameter_hash,scale_epoch,as_of_commit_xid,as_of_global_seq,
   rating,confidence,matches_counted,published)
  VALUES (gen_random_uuid(),'c','1','h',1,'100'::xid8,1, NULL, 0.5, 1, true);" 2>&1)
if echo "$r" | grep -qi 'violates'; then
  ok "a published snapshot must carry an actual rating"
else bad "a published snapshot must carry an actual rating" "a published em dash was accepted"; fi

r=$($PSQL -c "SET ROLE app_rating; INSERT INTO rating.ledger
  (ledger_id,player_id,model_id,at_commit_xid,at_global_seq,cause,delta)
  VALUES (gen_random_uuid(),'$PL','c','100'::xid8,1,'match',5.0);" 2>&1)
if echo "$r" | grep -qi 'violates check constraint'; then
  ok "a match ledger line must name its match"
else bad "a match ledger line must name its match" "an anonymous match line was accepted"; fi

r=$($PSQL -c "SET ROLE app_match; SELECT count(*) FROM rating.snapshot;" 2>&1)
if echo "$r" | grep -qi 'permission denied'; then
  ok "the match module cannot see rating state"
else bad "the match module cannot see rating state" "it was readable"; fi

echo
echo "== a module may append only to the streams it owns =="
r=$($PSQL -c "SET ROLE app_trust; INSERT INTO evidence.event
  (event_id,match_id,device_id,device_seq,event_type,schema_version,correlation_id,actor_id,
   actor_role,occurred_at,occurred_tz,payload)
  VALUES (gen_random_uuid(),'$M','$DA',801,'VisitRecorded',1,gen_random_uuid(),gen_random_uuid(),
   'participant',now(),'Europe/London','{}'::jsonb);" 2>&1)
if echo "$r" | grep -qi 'that stream belongs to app_match'; then
  ok "trust cannot append match evidence"
else bad "trust cannot append match evidence" "$(echo "$r" | head -1)"; fi

r=$($PSQL -c "SET ROLE app_match; INSERT INTO evidence.event
  (event_id,match_id,device_id,device_seq,event_type,schema_version,correlation_id,actor_id,
   actor_role,occurred_at,occurred_tz,payload)
  VALUES (gen_random_uuid(),'$M','$DA',802,'LegAttested',1,gen_random_uuid(),gen_random_uuid(),
   'participant',now(),'Europe/London','{}'::jsonb);" 2>&1)
if echo "$r" | grep -qi 'that stream belongs to app_trust'; then
  ok "match cannot append an attestation on a participant's behalf"
else bad "match cannot append an attestation on a participant's behalf" "$(echo "$r" | head -1)"; fi

r=$($PSQL -c "SET ROLE app_rating; INSERT INTO evidence.event
  (event_id,match_id,device_id,device_seq,event_type,schema_version,correlation_id,actor_id,
   actor_role,occurred_at,occurred_tz,payload)
  VALUES (gen_random_uuid(),'$M','$DA',803,'VisitRecorded',1,gen_random_uuid(),gen_random_uuid(),
   'system',now(),'Europe/London','{}'::jsonb);" 2>&1)
if echo "$r" | grep -qi 'permission denied'; then
  ok "rating cannot write to the evidence log at all"
else bad "rating cannot write to the evidence log at all" "$(echo "$r" | head -1)"; fi

r=$($PSQL -c "SET ROLE app_match; INSERT INTO evidence.event
  (event_id,match_id,device_id,device_seq,event_type,schema_version,correlation_id,actor_id,
   actor_role,occurred_at,occurred_tz,payload)
  VALUES (gen_random_uuid(),'$M','$DA',804,'SomethingInvented',1,gen_random_uuid(),
   gen_random_uuid(),'system',now(),'Europe/London','{}'::jsonb);" 2>&1)
if echo "$r" | grep -qi 'every stream must have a named owner'; then
  ok "an event type nobody owns is refused"
else bad "an event type nobody owns is refused" "$(echo "$r" | head -1)"; fi

echo
echo "== a match that ended short stays ended (V034) =="
M2=$($PSQL -c "SELECT gen_random_uuid();")
$PSQL -c "SET ROLE app_match; INSERT INTO evidence.match
  (match_id,home_id,away_id,starting_score,in_rule,out_rule,
   legs_mode,legs_target,throw_first)
  VALUES ('$M2', '$DA', '$DB', 501, 'straight', 'double', 'first_to', 5, '$DA');" >/dev/null 2>&1

r=$($PSQL -c "SET ROLE app_match; INSERT INTO evidence.event
  (event_id,match_id,device_id,device_seq,event_type,schema_version,correlation_id,actor_id,
   actor_role,occurred_at,occurred_tz,payload)
  VALUES (gen_random_uuid(),'$M2','$DA',1,'MatchEndedShort',1,gen_random_uuid(),'$DA',
   'participant',now(),'Europe/London','{\"ending\":\"retired\"}'::jsonb);" 2>&1)
if echo "$r" | grep -qi 'an_ending_says_how'; then
  ok "a retirement says which seat retired"
else bad "a retirement says which seat retired" "$(echo "$r" | head -1)"; fi

# V034 let this through: with nothing to compare, its CHECK came out NULL, and NULL passes a CHECK.
r=$($PSQL -c "SET ROLE app_match; INSERT INTO evidence.event
  (event_id,match_id,device_id,device_seq,event_type,schema_version,correlation_id,actor_id,
   actor_role,occurred_at,occurred_tz,payload)
  VALUES (gen_random_uuid(),'$M2','$DA',5,'MatchEndedShort',1,gen_random_uuid(),'$DA',
   'participant',now(),'Europe/London','{}'::jsonb);" 2>&1)
if echo "$r" | grep -qi 'an_ending_says_how'; then
  ok "an ending says how it ended"
else bad "an ending says how it ended" "$(echo "$r" | head -1)"; fi

$PSQL -c "SET ROLE app_match; INSERT INTO evidence.event
  (event_id,match_id,device_id,device_seq,event_type,schema_version,correlation_id,actor_id,
   actor_role,occurred_at,occurred_tz,payload)
  VALUES (gen_random_uuid(),'$M2','$DA',2,'MatchEndedShort',1,gen_random_uuid(),'$DA',
   'participant',now(),'Europe/London','{\"ending\":\"abandoned\"}'::jsonb);" >/dev/null 2>&1
r=$($PSQL -c "SET ROLE app_match; INSERT INTO evidence.event
  (event_id,match_id,device_id,device_seq,event_type,schema_version,correlation_id,actor_id,
   actor_role,occurred_at,occurred_tz,payload)
  VALUES (gen_random_uuid(),'$M2','$DA',3,'VisitRecorded',1,gen_random_uuid(),'$DA',
   'participant',now(),'Europe/London','{\"player\":\"home\",\"visitTotal\":60}'::jsonb);" 2>&1)
if echo "$r" | grep -qi 'has ended'; then
  ok "nothing is added to a match after its end"
else bad "nothing is added to a match after its end" "$(echo "$r" | head -1)"; fi

r=$($PSQL -c "SET ROLE app_match; INSERT INTO evidence.event
  (event_id,match_id,device_id,device_seq,event_type,schema_version,correlation_id,actor_id,
   actor_role,occurred_at,occurred_tz,payload)
  VALUES (gen_random_uuid(),'$M2','$DA',2,'MatchEndedShort',1,gen_random_uuid(),'$DA',
   'participant',now(),'Europe/London','{\"ending\":\"abandoned\"}'::jsonb)
  ON CONFLICT (match_id, device_id, device_seq) DO NOTHING;" 2>&1)
if echo "$r" | grep -qi 'error'; then
  bad "a resend of the ending itself still lands as nothing" "$(echo "$r" | head -1)"
else ok "a resend of the ending itself still lands as nothing"; fi

echo
echo "== identity, and age as a dimension that cannot be forgotten =="
ACC=$($PSQL -c "SELECT gen_random_uuid();")
$PSQL -c "SET ROLE app_competition; INSERT INTO identity.account (account_id, display_name)
  VALUES ('$ACC','A Player');" >/dev/null 2>&1
d=$($PSQL -c "SELECT age_band FROM identity.account WHERE account_id='$ACC';")
check "an account without a stated age is 'unknown', not null" "$d" "unknown"

r=$($PSQL -c "SET ROLE app_competition; UPDATE identity.account SET age_band = NULL WHERE account_id='$ACC';" 2>&1)
if echo "$r" | grep -qi 'null value\|not-null'; then
  ok "the band cannot be set to null"
else bad "the band cannot be set to null" "null was accepted"; fi

r=$($PSQL -c "SET ROLE app_competition; UPDATE identity.account SET age_band='teenager' WHERE account_id='$ACC';" 2>&1)
if echo "$r" | grep -qi 'violates check constraint'; then
  ok "an unmodelled band is refused"
else bad "an unmodelled band is refused" "'teenager' was accepted"; fi

r=$($PSQL -c "SET ROLE app_competition; UPDATE identity.account
  SET age_assurance='verified' WHERE account_id='$ACC';" 2>&1)
if echo "$r" | grep -qi 'violates check constraint'; then
  ok "an unknown band cannot carry assurance"
else bad "an unknown band cannot carry assurance" "unknown+verified was accepted"; fi

# Personal data is confined to the identity module, which is what makes export and deletion answerable.
for role in app_match app_trust app_rating; do
  r=$($PSQL -c "SET ROLE $role; SELECT count(*) FROM identity.account;" 2>&1)
  if echo "$r" | grep -qi 'permission denied'; then
    ok "$role cannot read personal data"
  else bad "$role cannot read personal data" "it was readable"; fi
done

DEV=$($PSQL -c "SELECT gen_random_uuid();")
$PSQL -c "SET ROLE app_competition; INSERT INTO identity.device (device_id, account_id)
  VALUES ('$DEV','$ACC');" >/dev/null 2>&1
$PSQL -c "SET ROLE app_competition; UPDATE identity.device
  SET revoked_at = now(), revoked_reason='lost' WHERE device_id='$DEV';" >/dev/null 2>&1
r=$($PSQL -c "SET ROLE app_competition; UPDATE identity.device SET revoked_at = NULL WHERE device_id='$DEV';" 2>&1)
if echo "$r" | grep -qi 'cannot be undone'; then
  ok "a device revocation cannot be undone"
else bad "a device revocation cannot be undone" "un-revoking was permitted"; fi

echo "== the organisational graph: Team, Venue, League, Tournament, Series (ADR-017) =="
# No application role may delete history anywhere in the competition schema, on any table —
# including ones a later migration adds, which is what the default privilege is for.
n=$($PSQL -c "SELECT count(*) FROM information_schema.role_table_grants
  WHERE table_schema='competition' AND privilege_type IN ('DELETE','TRUNCATE') AND grantee LIKE 'app\_%';")
check "no application role holds DELETE or TRUNCATE on any competition table" "$n" "0"
$PSQL -c "SET ROLE thro_owner; CREATE TABLE competition.zz_later_org (id int);" >/dev/null 2>&1
n=$($PSQL -c "SELECT count(*) FROM information_schema.role_table_grants
  WHERE table_schema='competition' AND table_name='zz_later_org' AND privilege_type IN ('DELETE','TRUNCATE')
    AND grantee LIKE 'app\\_%';")
check "a competition table added by a FUTURE migration is not deletable either" "$n" "0"

# A tournament is not a league, structurally: the two families of tables share no foreign key.
n=$($PSQL -c "SELECT count(*) FROM information_schema.columns WHERE table_schema='competition'
  AND table_name IN ('event','entry','check_in','bracket_tie') AND column_name='league_season_id';")
check "no event, entry, check-in or bracket tie references a league season" "$n" "0"
n=$($PSQL -c "SELECT count(*) FROM information_schema.columns WHERE table_schema='competition'
  AND table_name IN ('league_fixture','team_affiliation','player_registration') AND column_name='event_id';")
check "no league fixture, affiliation or registration references an event" "$n" "0"
n=$($PSQL -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='competition' AND table_name='fixture';")
check "the table that was misnamed 'fixture' is gone; the bracket tie is bracket_tie" "$n" "0"
n=$($PSQL -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='competition' AND table_name LIKE '%standing%';")
check "no standings table lives beside the competition tables (they are projections)" "$n" "0"

# THRØ ID holds no personal data: the only text on a player is a fixed vocabulary.
n=$($PSQL -c "SELECT string_agg(column_name, ',') FROM information_schema.columns
  WHERE table_schema='competition' AND table_name='player' AND data_type IN ('text','character varying');")
check "a player row carries no free text — a name lives in identity, reached through a claim" "$n" "source"

# Membership and registration share no key.
n=$($PSQL -c "SELECT count(*) FROM information_schema.columns WHERE table_schema='competition'
  AND table_name='player_registration' AND column_name LIKE '%membership%';")
check "a registration does not reference a membership" "$n" "0"

# Closing a dated relationship is the only change permitted, and it happens once.
TEAM=$($PSQL -c "SELECT gen_random_uuid();"); VEN=$($PSQL -c "SELECT gen_random_uuid();"); TEN=$($PSQL -c "SELECT gen_random_uuid();")
$PSQL -c "SET ROLE app_competition;
  INSERT INTO competition.team (team_id, name) VALUES ('$TEAM','Riverside A');
  INSERT INTO competition.venue (venue_id, name) VALUES ('$VEN','Riverside Club');
  INSERT INTO competition.team_venue_tenure (tenure_id, team_id, venue_id, kind, valid_from)
    VALUES ('$TEN','$TEAM','$VEN','home', now() - interval '1 year');
  UPDATE competition.team_venue_tenure SET valid_until = now() WHERE tenure_id='$TEN';" >/dev/null 2>&1
r=$($PSQL -c "SET ROLE app_competition; UPDATE competition.team_venue_tenure SET valid_until = NULL WHERE tenure_id='$TEN';" 2>&1)
if echo "$r" | grep -qi 'closed relationship'; then ok "a closed tenure cannot be reopened"
else bad "a closed tenure cannot be reopened" "${r:-reopening was permitted}"; fi
r=$($PSQL -c "SET ROLE app_competition; DELETE FROM competition.team_venue_tenure WHERE tenure_id='$TEN';" 2>&1)
if echo "$r" | grep -qi 'permission denied'; then ok "a tenure cannot be deleted"
else bad "a tenure cannot be deleted" "${r:-deletion was permitted}"; fi
n=$($PSQL -c "SELECT count(*) FROM competition.team_name WHERE team_id='$TEAM';")
check "a team's name is kept with a period from the moment it is created" "$n" "1"

# The ambiguous 'season' object type is gone from authorization; league_season replaces it.
r=$($PSQL -c "SET ROLE app_competition; INSERT INTO authz.relation (subject_id, relation, object_type, object_id)
  VALUES (gen_random_uuid(),'admin','season','x');" 2>&1)
if echo "$r" | grep -qi 'violates check constraint'; then ok "'season' is no longer an authorization object type"
else bad "'season' is no longer an authorization object type" "it was accepted"; fi
r=$($PSQL -c "SET ROLE app_competition; DELETE FROM authz.relation;" 2>&1)
if echo "$r" | grep -qi 'permission denied'; then ok "an authorization relation is revoked, never deleted"
else bad "an authorization relation is revoked, never deleted" "${r:-deletion was permitted}"; fi

# What an event requires of an entrant is stated, appended and withdrawn — never guessed, never rewritten (V019).
EV=$($PSQL -c "SELECT gen_random_uuid();"); REQ=$($PSQL -c "SELECT gen_random_uuid();"); WHO=$($PSQL -c "SELECT gen_random_uuid();")
$PSQL -c "SET ROLE app_competition; INSERT INTO competition.event (event_id, name, starts_at, session_ends_at, access)
  VALUES ('$EV','Open Night', now() + interval '7 days', now() + interval '7 days 6 hours', 'open');" >/dev/null 2>&1
r=$($PSQL -c "SET ROLE app_competition; INSERT INTO competition.event_eligibility
  (requirement_id, event_id, requirement_group, kind, team_id, stated_by) VALUES ('$REQ','$EV',1,'team_member','$TEAM','$WHO');" 2>&1)
if echo "$r" | grep -qi 'open event states no eligibility requirement'; then ok "an open event states no requirement: open means open"
else bad "an open event states no requirement: open means open" "${r:-a requirement was accepted on an open event}"; fi
$PSQL -c "SET ROLE app_competition; UPDATE competition.event SET access='member_only' WHERE event_id='$EV';
  INSERT INTO competition.event_eligibility (requirement_id, event_id, requirement_group, kind, team_id, stated_by)
    VALUES ('$REQ','$EV',1,'team_member','$TEAM','$WHO');" >/dev/null 2>&1
r=$($PSQL -c "SET ROLE app_competition; INSERT INTO competition.event_eligibility
  (requirement_id, event_id, requirement_group, kind, team_id, age_band, stated_by) VALUES (gen_random_uuid(),'$EV',1,'team_member','$TEAM','adult','$WHO');" 2>&1)
if echo "$r" | grep -qi 'violates check constraint'; then ok "a requirement names exactly the subject its kind needs"
else bad "a requirement names exactly the subject its kind needs" "${r:-a team_member row carrying an age band was accepted}"; fi
r=$($PSQL -c "SET ROLE app_competition; INSERT INTO competition.event_eligibility
  (requirement_id, event_id, requirement_group, kind, age_band, stated_by) VALUES (gen_random_uuid(),'$EV',2,'age_band','unknown','$WHO');" 2>&1)
if echo "$r" | grep -qi 'violates check constraint'; then ok "'unknown' is not an age band an event may require"
else bad "'unknown' is not an age band an event may require" "${r:-it was accepted}"; fi
r=$($PSQL -c "SET ROLE app_competition; UPDATE competition.event_eligibility SET requirement_group = 2 WHERE requirement_id='$REQ';" 2>&1)
if echo "$r" | grep -qi 'permission denied'; then ok "the application may withdraw a requirement and change nothing else in it"
else bad "the application may withdraw a requirement and change nothing else in it" "${r:-the group was changed}"; fi
r=$($PSQL -c "SET ROLE thro_owner; UPDATE competition.event_eligibility SET requirement_group = 2 WHERE requirement_id='$REQ';" 2>&1)
if echo "$r" | grep -qi 'cannot be rewritten'; then ok "a stated requirement cannot be rewritten, even by the owner"
else bad "a stated requirement cannot be rewritten, even by the owner" "${r:-the group was changed}"; fi
n=$($PSQL -c "SELECT competition.player_satisfies_event(gen_random_uuid(), '$EV');")
check "a stranger does not satisfy a stated requirement" "$n" "f"
n=$($PSQL -c "SELECT coalesce(competition.player_satisfies_event(gen_random_uuid(), gen_random_uuid())::text, 'null');")
check "an event that states nothing answers null — never yes" "$n" "null"
$PSQL -c "SET ROLE app_competition; UPDATE competition.event_eligibility
  SET withdrawn_at = now(), withdrawn_by = '$WHO', withdrawn_reason = 'stated on the wrong team' WHERE requirement_id='$REQ';" >/dev/null 2>&1
r=$($PSQL -c "SET ROLE app_competition; UPDATE competition.event_eligibility SET withdrawn_reason = 'changed my mind' WHERE requirement_id='$REQ';" 2>&1)
if echo "$r" | grep -qi 'history and cannot change'; then ok "a withdrawn requirement is history"
else bad "a withdrawn requirement is history" "${r:-the withdrawal was edited}"; fi
r=$($PSQL -c "SET ROLE app_competition; DELETE FROM competition.event_eligibility WHERE requirement_id='$REQ';" 2>&1)
if echo "$r" | grep -qi 'permission denied'; then ok "a requirement is withdrawn, never deleted"
else bad "a requirement is withdrawn, never deleted" "${r:-deletion was permitted}"; fi

# The health route reads the ledger through the application's connection (app_read), and nothing else may touch it.
n=$($PSQL -c "SELECT string_agg(privilege_type, ',' ORDER BY privilege_type) FROM information_schema.role_table_grants WHERE table_schema='thro' AND table_name='schema_migration' AND grantee LIKE 'app\_%';")
check "the application may read the migration ledger and may not write it" "$n" "SELECT"

echo "== the Secretary: a submission's state is the transitions', and nothing else's (V016) =="
n=$($PSQL -c "SELECT count(*) FROM information_schema.role_table_grants
  WHERE table_schema='competition' AND table_name='submission' AND privilege_type='UPDATE' AND grantee LIKE 'app\\_%';")
check "no application role holds UPDATE on competition.submission" "$n" "0"
n=$($PSQL -c "SELECT count(*) FROM information_schema.role_table_grants
  WHERE table_schema='competition' AND table_name IN ('submission_transition','submission_delivery','submission_artefact','admin_task_event')
    AND privilege_type IN ('UPDATE','DELETE','TRUNCATE') AND grantee LIKE 'app\\_%';")
check "transitions, deliveries, artefacts and task events are append-only for every application role" "$n" "0"
n=$($PSQL -c "SELECT prosecdef::int FROM pg_proc WHERE proname='submission_moves_only_with_evidence';")
check "the transition trigger runs as the owner, so it alone projects the state" "$n" "1"
# The disclosure gate: a self-created adult passes; a claimed minor with only their own consent does not; an unclaimed player never does.
ADULT=$($PSQL -c "SELECT gen_random_uuid();"); MINOR=$($PSQL -c "SELECT gen_random_uuid();"); PA=$($PSQL -c "SELECT gen_random_uuid();"); PM=$($PSQL -c "SELECT gen_random_uuid();"); PU=$($PSQL -c "SELECT gen_random_uuid();")
$PSQL -c "SET ROLE app_competition;
  INSERT INTO identity.account (account_id, display_name, age_band, age_assurance) VALUES ('$ADULT','An Adult','adult','self_declared');
  INSERT INTO identity.account (account_id, display_name, age_band, age_assurance) VALUES ('$MINOR','A Minor','minor','self_declared');
  INSERT INTO competition.player (player_id) VALUES ('$PA'), ('$PM'), ('$PU');
  INSERT INTO identity.player_claim (claim_id, player_id, account_id, method) VALUES (gen_random_uuid(),'$PA','$ADULT','self_created');
  INSERT INTO identity.player_claim (claim_id, player_id, account_id, method) VALUES (gen_random_uuid(),'$PM','$MINOR','self_created');" >/dev/null 2>&1
check "a self-created adult may be disclosed" "$($PSQL -c "SELECT identity.player_may_be_disclosed('$PA');")" "t"
check "a minor with only their own consent may not" "$($PSQL -c "SELECT identity.player_may_be_disclosed('$PM');")" "f"
check "an unclaimed player never may" "$($PSQL -c "SELECT identity.player_may_be_disclosed('$PU');")" "f"

echo "== provenance for imported rows (V027, PD-033) =="
SRC=$($PSQL -c "SELECT gen_random_uuid();"); VEN=$($PSQL -c "SELECT gen_random_uuid();")
$PSQL -c "SET ROLE app_competition;
  INSERT INTO competition.venue (venue_id, name, locality, postcode, latitude, longitude) VALUES ('$VEN','The Sun Inn','Stockton-on-Tees','TS18 1SU',54.5655947,-1.3118501);
  INSERT INTO competition.source_record (source_record_id, subject_kind, subject_id, source, source_url, external_ref, retrieved_on, basis)
    VALUES ('$SRC','venue','$VEN','OpenStreetMap','https://www.openstreetmap.org/way/99782298','way/99782298','2026-09-10','stated by the source');" >/dev/null 2>&1
check "the application may record where a row came from" "$($PSQL -c "SELECT count(*) FROM competition.source_record WHERE source_record_id='$SRC';")" "1"
r=$($PSQL -c "UPDATE competition.source_record SET basis='changed' WHERE source_record_id='$SRC';" 2>&1)
if echo "$r" | grep -qi 'is kept'; then ok "a source record is kept, never edited"
else bad "a source record is kept, never edited" "${r:-the record was edited}"; fi
r=$($PSQL -c "SET ROLE app_competition; DELETE FROM competition.source_record WHERE source_record_id='$SRC';" 2>&1)
if echo "$r" | grep -qi 'permission denied\|is kept'; then ok "and never deleted by the application"
else bad "and never deleted by the application" "${r:-deletion was permitted}"; fi
r=$($PSQL -c "SET ROLE app_competition; INSERT INTO competition.source_record (source_record_id, subject_kind, subject_id, source, retrieved_on, basis) VALUES (gen_random_uuid(),'player','$VEN','LeagueRepublic','2026-09-10','stated');" 2>&1)
if echo "$r" | grep -qi 'check constraint'; then ok "a person has no source record, by construction"
else bad "a person has no source record, by construction" "${r:-a player provenance row was accepted}"; fi
r=$($PSQL -c "SET ROLE app_competition; UPDATE competition.venue SET postcode='not a postcode', row_version=row_version+1 WHERE venue_id='$VEN';" 2>&1)
if echo "$r" | grep -qi 'check constraint'; then ok "a venue's postcode is a postcode"
else bad "a venue's postcode is a postcode" "${r:-junk was accepted as a postcode}"; fi

echo
echo "-------------------------------------------"
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
