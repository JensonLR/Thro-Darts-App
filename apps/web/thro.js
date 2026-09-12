// THRØ on the web: two public reads and the words that go with them.
//
// No framework and no build step. The pages need the generated tokens, one fetch and a little DOM —
// a dependency here would have to earn itself against that, and none can yet.

// tokens.css switches on [data-theme="dark"], so the page follows the reader's system setting.
const dark = window.matchMedia('(prefers-color-scheme: dark)');
const applyTheme = () => { document.documentElement.dataset.theme = dark.matches ? 'dark' : 'light'; };
applyTheme();
dark.addEventListener('change', applyTheme);

// Where THRØ answers. Same origin by default, so a deployment can put the API behind the same host and
// this needs no configuration; `?api=https://…` overrides it for looking at another one.
const API = new URLSearchParams(location.search).get('api') || window.THRO_API || '';

async function read(path) {
  const res = await fetch(`${API}${path}`, { headers: { Accept: 'application/json' } });
  if (!res.ok) {
    const body = await res.text();
    let said = '';
    try { said = JSON.parse(body).error || ''; } catch { /* not JSON: the status is all there is */ }
    throw new Error(said || `THRØ answered ${res.status}.`);
  }
  return res.json();
}

const text = (el, s) => { el.textContent = s; return el; };
const make = (tag, cls, s) => { const el = document.createElement(tag); if (cls) el.className = cls; if (s !== undefined) el.textContent = s; return el; };

function fail(where, error) {
  where.replaceChildren(
    make('p', null, 'That could not be read just now.'),
    make('p', 'quiet', error.message),
  );
}

// --- the leagues -------------------------------------------------------------------------------

function leagueMeta(league) {
  const season = league.seasons && league.seasons[0];
  const teams = season ? season.divisions.reduce((n, d) => n + d.teams.length, 0) : 0;
  return [
    league.playsOn ? `${league.playsOn} nights` : null,
    teams ? `${teams} team${teams === 1 ? '' : 's'}` : null,
    league.locality,
  ].filter(Boolean).join(' · ');
}

async function mountLeagues(listEl, searchEl, countEl) {
  let leagues = [];
  try {
    // The read is an envelope — {"leagues": [...]} — and taking the object for the array is how the
    // first version of this page came to report "undefined leagues" over an empty list.
    leagues = (await read('/v1/leagues')).leagues || [];
  } catch (e) { fail(listEl, e); return; }

  const draw = () => {
    const q = (searchEl.value || '').trim().toLowerCase();
    const shown = q ? leagues.filter(l => l.name.toLowerCase().includes(q) || (l.locality || '').toLowerCase().includes(q)) : leagues;
    const many = n => `${n} league${n === 1 ? '' : 's'}`;
    countEl.textContent = q ? `${shown.length} of ${many(leagues.length)}` : many(leagues.length);
    listEl.replaceChildren(...shown.slice(0, 200).map(l => {
      const li = make('li');
      const season = l.seasons && l.seasons[0];
      const a = make('a');
      // A league with no season has no table to show, so its row does not pretend to lead anywhere.
      if (season) a.href = `table.html?season=${encodeURIComponent(season.leagueSeasonId)}`;
      else { a.setAttribute('aria-disabled', 'true'); a.style.cursor = 'default'; }
      a.append(make('div', 'row-name', l.name), make('div', 'row-meta', season ? leagueMeta(l) : 'No season on THRØ yet'));
      li.append(a);
      return li;
    }));
    if (!shown.length) listEl.replaceChildren(make('li', null, ''), text(make('p', 'quiet'), 'No league here by that name.'));
  };
  searchEl.addEventListener('input', draw);
  draw();
}

// --- a league's table --------------------------------------------------------------------------

/** The chain step names, in the words a player would use. The app says the same (LeagueTableWords). */
const STEP = {
  points: 'points',
  leg_difference: 'leg difference',
  legs_for: 'legs won',
  head_to_head: 'who beat whom',
  played: 'matches played',
};

function orderedBy(rules) {
  const by = (rules.orderedBy || []).map(s => STEP[s] || s.replace(/_/g, ' '));
  return by.length ? `Ordered on ${by.join(', then ')}.` : '';
}

function awaiting(n) {
  return n === 1
    ? 'One fixture has been played with no result entered, so this table is not finished.'
    : `${n} fixtures have been played with no result entered, so this table is not finished.`;
}

function tableFor(division) {
  const table = make('table');
  const head = make('thead');
  const hr = make('tr');
  for (const [label, title] of [['#', 'Position'], ['Team', 'Team'], ['P', 'Played'], ['W', 'Won'], ['D', 'Drawn'], ['L', 'Lost'], ['+/−', 'Leg difference'], ['E', 'Scored on THRØ'], ['Pts', 'Points']]) {
    const th = make('th', null, label);
    th.scope = 'col';
    th.title = title;
    hr.append(th);
  }
  head.append(hr);
  const body = make('tbody');
  for (const r of division.rows) {
    const tr = make('tr');
    const diff = r.legDifference > 0 ? `+${r.legDifference}` : `${r.legDifference}`;
    tr.append(
      make('td', null, String(r.position)),
      make('td', 'team', r.name),
      make('td', null, String(r.played)),
      make('td', null, String(r.won)),
      make('td', null, String(r.drawn)),
      make('td', null, String(r.lost)),
      make('td', null, diff),
      make('td', r.evidenced > 0 ? 'evidenced' : null, String(r.evidenced)),
      make('td', 'points', String(r.points)),
    );
    body.append(tr);
  }
  table.append(head, body);
  const scroll = make('div', 'table-scroll');
  scroll.append(table);
  return scroll;
}

async function mountTable(where, titleEl, eyebrowEl) {
  const season = new URLSearchParams(location.search).get('season');
  if (!season) { fail(where, new Error('This address names no season.')); return; }
  let t;
  try {
    t = await read(`/v1/seasons/${encodeURIComponent(season)}/standings`);
  } catch (e) { fail(where, e); return; }

  document.title = `${t.league} — table — THRØ`;
  titleEl.textContent = t.league;
  eyebrowEl.textContent = t.label;

  const parts = [];
  const empty = t.divisions.every(d => !d.rows.length);
  if (empty) {
    parts.push(make('p', null, 'No results yet.'));
    parts.push(make('p', 'quiet', 'When this league’s fixtures start carrying results the table fills itself in. THRØ works it out from the results rather than keeping a table of its own.'));
  } else {
    for (const d of t.divisions) {
      if (t.divisions.length > 1 || d.name !== t.label) parts.push(make('h2', null, d.name));
      parts.push(tableFor(d));
      if (d.awaitingResults > 0) parts.push(make('p', 'note', awaiting(d.awaitingResults)));
    }
  }
  // PD-054's condition: a table always says whose rules ordered it. Never omitted, empty or not.
  parts.push(make('p', 'note', `${t.rules.says} ${orderedBy(t.rules)}`.trim()));
  parts.push(make('p', 'quiet', 'E counts the results in that row that came from a match scored on THRØ. The rest are an official’s word, which counts here and can never move a rating.'));
  where.replaceChildren(...parts);
}


// --- a season's fixtures ------------------------------------------------------------------------

/** What a fixture finished as, in the words a player would use rather than the schema's. */
function decided(d) {
  if (!d) return null;
  if (d.kind === 'played') return { score: `${d.legsHome}–${d.legsAway}`, tag: 'Scored on THRØ', how: 'played' };
  if (d.kind === 'declared') return { score: `${d.legsHome}–${d.legsAway}`, tag: 'The league’s word', how: 'declared' };
  if (d.kind === 'walkover') return { score: null, tag: d.awardedToHome ? 'Walkover, home' : 'Walkover, away', how: 'awarded' };
  return { score: null, tag: d.awardedToHome ? 'Awarded, home' : 'Awarded, away', how: 'awarded' };
}

const when = iso => new Date(iso).toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' });

async function mountFixtures(where, titleEl, eyebrowEl) {
  const season = new URLSearchParams(location.search).get('season');
  if (!season) { fail(where, new Error('This address names no season.')); return; }
  let data;
  try {
    data = await read(`/v1/seasons/${encodeURIComponent(season)}/fixtures`);
  } catch (e) { fail(where, e); return; }

  const fixtures = data.fixtures || [];
  titleEl.textContent = 'Fixtures';
  eyebrowEl.textContent = fixtures.length ? `${fixtures.length} fixture${fixtures.length === 1 ? '' : 's'}` : 'Fixtures';
  document.title = 'Fixtures — THRØ';

  if (!fixtures.length) {
    where.replaceChildren(
      make('p', null, 'No fixtures yet.'),
      make('p', 'quiet', 'When the league publishes its calendar the fixtures appear here, and the table fills itself in from their results.'),
    );
    return;
  }

  const list = make('ul', 'rows');
  for (const f of fixtures) {
    const li = make('li');
    const row = make('div');
    row.style.padding = '14px 0';
    // A private team is unnamed rather than absent, exactly as the server sends it.
    const side = n => n || 'A team';
    const d = decided(f.decided);
    const head = make('div', 'row-name', d && d.score
      ? `${side(f.home)}  ${d.score}  ${side(f.away)}`
      : `${side(f.home)} v ${side(f.away)}`);
    const bits = [when(f.scheduledAt)];
    if (f.venue) bits.push(f.locality ? `${f.venue}, ${f.locality}` : f.venue);
    if (f.state !== 'scheduled') bits.push(f.state);
    if (d) bits.push(d.tag); else bits.push('To play');
    row.append(head, make('div', 'row-meta', bits.join(' · ')));
    li.append(row);
    list.append(li);
  }
  const unplayed = fixtures.filter(f => !f.decided).length;
  where.replaceChildren(
    list,
    make('p', 'quiet', unplayed
      ? `${unplayed} of ${fixtures.length} still to play.`
      : 'Every fixture in this season has a result.'),
  );
}


// --- signing in, with a passkey ------------------------------------------------------------------
//
// A passkey rather than an OAuth redirect, because the API already speaks WebAuthn (PD-030) and because a
// redirect flow on a static site means a client id, a callback page and a third party in the round trip. A
// passkey needs none of those: the browser holds the key, the server holds the public half, and the whole
// exchange is two requests to our own origin.
//
// The session lives in sessionStorage, not localStorage. It is cleared when the tab closes, which is the
// right default for somebody entering results on a shared laptop in a pub back room — the place this page
// is actually for.

const B64U = {
  toBytes(s) {
    const b64 = s.replace(/-/g, '+').replace(/_/g, '/');
    const bin = atob(b64 + '='.repeat((4 - (b64.length % 4)) % 4));
    return Uint8Array.from(bin, c => c.charCodeAt(0));
  },
  fromBytes(buf) {
    const bin = String.fromCharCode(...new Uint8Array(buf));
    return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  },
};

/** This browser's device id, kept so a session family belongs to it as the phone's does. */
function deviceId() {
  let id = localStorage.getItem('thro.device');
  if (!id) { id = crypto.randomUUID(); localStorage.setItem('thro.device', id); }
  return id;
}

const session = {
  get() { try { return JSON.parse(sessionStorage.getItem('thro.session') || 'null'); } catch { return null; } },
  set(s) { sessionStorage.setItem('thro.session', JSON.stringify(s)); },
  clear() { sessionStorage.removeItem('thro.session'); },
};

async function post(path, body, bearer) {
  const res = await fetch(`${API}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(bearer ? { Authorization: `Bearer ${bearer}` } : {}) },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  let parsed = null;
  try { parsed = text ? JSON.parse(text) : null; } catch { /* the status is all there is */ }
  if (!res.ok) throw new Error((parsed && parsed.error) || `THRØ answered ${res.status}.`);
  return parsed;
}

/** A request that needs a session: one refresh on a 401, then it gives up and says so — as the phone does. */
async function authorised(method, path, body) {
  let s = session.get();
  if (!s) throw new Error('You are not signed in.');
  const send = token => fetch(`${API}${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let res = await send(s.accessToken);
  if (res.status === 401) {
    let renewed;
    try { renewed = await post('/v1/auth/refresh', { refreshToken: s.refreshToken }); }
    catch { session.clear(); throw new Error('Your sign-in has expired. Sign in again.'); }
    session.set(renewed);
    res = await send(renewed.accessToken);
  }
  const text = await res.text();
  let parsed = null;
  try { parsed = text ? JSON.parse(text) : null; } catch { /* nothing to read */ }
  if (!res.ok) throw new Error((parsed && parsed.error) || `THRØ answered ${res.status}.`);
  return parsed;
}

/** True when this browser can do the ceremony at all — an old one, or an insecure origin, cannot. */
function passkeysPossible() {
  return typeof PublicKeyCredential !== 'undefined' && window.isSecureContext;
}

async function signInWithPasskey() {
  if (!passkeysPossible()) {
    throw new Error('This browser cannot use a passkey here. It needs a recent browser on a secure connection.');
  }
  const asked = await post('/v1/auth/passkey/options', { deviceId: deviceId() });
  const assertion = await navigator.credentials.get({
    publicKey: {
      challenge: B64U.toBytes(asked.publicKey.challenge),
      rpId: asked.publicKey.rpId,
      userVerification: asked.publicKey.userVerification,
      timeout: asked.publicKey.timeout,
      // No allowCredentials: the passkey is discoverable, so the browser offers the ones it holds
      // for this domain rather than the page having to know who is signing in.
    },
  });
  if (!assertion) throw new Error('No passkey was chosen.');
  const signedIn = await post('/v1/auth/passkey', {
    deviceId: deviceId(),
    challengeId: asked.challengeId,
    credentialId: B64U.fromBytes(assertion.rawId),
    clientDataJSON: B64U.fromBytes(assertion.response.clientDataJSON),
    authenticatorData: B64U.fromBytes(assertion.response.authenticatorData),
    signature: B64U.fromBytes(assertion.response.signature),
  });
  session.set(signedIn);
  return signedIn;
}

async function whoAmI() { return authorised('GET', '/v1/me'); }

function signOut() { session.clear(); }


// --- running a league ----------------------------------------------------------------------------
//
// The surface a league secretary actually wants: a laptop, a keyboard, and the week's results typed in one
// sitting. The routes behind it are PD-053's, and nothing here can grant the relation they check — an
// administrator is named out of band, so this page refuses politely for everybody else rather than
// pretending the button might work.

async function mountOrganiser(where, signInEl) {
  const season = new URLSearchParams(location.search).get('season');
  if (!season) { fail(where, new Error('This address names no season.')); return; }

  const draw = async () => {
    if (!session.get()) {
      signInEl.replaceChildren(make('p', 'quiet', 'Signing in uses a passkey — the same one the app uses. Nothing is typed.'));
      const button = make('button', 'primary', 'Sign in with a passkey');
      button.onclick = async () => {
        button.disabled = true;
        try { await signInWithPasskey(); await draw(); }
        catch (e) { signInEl.append(make('p', 'note', e.message)); button.disabled = false; }
      };
      signInEl.append(button);
      where.replaceChildren(make('p', 'quiet', 'Sign in to enter this season’s results.'));
      return;
    }

    signInEl.replaceChildren();
    const out = make('button', 'quiet-button', 'Sign out');
    out.onclick = () => { signOut(); draw(); };
    signInEl.append(out);

    let data;
    try { data = await read(`/v1/seasons/${encodeURIComponent(season)}/fixtures`); }
    catch (e) { fail(where, e); return; }

    const todo = (data.fixtures || []).filter(f => !f.decided);
    const done = (data.fixtures || []).filter(f => f.decided);
    const parts = [];

    if (!todo.length) {
      parts.push(make('p', null, 'Every fixture in this season has a result.'));
    } else {
      parts.push(make('h2', null, `${todo.length} to enter`));
      for (const f of todo) parts.push(entry(f, draw));
    }
    if (done.length) {
      parts.push(make('h2', null, `${done.length} already in`));
      const list = make('ul', 'rows');
      for (const f of done) list.append(standing(f, draw));
      parts.push(list);
      parts.push(make('p', 'quiet', 'Correcting a result does not rub the old one out: it records a second decision, with your name on it, that supersedes the first.'));
    }
    where.replaceChildren(...parts);
  };

  /**
   * A result already in, with a way to correct it (PD-059).
   *
   * Folded away behind one word, because a season is mostly results that are right and a page of open
   * forms is a page nobody can read. The form it opens is the same one used to enter a result, told which
   * decision it replaces — the page never edits anything, it records a second decision.
   */
  function standing(f, redraw) {
    const li = make('li');
    const row = make('div');
    row.style.padding = '12px 0';
    const d = f.decided;
    const score = d.legsHome === null ? (d.kind === 'walkover' ? 'walkover' : 'awarded') : `${d.legsHome}–${d.legsAway}`;
    const head = make('div', 'row-head');
    head.append(make('div', 'row-name', `${f.home || 'A team'} ${score} ${f.away || 'A team'}`));
    const fix = make('button', 'quiet-button', 'Correct');
    fix.setAttribute('aria-expanded', 'false');
    head.append(fix);
    row.append(head, make('div', 'row-meta', when(f.scheduledAt)));

    let open = null;
    fix.onclick = () => {
      if (open) { open.remove(); open = null; fix.textContent = 'Correct'; fix.setAttribute('aria-expanded', 'false'); return; }
      open = entry(f, redraw, d);
      fix.textContent = 'Leave it';
      fix.setAttribute('aria-expanded', 'true');
      row.append(open);
    };
    li.append(row);
    return li;
  }

  /**
   * One fixture, with two boxes and a button. The server decides whether it is played or declared.
   *
   * [replacing] is the decision standing now, when this is a correction. Naming it is what stops two
   * officials from silently overwriting one another: the server refuses a correction to a result that has
   * itself been corrected since this page was drawn, and says so rather than taking the last write.
   */
  function entry(f, redraw, replacing) {
    const box = make('div', 'entry');
    if (!replacing) {
      box.append(make('div', 'row-name', `${f.home || 'A team'} v ${f.away || 'A team'}`),
                 make('div', 'row-meta', when(f.scheduledAt) + (f.venue ? ` · ${f.venue}` : '')));
    }
    const form = make('div', 'entry-form');
    const home = make('input'); home.type = 'number'; home.min = '0'; home.inputMode = 'numeric';
    home.setAttribute('aria-label', `Legs for ${f.home || 'the home team'}`);
    const away = make('input'); away.type = 'number'; away.min = '0'; away.inputMode = 'numeric';
    away.setAttribute('aria-label', `Legs for ${f.away || 'the away team'}`);
    if (replacing && replacing.legsHome !== null) { home.value = replacing.legsHome; away.value = replacing.legsAway; }
    const save = make('button', 'primary', replacing ? 'Correct it' : 'Save');
    const said = make('p', 'note');
    said.hidden = true;
    save.onclick = async () => {
      const h = parseInt(home.value, 10);
      const a = parseInt(away.value, 10);
      if (!Number.isInteger(h) || !Number.isInteger(a) || h < 0 || a < 0) {
        said.hidden = false; said.textContent = 'A result is two numbers, one for each side.'; return;
      }
      save.disabled = true;
      try {
        const body = { legsHome: h, legsAway: a };
        if (replacing) body.supersedes = replacing.outcomeId;
        const done = await authorised('POST', `/v1/fixtures/${encodeURIComponent(f.fixtureId)}/result`, body);
        // The server chose the kind from the evidence, not from anything this page sent (PD-055).
        said.hidden = false;
        said.textContent = replacing
          ? 'Corrected. The earlier result stays on the record, superseded.'
          : done.kind === 'played'
            ? 'Saved, against the match scored on THRØ.'
            : 'Saved as the league’s word — no match was scored on THRØ for this fixture.';
        setTimeout(redraw, 900);
      } catch (e) {
        said.hidden = false; said.textContent = e.message; save.disabled = false;
      }
    };
    form.append(home, make('span', 'v', 'v'), away, save);
    box.append(form, said);
    return box;
  }

  await draw();
}

window.THRO = { mountLeagues, mountTable, mountFixtures, mountOrganiser, signInWithPasskey, whoAmI, signOut, session, authorised, passkeysPossible };
