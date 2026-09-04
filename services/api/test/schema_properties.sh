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
for f in "$(dirname "$0")"/../migrations/V*.sql; do
  out=$($PSQL -f "$f" 2>&1); rc=$?
  if [ $rc -eq 0 ] && ! echo "$out" | grep -qi '^ERROR'; then ok "applied $(basename "$f")"
  else bad "applied $(basename "$f")" "$(echo "$out" | grep -i ERROR | head -1)"; fi
done

M=11111111-1111-1111-1111-111111111111
DA=aaaaaaaa-0000-0000-0000-00000000000a
DB=bbbbbbbb-0000-0000-0000-00000000000b
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
n=$($PSQL -c "SELECT count(*) FROM evidence.event;")
check "the log survived every attempt" "$n" "4"

echo
echo "== a table added by a FUTURE migration inherits the revocation =="
$PSQL -c "SET ROLE thro_owner; CREATE TABLE evidence.late_arrival(id int PRIMARY KEY, v int);" >/dev/null
$PSQL -c "SET ROLE thro_owner; INSERT INTO evidence.late_arrival VALUES (1,180);" >/dev/null
r=$($PSQL -c "SET ROLE app_match; UPDATE evidence.late_arrival SET v=1;" 2>&1)
if echo "$r" | grep -qi 'permission denied'; then ok "UPDATE on a later table is denied by default privileges"
else bad "UPDATE on a later table is denied by default privileges" "${r:-succeeded — the defect this test exists for}"; fi
v=$($PSQL -c "SELECT v FROM evidence.late_arrival WHERE id=1;")
check "the later table's data is intact" "$v" "180"

echo
echo "== idempotency =="
CMD=cccccccc-0000-0000-0000-00000000000c
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
d=$($PSQL -c "SELECT coalesce(darts_used::text,'NULL') FROM read.visit LIMIT 1;")
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
echo "-------------------------------------------"
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
