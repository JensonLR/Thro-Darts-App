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


/**
 * The sign-in gate every signed-in page shares: a passkey button when nobody is signed in, a sign-out button when
 * somebody is. Answers whether the page may go on to draw.
 */
function signInGate(signInEl, where, prompt, redraw) {
  if (!session.get()) {
    signInEl.replaceChildren(make('p', 'quiet', 'Signing in uses a passkey — the same one the app uses. Nothing is typed.'));
    const button = make('button', 'primary', 'Sign in with a passkey');
    button.onclick = async () => {
      button.disabled = true;
      try { await signInWithPasskey(); await redraw(); }
      catch (e) { signInEl.append(make('p', 'note', e.message)); button.disabled = false; }
    };
    signInEl.append(button);
    where.replaceChildren(make('p', 'quiet', prompt));
    return false;
  }
  signInEl.replaceChildren();
  const out = make('button', 'quiet-button', 'Sign out');
  out.onclick = () => { signOut(); redraw(); };
  signInEl.append(out);
  return true;
}

// --- answering reports ---------------------------------------------------------------------------
//
// The queue a moderator works (PD-050, PD-101): what was reported, by the name somebody read, why, and when the
// answer is due — the urgent first. Only the accounts named in THRO_MODERATORS may read it, so everybody else is
// told that once rather than shown an empty page.

const ANSWERS = [
  ['left', 'Leave it — nothing wrong'],
  ['hidden', 'Hide it — the name comes off every public page'],
  ['corrected', 'Corrected — they put it right'],
  ['account_suspended', 'Suspend the account — signed out everywhere, cannot sign in'],
  ['not_upheld', 'Not upheld'],
  ['reinstated', 'Reinstate — lift the suspension, or show it again'],
];

async function mountModeration(where, signInEl) {
  const draw = async () => {
    if (!signInGate(signInEl, where, 'Sign in to answer reports.', draw)) return;
    let data;
    try { data = await authorised('GET', '/v1/reports'); } catch (e) { fail(where, e); return; }
    const open = data.reports.filter(r => r.decisions === 0);
    const answered = data.reports.filter(r => r.decisions > 0);
    const parts = [
      make('p', 'quiet', 'A decision is recorded, with your name and reason, and kept — and it does what it says (PD-103): '
        + 'hiding takes the name off every public page, suspending signs the person out everywhere and refuses their '
        + 'next sign-in, and reinstating undoes either. A match names nobody, so a report about one is answered by '
        + 'reporting the account.'),
      make('h2', null, open.length ? `${open.length} to answer` : 'Nothing waiting'),
    ];
    for (const r of open) parts.push(card(r, draw));
    if (answered.length) {
      parts.push(make('h2', null, `${answered.length} answered`));
      for (const r of answered) parts.push(card(r, draw));
    }
    where.replaceChildren(...parts);
  };

  function card(r, redraw) {
    const box = make('div', 'entry');
    const kind = { account: 'Account', team: 'Team', venue: 'Venue', league: 'League', match: 'Match' }[r.subjectKind] || r.subjectKind;
    box.append(
      make('div', 'row-name', `${r.urgent ? 'URGENT · ' : ''}${kind}: ${r.subject}`),
      make('p', null, `“${r.reason}”`),
      make('div', 'row-meta', `Reported ${when(r.reportedAt)} · answer by ${when(r.answerDueAt)}`
        + (r.decisions ? ` · answered ${r.decisions} time${r.decisions === 1 ? '' : 's'}` : '')),
    );
    const form = make('div', 'entry-form');
    const answer = make('select');
    answer.setAttribute('aria-label', 'Your answer');
    for (const [value, text] of ANSWERS) answer.append(new Option(text, value));
    const note = make('input'); note.type = 'text'; note.placeholder = 'Why — this is kept'; note.maxLength = 1000;
    note.style.flex = '1 1 16rem';
    note.setAttribute('aria-label', 'Why you decided this');
    const save = make('button', 'primary', r.decisions ? 'Answer again' : 'Record');
    const said = make('p', 'note'); said.hidden = true;
    save.onclick = async () => {
      if (note.value.trim().length < 3) { said.hidden = false; said.textContent = 'Say why, so the decision can be read back.'; return; }
      save.disabled = true;
      try {
        await authorised('POST', `/v1/reports/${encodeURIComponent(r.reportId)}/decisions`, { outcome: answer.value, note: note.value.trim() });
        said.hidden = false; said.textContent = 'Recorded.';
        setTimeout(redraw, 700);
      } catch (e) { said.hidden = false; said.textContent = e.message; save.disabled = false; }
    };
    form.append(answer, note, save);
    box.append(form, said);
    return box;
  }

  await draw();
}

// --- running a league ----------------------------------------------------------------------------

/**
 * The organiser's front door, when the address names no season (PD-100): sign in, the seasons you run, and a
 * league of your own to start. A league THRØ lists from elsewhere is not offered here to be taken on — its
 * organiser is named, never self-appointed (PD-053).
 */
async function mountLobby(where, signInEl) {
  const draw = async () => {
    if (!signInGate(signInEl, where, 'Sign in to run a league.', draw)) return;

    let mine;
    try { mine = await authorised('GET', '/v1/me/seasons'); } catch (e) { fail(where, e); return; }
    const parts = [make('h2', null, 'Seasons you run')];
    if (!mine.seasons.length) {
      parts.push(make('p', 'quiet', 'None yet. Start a league below.'));
    } else {
      const list = make('ul', 'rows');
      for (const s of mine.seasons) {
        const li = make('li');
        const link = make('a', 'row-name', `${s.league} · ${s.label}`);
        link.href = `organiser.html?season=${encodeURIComponent(s.leagueSeasonId)}`;
        li.append(link, make('div', 'row-meta', `${s.startsOn} to ${s.endsOn}`));
        list.append(li);
      }
      parts.push(list);
    }
    parts.push(starter());
    where.replaceChildren(...parts);
  };

  function starter() {
    const box = make('div', 'entry');
    box.append(make('h2', null, 'Start a league'),
      make('p', 'quiet', 'A league you start here is yours to run: its seasons, its teams, its fixtures and results.'));
    const field = (text, input) => { const l = make('label', 'quiet', text + ' '); l.append(input); return l; };
    const input = (type, placeholder) => { const i = make('input'); i.type = type; if (placeholder) i.placeholder = placeholder; return i; };
    const name = input('text', 'League name'); name.maxLength = 80;
    const locality = input('text', 'Town, optional');
    const label = input('text', 'Season, e.g. 2026-27'); label.maxLength = 40;
    const starts = input('date'); const ends = input('date');
    const divisions = input('text', 'Divisions, comma-separated, optional');
    const quiet = input('checkbox'); quiet.checked = true;
    const go = make('button', 'primary', 'Start it');
    const said = make('p', 'note'); said.hidden = true;
    go.onclick = async () => {
      const body = {
        name: name.value.trim(),
        visibility: quiet.checked ? 'private' : 'public',
        ...(locality.value.trim() ? { locality: locality.value.trim() } : {}),
        season: {
          label: label.value.trim(), startsOn: starts.value, endsOn: ends.value,
          divisions: divisions.value.split(',').map(d => d.trim()).filter(Boolean),
        },
      };
      if (body.name.length < 2 || !body.season.label || !starts.value || !ends.value) {
        said.hidden = false; said.textContent = 'A league needs a name, and its first season a label and two dates.'; return;
      }
      go.disabled = true;
      try {
        const started = await authorised('POST', '/v1/leagues', body);
        location.href = `organiser.html?season=${encodeURIComponent(started.season.leagueSeasonId)}`;
      } catch (e) { said.hidden = false; said.textContent = e.message; go.disabled = false; }
    };
    const form = make('div', 'entry-form');
    form.style.flexWrap = 'wrap';
    form.append(name, locality, label, field('Starts', starts), field('Ends', ends), divisions,
                field('Keep it private for now (off the public list; you can make it public later)', quiet), go);
    box.append(form, said);
    return box;
  }

  await draw();
}
//
// The surface a league secretary actually wants: a laptop, a keyboard, and the week's results typed in one
// sitting. The routes behind it are PD-053's, and nothing here can grant the relation they check — an
// administrator is named out of band, so this page refuses politely for everybody else rather than
// pretending the button might work.

async function mountOrganiser(where, signInEl) {
  const season = new URLSearchParams(location.search).get('season');
  if (!season) { await mountLobby(where, signInEl); return; }

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

    // The season as its administrator sees it (PD-099): its dates, divisions and every team that asked in. It is
    // also the page's one question about authority — somebody who does not run this season is told so here,
    // once, rather than by every button refusing in turn.
    let plan, data;
    try {
      plan = await authorised('GET', `/v1/seasons/${encodeURIComponent(season)}/teams`);
      data = await read(`/v1/seasons/${encodeURIComponent(season)}/fixtures`);
    } catch (e) { fail(where, e); return; }

    const todo = (data.fixtures || []).filter(f => !f.decided);
    const done = (data.fixtures || []).filter(f => f.decided);
    const parts = [...leagueSection(plan, draw), ...teamsSection(plan, draw)];

    if (!(data.fixtures || []).length) {
      parts.push(make('h2', null, 'Fixtures'),
                 make('p', null, 'This season has no fixtures yet. Let its teams in above, then add them below.'));
    } else if (!todo.length) {
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
    parts.push(scheduler(plan, draw));
    where.replaceChildren(...parts);
  };

  /**
   * The league this season belongs to, and what its starter may do to it (PD-103): rename it, keep it off the public
   * list, or end it. A league THRØ lists from elsewhere is named and left alone — its organiser did not start it here.
   */
  function leagueSection(plan, redraw) {
    const l = plan.league;
    const standing = l.endedAt ? `ended ${when(l.endedAt)}` : (l.visibility === 'private' ? 'private — off the public list' : 'public');
    const out = [make('h2', null, l.name), make('p', 'quiet', `${plan.label} · ${plan.startsOn} to ${plan.endsOn} · the league is ${standing}.`)];
    if (!l.startedHere || l.endedAt) return out;
    const box = make('div', 'entry');
    const said = make('p', 'note'); said.hidden = true;
    const change = async (body, button) => {
      button.disabled = true;
      try { await authorised('POST', `/v1/leagues/${encodeURIComponent(l.leagueId)}`, body); redraw(); }
      catch (e) { said.hidden = false; said.textContent = e.message; button.disabled = false; }
    };
    const form = make('div', 'entry-form');
    const name = make('input'); name.type = 'text'; name.value = l.name; name.maxLength = 80;
    name.setAttribute('aria-label', 'The league’s name');
    const rename = make('button', 'quiet-button', 'Rename');
    rename.onclick = () => change({ name: name.value.trim() }, rename);
    const toggle = make('button', 'quiet-button', l.visibility === 'private' ? 'Make it public' : 'Take it private');
    toggle.onclick = () => change({ visibility: l.visibility === 'private' ? 'public' : 'private' }, toggle);
    const end = make('button', 'quiet-button', 'End this league');
    end.onclick = () => {
      if (end.textContent !== 'End it — this cannot be undone') { end.textContent = 'End it — this cannot be undone'; return; }
      change({ ended: true }, end);
    };
    form.append(name, rename, toggle, end);
    box.append(form, said);
    out.push(box);
    return out;
  }

  /**
   * The teams that asked into the season (PD-099). Only an accepted team is in the league: its fixtures count and
   * it is a row in the table. So a team still waiting gets one button, and the accepted ones are a count.
   */
  function teamsSection(plan, redraw) {
    const waiting = plan.teams.filter(t => t.status !== 'accepted');
    const accepted = plan.teams.filter(t => t.status === 'accepted');
    const out = [make('h2', null, 'Teams'),
      make('p', 'quiet', `${accepted.length} in the season${waiting.length ? `, ${waiting.length} waiting to be let in` : ''}.`)];
    out.push(teamAdder(plan, redraw));
    if (!waiting.length) return out;
    const list = make('ul', 'rows');
    for (const t of waiting) {
      const li = make('li');
      const head = make('div', 'row-head');
      const division = plan.divisions.find(d => d.divisionId === t.divisionId);
      head.append(make('div', 'row-name', t.name + (division ? ` · ${division.name}` : '')));
      const let_in = make('button', 'primary', 'Let in');
      const said = make('p', 'note'); said.hidden = true;
      let_in.onclick = async () => {
        let_in.disabled = true;
        try {
          await authorised('POST', `/v1/seasons/${encodeURIComponent(plan.leagueSeasonId)}/affiliations/${encodeURIComponent(t.affiliationId)}`, {});
          redraw();
        } catch (e) { said.hidden = false; said.textContent = e.message; let_in.disabled = false; }
      };
      head.append(let_in);
      li.append(head, said);
      list.append(li);
    }
    out.push(list);
    return out;
  }

  /**
   * A team the league adds itself (PD-100), in the season at once. In a season with divisions it names one.
   */
  function teamAdder(plan, redraw) {
    const form = make('div', 'entry-form');
    const name = make('input'); name.type = 'text'; name.placeholder = 'Team name'; name.maxLength = 60;
    name.setAttribute('aria-label', 'The new team’s name');
    form.append(name);
    let division = null;
    if (plan.divisions.length) {
      division = make('select');
      division.setAttribute('aria-label', 'Which division it plays in');
      for (const d of plan.divisions) division.append(new Option(d.name, d.divisionId));
      form.append(division);
    }
    const add = make('button', 'quiet-button', 'Add a team');
    const said = make('p', 'note'); said.hidden = true;
    add.onclick = async () => {
      if (name.value.trim().length < 2) { said.hidden = false; said.textContent = 'A team’s name is at least two characters.'; return; }
      add.disabled = true;
      try {
        await authorised('POST', `/v1/seasons/${encodeURIComponent(plan.leagueSeasonId)}/teams`,
                         { name: name.value.trim(), ...(division ? { divisionId: division.value } : {}) });
        redraw();
      } catch (e) { said.hidden = false; said.textContent = e.message; add.disabled = false; }
    };
    form.append(add);
    const box = make('div');
    box.append(form, said);
    return box;
  }

  /**
   * Every pairing of [ids] once, in rounds, by the circle method — or twice, the second half with home and away
   * swapped. A bye fills an odd division, so a team sits out one round rather than a round being lost.
   */
  function roundRobin(ids, homeAndAway) {
    const ring = ids.slice();
    if (ring.length % 2) ring.push(null);
    const n = ring.length;
    const rounds = [];
    for (let r = 0; r < n - 1; r++) {
      const pairs = [];
      for (let i = 0; i < n / 2; i++) {
        const a = ring[i], b = ring[n - 1 - i];
        // Alternating who is at home by round keeps the fixed team from being at home all season.
        if (a && b) pairs.push(r % 2 === 0 ? [a, b] : [b, a]);
      }
      rounds.push(pairs);
      ring.splice(1, 0, ring.pop());
    }
    if (homeAndAway) rounds.push(...rounds.map(pairs => pairs.map(([h, a]) => [a, h])));
    return rounds;
  }

  /**
   * Adding fixtures (PD-099): one at a time, or a whole division drawn as a round robin and looked at before it
   * is sent. Nothing is written until the organiser presses the button under the list they can see, and the
   * server checks every fixture again — accepted teams, one division, inside the season — refusing the whole list
   * if any one cannot be played.
   */
  function scheduler(plan, redraw) {
    const box = make('div', 'entry');
    box.append(make('h2', null, 'Add fixtures'));
    const accepted = plan.teams.filter(t => t.status === 'accepted');
    if (accepted.length < 2) {
      box.append(make('p', 'quiet', 'A fixture needs two teams in the season. Let them in first.'));
      return box;
    }
    const named = id => (plan.teams.find(t => t.teamId === id) || {}).name || 'A team';
    const label = (text, input) => { const l = make('label', 'quiet', text + ' '); l.append(input); return l; };
    const select = (options, blank) => {
      const s = make('select');
      if (blank) s.append(new Option(blank, ''));
      for (const [value, text] of options) s.append(new Option(text, value));
      return s;
    };
    const instant = (day, time) => new Date(`${day}T${time}`).toISOString();

    // Which division's teams to draw from. A season without divisions is one pool.
    const pools = plan.divisions.length
      ? plan.divisions.map(d => [d.divisionId, d.name])
      : [['', 'All teams']];
    const pool = select(pools);
    const inPool = () => accepted.filter(t => (t.divisionId || '') === pool.value);
    const said = make('p', 'note'); said.hidden = true;
    const say = text => { said.hidden = false; said.textContent = text; };

    const send = async (fixtures, button) => {
      button.disabled = true;
      try {
        const made = await authorised('POST', `/v1/seasons/${encodeURIComponent(plan.leagueSeasonId)}/fixtures`, { fixtures });
        say(`${made.created.length} fixture${made.created.length === 1 ? '' : 's'} added.`);
        setTimeout(redraw, 900);
      } catch (e) { say(e.message); button.disabled = false; }
    };

    // One fixture.
    const one = make('div', 'entry-form');
    const home = select([], 'Home'), away = select([], 'Away');
    const day = make('input'); day.type = 'date'; day.min = plan.startsOn; day.max = plan.endsOn;
    const time = make('input'); time.type = 'time'; time.value = '19:30';
    const add = make('button', 'primary', 'Add');
    const refill = () => {
      for (const s of [home, away]) {
        s.replaceChildren(new Option(s === home ? 'Home' : 'Away', ''));
        for (const t of inPool()) s.append(new Option(t.name, t.teamId));
      }
    };
    add.onclick = () => {
      if (!home.value || !away.value || !day.value || !time.value) { say('A fixture is a home team, an away team, a day and a time.'); return; }
      send([{ homeTeamId: home.value, awayTeamId: away.value, scheduledAt: instant(day.value, time.value),
              ...(pool.value ? { divisionId: pool.value } : {}) }], add);
    };
    one.append(home, make('span', 'v', 'v'), away, day, time, add);

    // A whole division.
    const whole = make('div', 'entry-form');
    const first = make('input'); first.type = 'date'; first.min = plan.startsOn; first.max = plan.endsOn;
    const wholeTime = make('input'); wholeTime.type = 'time'; wholeTime.value = '19:30';
    const twice = make('input'); twice.type = 'checkbox'; twice.checked = true;
    const draw_up = make('button', 'quiet-button', 'Draw it up');
    const preview = make('div');
    draw_up.onclick = () => {
      const teams = inPool();
      if (teams.length < 2) { say('This division has fewer than two teams in the season.'); return; }
      if (!first.value || !wholeTime.value) { say('Say which day the first round is on, and at what time.'); return; }
      const [y, m, d] = first.value.split('-').map(Number);
      const [hh, mm] = wholeTime.value.split(':').map(Number);
      const fixtures = [];
      roundRobin(teams.map(t => t.teamId), twice.checked).forEach((pairs, round) => {
        // Weekly, on the same weekday, by the calendar — so a clock change moves nobody's start time.
        const at = new Date(y, m - 1, d + 7 * round, hh, mm).toISOString();
        for (const [h, a] of pairs) fixtures.push({ homeTeamId: h, awayTeamId: a, scheduledAt: at, ...(pool.value ? { divisionId: pool.value } : {}) });
      });
      const list = make('ul', 'rows');
      for (const f of fixtures) list.append(make('li', 'row-meta', `${when(f.scheduledAt)} · ${named(f.homeTeamId)} v ${named(f.awayTeamId)}`));
      const create = make('button', 'primary', `Add these ${fixtures.length} fixtures`);
      create.onclick = () => send(fixtures, create);
      preview.replaceChildren(make('p', 'quiet', `${fixtures.length} fixtures, weekly. Nothing is added until you press the button under the list.`), list, create);
    };
    whole.append(label('First round', first), wholeTime, label('Home and away', twice), draw_up);

    pool.onchange = () => { refill(); preview.replaceChildren(); };
    refill();
    box.append(label('Division', pool),
               make('p', 'quiet', 'One fixture'), one,
               make('p', 'quiet', `Or the whole division as a round robin, inside the season (${plan.startsOn} to ${plan.endsOn})`), whole,
               preview, said);
    return box;
  }

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
    const annul = make('button', 'quiet-button', 'Annul');
    head.append(fix, annul);
    row.append(head, make('div', 'row-meta', when(f.scheduledAt)));

    let open = null;
    const shut = () => {
      if (open) { open.remove(); open = null; }
      fix.textContent = 'Correct'; fix.setAttribute('aria-expanded', 'false');
      annul.textContent = 'Annul'; annul.setAttribute('aria-expanded', 'false');
    };
    fix.onclick = () => {
      const was = fix.getAttribute('aria-expanded') === 'true';
      shut();
      if (was) return;
      open = entry(f, redraw, d);
      fix.textContent = 'Leave it';
      fix.setAttribute('aria-expanded', 'true');
      row.append(open);
    };
    annul.onclick = () => {
      const was = annul.getAttribute('aria-expanded') === 'true';
      shut();
      if (was) return;
      open = annulment(f, redraw, d);
      annul.textContent = 'Leave it';
      annul.setAttribute('aria-expanded', 'true');
      row.append(open);
    };
    li.append(row);
    return li;
  }

  /**
   * Annulling a result (PD-065) — a different act from correcting one.
   *
   * A correction says the scoreline was wrong. This says the fixture should not have had a result at all:
   * played under protest, abandoned, ordered again. So it asks for a reason and will not proceed without
   * one, and the fixture comes back as open and annulled rather than as one nobody got round to.
   */
  function annulment(f, redraw, replacing) {
    const box = make('div', 'entry');
    box.append(make('p', 'quiet', 'The result comes off and the fixture is open again, with this reason on '
      + 'it. The old result stays on the record, superseded — nothing is rubbed out.'));
    const form = make('div', 'entry-form');
    const why = make('input');
    why.type = 'text';
    why.placeholder = 'Why — e.g. played under protest';
    why.style.flex = '1 1 16rem';
    why.setAttribute('aria-label', 'Why this result is being annulled');
    const go = make('button', 'primary', 'Annul it');
    const said = make('p', 'note');
    said.hidden = true;
    go.onclick = async () => {
      const reason = why.value.trim();
      if (!reason) {
        said.hidden = false;
        said.textContent = 'An annulment says why. A result withdrawn without a reason is one nobody can answer for.';
        return;
      }
      go.disabled = true;
      try {
        await authorised('POST', `/v1/fixtures/${encodeURIComponent(f.fixtureId)}/void`,
                         { supersedes: replacing.outcomeId, reason });
        said.hidden = false;
        said.textContent = 'Annulled. The fixture is open again and says why.';
        setTimeout(redraw, 900);
      } catch (e) {
        said.hidden = false; said.textContent = e.message; go.disabled = false;
      }
    };
    form.append(why, go);
    box.append(form, said);
    return box;
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
                 make('div', 'row-meta', when(f.scheduledAt) + (f.venue ? ` · ${f.venue}` : '')
                   + (f.annulled ? ` · annulled, to be replayed — ${f.annulled.reason}` : '')));
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

// --- a notice about people's information (PD-094) ----------------------------------------------
//
// Read from notice.json beside these pages and never from the API: the day a notice is needed may be the day
// the API is switched off, and this site answers whatever the API is doing. Anything short of a readable,
// active notice draws nothing — half a breach notice is worse than none. The shape is written down in
// docs/legal/BREACH_PLAN.md, and tools/check_notice.py holds the file to it on every push.

function usableNotice(n) {
  const words = (s) => typeof s === 'string' && s.trim() !== '';
  const paragraphs = (a) => Array.isArray(a) && a.length > 0 && a.every(words);
  const part = (p) => !!p && words(p.title) && words(p.summary) && paragraphs(p.body);
  return !!n && n.format === 1 && n.active === true && words(n.id) && words(n.published) && part(n) && part(n.under18);
}

async function readNotice() {
  try {
    const res = await fetch('notice.json', { cache: 'no-store', headers: { Accept: 'application/json' } });
    if (!res.ok) return null;
    const n = await res.json();
    return usableNotice(n) ? n : null;
  } catch {
    return null;
  }
}

function publishedOn(iso) {
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? '' : d.toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' });
}

// The card at the top of the front page: the title, the summary, and the way to both pages. A web page knows
// nobody's age, so it offers the under-18 words beside the full ones rather than choosing.
async function mountNoticeBanner(where) {
  const n = await readNotice();
  if (!n) return;
  const box = make('section', 'notice');
  const title = make('p', 'notice-title', n.title);
  title.id = 'notice-title';
  box.setAttribute('aria-labelledby', 'notice-title');
  const full = make('a', null, 'Read what happened');
  full.href = 'notice.html';
  const young = make('a', null, "If you're under 18");
  young.href = 'notice-under-18.html';
  const links = make('p', 'notice-links');
  links.append(full, ' · ', young);
  box.append(title, make('p', 'notice-summary', n.summary), links);
  where.replaceChildren(box);
}

// The whole notice, for an adult or in the words kept for under-18s.
async function mountNotice(where, reader) {
  const young = reader === 'under18';
  const n = await readNotice();
  if (!n) {
    where.replaceChildren(
      make('p', null, young
        ? 'There is nothing to tell you right now.'
        : 'There is no notice about your information at the moment.'),
      make('p', 'quiet', young
        ? 'THRØ has no way to send you a message. If something ever goes wrong with your information, this page and the app will say so.'
        : 'THRØ holds no email address or phone number for anybody, so it cannot write to you. If something ever goes wrong with the information it keeps, this page will explain it and the app will show it on its front screen.'),
    );
    return;
  }
  const part = young ? n.under18 : n;
  const box = make('article', 'notice');
  box.append(
    make('p', 'notice-title', part.title),
    make('p', 'notice-when', `Published ${publishedOn(n.published)}`),
    make('p', 'notice-summary', part.summary),
    ...part.body.map((paragraph) => make('p', null, paragraph)),
  );
  where.replaceChildren(box);
}

window.THRO = { mountLeagues, mountTable, mountFixtures, mountOrganiser, mountModeration, mountNotice, mountNoticeBanner, signInWithPasskey, whoAmI, signOut, session, authorised, passkeysPossible };
