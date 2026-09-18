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
const make = (tag, cls, s) => {
  const el = document.createElement(tag);
  if (cls) el.className = cls;
  if (s !== undefined) el.textContent = s;
  // A `note` is what a page says after something was tried — saved, refused, why. Sighted readers see it appear;
  // a screen reader hears it only if the region announces itself.
  if (cls === 'note') el.setAttribute('role', 'status');
  return el;
};

/**
 * A read that failed is said at the top of the page, not instead of it: what was already drawn stays, so one bad
 * answer does not blank a page a person was reading. With `retry`, the note carries a button that asks again.
 */
/** A checkbox beside its words, as one tap target. */
function check(text, checked) {
  const l = make('label', 'check');
  const c = make('input'); c.type = 'checkbox'; c.checked = !!checked;
  l.append(c, text);
  return [c, l];
}

/** A calendar day (yyyy-mm-dd) in words: "1 Sep 2026". Days are days, not instants, so no time zone touches them. */
const day = iso => {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso || '');
  if (!m) return iso || '';
  return new Date(Date.UTC(+m[1], +m[2] - 1, +m[3])).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' });
};

function fail(where, error, retry) {
  const note = make('div', 'entry');
  note.setAttribute('role', 'status');
  note.append(make('p', null, 'That could not be read just now.'), make('p', 'quiet', error.message));
  if (retry) {
    const again = make('button', 'quiet-button', 'Try again');
    again.onclick = () => { again.disabled = true; retry(); };
    note.append(again);
  }
  const placeholder = where.children.length <= 1 && where.textContent.trim().endsWith('…');
  if (placeholder || !where.children.length) where.replaceChildren(note); else where.prepend(note);
}

// --- the leagues -------------------------------------------------------------------------------

/** The season a league's row and page show: the one running today, else the newest. The app picks the same. */
const shownSeason = league => (league.seasons || []).find(s => s.current) || (league.seasons || [])[0] || null;
const teamsIn = season => season ? season.divisions.reduce((n, d) => n + d.teams.length, 0) : 0;
const plural = (n, noun) => `${n} ${noun}${n === 1 ? '' : 's'}`;

/**
 * What THRØ holds for a league (PD-126): it is run here, or its teams are listed from its own website, or it is a point
 * on the map and nothing more. Three different things. A list that words them alike reads as three hundred leagues on
 * THRØ, which is false; so each row and each page says which it is. The app says the same (`PublicLeague.held`).
 */
function heldAs(league) {
  if (league.standing === 'run_here') return 'run';
  return teamsIn(shownSeason(league)) > 0 ? 'teams' : 'placed';
}

function leagueMeta(league) {
  const season = shownSeason(league);
  const kind = heldAs(league);
  const held = kind === 'run'
    ? 'Run on THRØ · ' + (season && season.fixtures ? `${plural(season.fixtures, 'fixture')}, ${plural(season.results || 0, 'result')}` : 'no fixtures yet')
    : kind === 'teams' ? `${plural(teamsIn(season), 'team')} listed` : 'On the map only';
  return [held, league.playsOn ? `${league.playsOn} nights` : null, league.locality].filter(Boolean).join(' · ');
}

/** Where a league's fixtures and table are: here, or on its own website. The sentence its page opens on. */
function heldWords(league) {
  const season = shownSeason(league);
  switch (heldAs(league)) {
    case 'run':
      return season && season.fixtures
        ? `Run on THRØ: ${plural(season.fixtures, 'fixture')}, ${season.results || 0} with a result. The table is worked out from them.`
        : 'Run on THRØ. Its organiser has not scheduled a fixture yet.';
    case 'teams': return 'Its teams are listed here from its own website. Its fixtures and table are kept there, not on THRØ.';
    default: return 'On the map where the league lists itself. Its teams, fixtures and table are on its own website, not on THRØ.';
  }
}

async function mountLeagues(listEl, searchEl, countEl) {
  let leagues = [];
  try {
    // The read is an envelope — {"leagues": [...]} — and taking the object for the array is how the
    // first version of this page came to report "undefined leagues" over an empty list.
    leagues = (await read('/v1/leagues')).leagues || [];
  } catch (e) { fail(listEl, e); return; }
  // What THRØ holds most of comes first: a league run here, then one with its teams, then the map's pins.
  const order = { run: 0, teams: 1, placed: 2 };
  leagues = leagues.map((l, i) => [l, i]).sort((a, b) => (order[heldAs(a[0])] - order[heldAs(b[0])]) || (a[1] - b[1])).map(x => x[0]);
  const counted = kind => leagues.filter(l => heldAs(l) === kind).length;

  const row = l => {
    const li = make('li');
    const a = make('a');
    // One address, on the web and in the app (PD-127): the league's own page, whatever THRØ holds for it.
    a.href = `/league/${encodeURIComponent(l.leagueId)}`;
    a.append(make('div', 'row-name', l.name), make('div', 'row-meta', leagueMeta(l)));
    li.append(a);
    return li;
  };
  const draw = () => {
    const q = (searchEl.value || '').trim().toLowerCase();
    const shown = q ? leagues.filter(l => l.name.toLowerCase().includes(q) || (l.locality || '').toLowerCase().includes(q)) : leagues;
    // Counted apart, never as one number (PD-126).
    countEl.textContent = q ? `${shown.length} of ${plural(leagues.length, 'league')}`
      : [counted('run') ? `${counted('run')} run on THRØ` : null,
         counted('teams') ? `${counted('teams')} with their teams listed` : null,
         counted('placed') ? `${counted('placed')} on the map from their own websites` : null].filter(Boolean).join(' · ');
    // A few until a name is typed: three hundred leagues in a column is a wall, not a way in.
    listEl.replaceChildren(...shown.slice(0, q ? 200 : 8).map(row));
    if (!q && shown.length > 8) {
      const more = make('li', 'more');
      const btn = make('button', 'quiet-button', `Show all ${shown.length} leagues`);
      btn.onclick = () => listEl.replaceChildren(...shown.map(row));
      more.append(btn); listEl.append(more);
    }
    if (!shown.length) {
      const none = make('li');
      none.append(make('p', 'quiet', 'No league here by that name. If you run it, start it on the organiser’s desk and it is here the same day.'));
      const desk = make('a', null, 'Open the desk'); desk.href = 'organiser.html'; none.append(desk);
      listEl.replaceChildren(none);
    }
  };
  searchEl.addEventListener('input', draw);
  draw();
}

// --- one address, on the web and in the app (PD-127) -------------------------------------------

/**
 * The same place in the app. `thro.uk/league/<id>` is a page here and, on a phone with THRØ, the league in the app —
 * so on a phone this is a button that opens it there, and on a bigger screen it is this page's own address as a QR,
 * for the phone in the reader's pocket. `what` is `league`, `event` or `team`.
 */
function openInApp(what, id, words) {
  const box = make('div', 'entry app-link');
  const path = `${what}/${encodeURIComponent(id)}`;
  if (onPhone()) {
    const open = make('a', 'primary', 'Open in THRØ'); open.href = `thro://${path}`;
    box.append(open, make('p', 'quiet', words.phone));
  } else {
    const qr = make('div', 'qr');
    if (window.THROQR) {
      try { qr.innerHTML = window.THROQR.svg(`${location.origin}/${path}`, { dark: 'var(--thro-ink)', light: 'var(--thro-chalk-raised)' }); } catch (e) { qr.hidden = true; }
    } else qr.hidden = true;
    const say = make('div');
    say.append(make('p', 'app-link-title', 'On your phone'), make('p', 'quiet', words.screen));
    box.append(qr, say);
  }
  return box;
}

const idFromPath = what => decodeURIComponent((location.pathname.match(new RegExp(`/${what}/([^/?#]+)`)) || [])[1]
  || new URLSearchParams(location.search).get(what) || '');

/** A league's own page: what THRØ holds for it, said first; then its table and fixtures where they exist, and its teams. */
async function mountLeague(where, titleEl, eyebrowEl) {
  const id = idFromPath('league').toLowerCase();
  let league;
  // One league, not the directory: the page is what gets shared, and it should not wait on 329 leagues to show one.
  try { league = await read(`/v1/leagues/${encodeURIComponent(id)}`); }
  catch (e) {
    if (!/^(no public league|leagueId must)/.test(e.message || '')) { fail(where, e, () => mountLeague(where, titleEl, eyebrowEl)); return; }
  }
  if (!league) {
    titleEl.textContent = 'No league at this address';
    where.replaceChildren(make('p', 'quiet', 'It may have ended, or been made private by whoever runs it, or the link may be old.'));
    const all = make('a', null, 'All leagues'); all.href = 'index.html'; where.append(all);
    return;
  }
  const season = shownSeason(league);
  titleEl.textContent = league.name;
  eyebrowEl.textContent = [heldAs(league) === 'run' ? 'League · run on THRØ' : 'League', league.playsOn ? `${league.playsOn} nights` : null, league.locality].filter(Boolean).join(' · ');
  document.title = `${league.name} — THRØ`;
  const parts = [make('p', 'lede-line', heldWords(league))];

  const go = make('div', 'cards');
  const card = (href, title, words, cta) => { const a = make('a', 'card'); a.href = href; a.append(make('h3', null, title), make('p', null, words), make('span', 'go', cta)); return a; };
  if (season && season.fixtures) {
    go.append(card(`table.html?season=${encodeURIComponent(season.leagueSeasonId)}`, 'Table', 'Worked out from the results beneath it.', 'See the table →'),
              card(`fixtures.html?season=${encodeURIComponent(season.leagueSeasonId)}`, 'Fixtures and results', `${plural(season.fixtures, 'fixture')} this season.`, 'See the fixtures →'));
  }
  if (league.website) go.append(card(league.website, 'Its own website', heldAs(league) === 'run' ? 'What the league publishes itself.' : 'Its fixtures, results and table are kept there.', 'Go to its website →'));
  if (go.children.length) parts.push(go);

  if (season && teamsIn(season)) {
    parts.push(make('h2', null, `${season.label} · ${plural(teamsIn(season), 'team')}`));
    for (const d of season.divisions) {
      if (!d.teams.length) continue;
      if (season.divisions.length > 1) parts.push(make('h3', null, d.name));
      const list = make('ul', 'rows');
      for (const t of d.teams) {
        const li = make('li'); const a = make('a'); a.href = `/team/${encodeURIComponent(t.teamId)}`;
        a.append(make('div', 'row-name', t.name), make('div', 'row-meta', t.venue ? [t.venue.name, t.venue.locality].filter(Boolean).join(' · ') : 'Its pub is not known yet'));
        li.append(a); list.append(li);
      }
      parts.push(list);
    }
  }
  if ((league.saidTeams || []).length) {
    parts.push(make('h2', null, 'Said by their players'));
    const list = make('ul', 'rows');
    for (const t of league.saidTeams) { const li = make('li'); const a = make('a'); a.href = `/team/${encodeURIComponent(t.teamId)}`; a.append(make('div', 'row-name', t.name)); li.append(a); list.append(li); }
    parts.push(list, make('p', 'quiet', 'These teams put themselves here. The league did not list them.'));
  }
  if (heldAs(league) !== 'run') {
    parts.push(make('h2', null, 'Do you run it?'),
      make('p', 'quiet', 'THRØ lists this league from elsewhere, so nobody here can take it over by asking. A league you start on the organiser’s desk is yours to run from the first minute: fixtures, results, the table, and the app for every player in it.'));
    const desk = make('a', 'primary', 'Start a league on the desk'); desk.href = 'organiser.html'; parts.push(desk);
  }
  parts.push(openInApp('league', league.leagueId, {
    phone: 'THRØ is a darts app for iPhone. In it this league is on the map, with its teams and the pubs they play at.',
    screen: 'Point your phone’s camera here. With THRØ on it, this league opens in the app: the map, its teams, and the pubs they play at.',
  }));
  if ((league.sources || []).length) {
    parts.push(make('p', 'quiet', 'Listed from ' + league.sources.map(s => `${s.source} (read ${day(s.retrievedOn)})`).join(', ') + '.'));
  }
  where.replaceChildren(...parts);
}

/** A team's page: who it is, where it plays, what it plays in. Nothing on it is a person unless they said they may be named. */
async function mountTeam(where, titleEl, eyebrowEl) {
  const id = idFromPath('team').toLowerCase();
  let team;
  try { team = await read(`/v1/teams/${encodeURIComponent(id)}`); }
  catch (e) {
    titleEl.textContent = 'No team at this address';
    where.replaceChildren(make('p', 'quiet', 'It may be private, or have folded, or the link may be old.'));
    return;
  }
  titleEl.textContent = team.name;
  eyebrowEl.textContent = ['Team', team.locality].filter(Boolean).join(' · ');
  document.title = `${team.name} — THRØ`;
  const parts = [];
  if (team.venue) parts.push(make('p', 'lede-line', `Plays at ${[team.venue.name, team.venue.locality, team.venue.postcode].filter(Boolean).join(', ')}.`));
  if ((team.seasons || []).length) {
    parts.push(make('h2', null, 'Playing in'));
    const list = make('ul', 'rows');
    for (const s of team.seasons) {
      const li = make('li'); const a = make('a');
      if (s.leagueSeasonId) a.href = `table.html?season=${encodeURIComponent(s.leagueSeasonId)}`;
      a.append(make('div', 'row-name', s.league), make('div', 'row-meta', [s.label, s.division].filter(Boolean).join(' · ')));
      li.append(a); list.append(li);
    }
    parts.push(list);
  }
  if ((team.saysItPlaysIn || []).length) {
    parts.push(make('h2', null, 'The team says it plays in'));
    const list = make('ul', 'rows');
    for (const l of team.saysItPlaysIn) { const li = make('li'); const a = make('a'); a.href = `/league/${encodeURIComponent(l.leagueId)}`; a.append(make('div', 'row-name', l.name)); li.append(a); list.append(li); }
    parts.push(list, make('p', 'quiet', 'Said by the team, not listed by the league.'));
  }
  const named = (team.roster || []).filter(m => m.name);
  parts.push(make('h2', null, 'On THRØ'),
    make('p', 'quiet', !(team.roster || []).length ? 'Nobody plays for it on THRØ yet.'
      : `${plural(team.roster.length, 'player')} on THRØ` + (named.length ? `: ${named.map(m => m.name).join(', ')}.` : '. None has chosen to be named.')));
  parts.push(openInApp('team', team.teamId, {
    phone: 'THRØ is a darts app for iPhone. In it you join this team with your captain’s code, and the side’s fixtures come to you.',
    screen: 'Point your phone’s camera here. With THRØ on it, this team opens in the app; your captain’s code joins you to it.',
  }));
  where.replaceChildren(...parts);
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
  const back = make('p', 'quiet');
  const toTable = make('a', null, 'This season’s table');
  toTable.href = `table.html?season=${encodeURIComponent(season)}`;
  back.append('← ', toTable);
  titleEl.textContent = 'Fixtures';
  eyebrowEl.textContent = fixtures.length ? `${fixtures.length} fixture${fixtures.length === 1 ? '' : 's'}` : 'Fixtures';
  document.title = 'Fixtures — THRØ';

  if (!fixtures.length) {
    where.replaceChildren(
      back,
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
  where.replaceChildren(back, 
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

/** True on a phone or a tablet: the device that may well have THRØ on it (PD-117). */
function onPhone() {
  return /iPhone|iPad|iPod|Android/i.test(navigator.userAgent)
    || (navigator.maxTouchPoints > 1 && window.matchMedia && matchMedia('(pointer: coarse)').matches);
}

/** What a passkey ceremony's refusal means, in words; the browser's own are a W3C address and a shrug. */
function passkeyWords(e) {
  if (e && (e.name === 'NotAllowedError' || e.name === 'AbortError')) {
    return onPhone() ? 'No passkey was used. Open THRØ on this phone instead — it signs this screen in.' : 'No passkey was used. Your phone is the easy way in.';
  }
  if (e && e.name === 'SecurityError') return 'This page cannot use a passkey here.';
  return (e && e.message) || 'The passkey did not sign you in.';
}

async function whoAmI() { return authorised('GET', '/v1/me'); }

function signOut() { session.clear(); }


/**
 * The sign-in gate every signed-in page shares: a passkey button when nobody is signed in, a sign-out button when
 * somebody is. Answers whether the page may go on to draw.
 */
/**
 * Signing in on a screen (PD-114). The phone holds the account, so the screen asks THRØ for a six-character code, the
 * person types it into the app, and this screen is signed in as them — no password, nothing to remember. A passkey is
 * the second way in, for anybody who made one in the app.
 */
let linkPolling = null;
function signInPanel(redraw) {
  const phone = onPhone();
  const box = make('div', 'entry signin');
  box.append(make('h2', null, phone ? 'Sign in with THRØ on this phone' : 'Sign in with your phone'));
  // PD-117: on a phone, the app that holds the account is a tap away. `thro://link/<code>` opens it on the sign-in
  // card with the code already in; the same path on thro.uk is a universal link for a code sent from elsewhere.
  const open = make('a', 'primary', 'Open THRØ'); open.hidden = true;
  const code = make('p', 'code', '······');
  code.setAttribute('aria-live', 'polite');
  const steps = make('ol', 'steps');
  const words = phone
    ? ['Tap Open THRØ', 'THRØ asks whether to sign this screen in — say yes', 'Come back here: you are in']
    : ['Open THRØ on your phone', 'You → Profile → Sign in on a screen', 'Type this code'];
  for (const step of words) steps.append(make('li', null, step));
  const elsewhere = phone ? make('p', 'quiet', 'THRØ on another phone? Open it there: You → Profile → Sign in on a screen, and type the code above.') : null;
  // PD-121: on a laptop, the same address as a QR code — a phone's camera opens THRØ on the card that approves it,
  // with nothing typed. Drawn here by qr.js, fetched only when a code is showing on a screen that is not a phone.
  const qr = make('div', 'qr'); qr.hidden = true;
  const qrWords = make('p', 'quiet', 'Or point your phone’s camera at this.'); qrWords.hidden = true;
  const said = make('p', 'quiet', 'Asking THRØ for a code…');
  const again = make('button', 'quiet-button', 'New code'); again.hidden = true;
  const acts = make('div', 'acts');
  // Apple and Google, only when the server names the web's client ids for them (PD-116): each SDK is fetched then,
  // never before, so a page without them loads nothing from either.
  providerButtons(acts, redraw, said);
  const passkey = make('button', 'quiet-button', 'Use a passkey you made in THRØ');
  passkey.onclick = async () => {
    passkey.disabled = true;
    try { await signInWithPasskey(); clearInterval(linkPolling); await redraw(); }
    catch (e) { said.textContent = passkeyWords(e); passkey.disabled = false; }
  };
  acts.append(again, passkey);
  if (phone) box.append(open, code, steps, elsewhere, said, acts);
  else box.append(code, steps, qr, qrWords, said, acts);

  let current = null;
  const expire = () => { clearInterval(linkPolling); current = null; said.textContent = 'That code has expired.'; again.hidden = false; code.textContent = '······'; open.hidden = true; qr.hidden = true; qrWords.hidden = true; };
  const tick = () => {
    if (!current) return;
    const left = Math.max(0, Math.round((current.until - Date.now()) / 1000));
    said.textContent = left > 0 ? `Good for ${Math.floor(left / 60)}:${String(left % 60).padStart(2, '0')} more.` : 'That code has expired.';
    if (left <= 0) expire();
  };
  const poll = async () => {
    if (!current) return;
    tick();
    try {
      const res = await fetch(`${API}/v1/auth/link/${encodeURIComponent(current.linkId)}?deviceId=${encodeURIComponent(deviceId())}`, { headers: { Accept: 'application/json' } });
      if (res.status === 200) {
        clearInterval(linkPolling); current = null;
        session.set(await res.json());
        await redraw();
      } else if (res.status === 410 || res.status === 404) expire();
    } catch { /* a missed poll is nothing; the next one asks again */ }
  };
  const ask = async () => {
    clearInterval(linkPolling);
    again.hidden = true;
    try {
      const link = await post('/v1/auth/link', { deviceId: deviceId() });
      current = { linkId: link.linkId, until: new Date(link.expiresAt) };
      code.textContent = link.code.split('').join(' ');
      open.href = `thro://link/${encodeURIComponent(link.code)}`;
      open.hidden = !phone;
      if (!phone) {
        // The universal link lives on thro.uk whichever host is serving this page.
        const site = /(^|\.)thro\.uk$/.test(location.hostname) ? location.origin : 'https://thro.uk';
        loadScript('qr.js').then(() => {
          qr.innerHTML = window.THROQR.svg(`${site}/link/${encodeURIComponent(link.code)}`, { dark: 'var(--thro-ink)', light: 'var(--thro-chalk-raised)' });
          qr.hidden = false; qrWords.hidden = false;
        }).catch(() => { /* no QR code is no loss: the code and the steps are above it */ });
      }
      tick();
      linkPolling = setInterval(poll, 2500);
    } catch (e) { said.textContent = e.message; again.hidden = false; }
  };
  // Coming back from the app — the phone's case — asks at once rather than waiting out the interval.
  document.addEventListener('visibilitychange', () => { if (!document.hidden) poll(); });
  again.onclick = ask;
  ask();
  return box;
}

/** A script from a provider, loaded once and only when asked for. */
function loadScript(src) {
  return new Promise((resolve, reject) => {
    if (document.querySelector(`script[src="${src}"]`)) { resolve(); return; }
    const s = document.createElement('script'); s.src = src; s.async = true; s.onload = resolve; s.onerror = () => reject(new Error(`${src} did not load`));
    document.head.append(s);
  });
}

async function providerButtons(where, redraw, said) {
  let p;
  try { p = await read('/v1/auth/providers'); } catch { return; }
  const finish = async (path, idToken, nonce) => {
    const s = await post(path, { idToken, deviceId: deviceId(), ...(nonce ? { nonce } : {}) });
    session.set(s); clearInterval(linkPolling); await redraw();
  };
  if (p.apple) {
    const b = make('button', 'quiet-button', 'Sign in with Apple');
    b.onclick = async () => {
      b.disabled = true;
      try {
        await loadScript('https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_GB/appleid.auth.js');
        const raw = crypto.getRandomValues(new Uint8Array(16)); const nonce = Array.from(raw, x => x.toString(16).padStart(2, '0')).join('');
        const hashed = B64U.fromBytes(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(nonce)));
        window.AppleID.auth.init({ clientId: p.apple, scope: 'name', redirectURI: `${location.origin}/`, usePopup: true, nonce: hashed });
        const r = await window.AppleID.auth.signIn();
        await finish('/v1/auth/apple', r.authorization.id_token, nonce);
      } catch (e) { said.textContent = e.message || 'Apple did not sign you in.'; b.disabled = false; }
    };
    where.append(b);
  }
  if (p.google) {
    const b = make('button', 'quiet-button', 'Sign in with Google');
    b.onclick = async () => {
      b.disabled = true;
      try {
        await loadScript('https://accounts.google.com/gsi/client');
        const raw = crypto.getRandomValues(new Uint8Array(16)); const nonce = Array.from(raw, x => x.toString(16).padStart(2, '0')).join('');
        await new Promise((resolve, reject) => {
          window.google.accounts.id.initialize({ client_id: p.google, nonce, callback: async res => { try { await finish('/v1/auth/google', res.credential, nonce); resolve(); } catch (e) { reject(e); } } });
          window.google.accounts.id.prompt(n => { if (n.isNotDisplayed && n.isNotDisplayed()) reject(new Error('Google could not show its sign-in here. Use your phone or a passkey.')); });
        });
      } catch (e) { said.textContent = e.message || 'Google did not sign you in.'; b.disabled = false; }
    };
    where.append(b);
  }
}

function signInGate(signInEl, where, prompt, redraw) {
  if (!session.get()) {
    signInEl.replaceChildren(signInPanel(redraw));
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

/** THRØ's reading of a report (PD-118) in words, or null when there is none worth a line. */
function readingWords(j) {
  if (!j || j.severity === null || j.severity === undefined) return null;
  const about = {
    harassment: 'harassment', hate_or_slur: 'a slur or hate', sexual: 'sexual', impersonation_or_fraud: 'impersonation or a scam',
    cheating_or_dispute: 'a disputed result', spam: 'spam', other: 'something else',
  }[j.category] || j.category;
  const level = ['nothing to act on', 'mildly unpleasant', 'clearly against the rules', 'serious harm or danger'][Math.min(3, Math.max(0, Math.round(j.severity)))];
  const child = j.childSafety >= 0.85 ? 'a child may be at risk' : j.childSafety >= 0.5 ? 'possibly about a child' : 'not about a child';
  return `THRØ's reading: ${about} (${Math.round(j.confidence * 100)}% sure) · ${level} · ${child}. A hint, not an answer.`;
}

async function mountModeration(where, signInEl) {
  const draw = async () => {
    if (!signInGate(signInEl, where, 'Sign in to answer reports.', draw)) return;
    let data;
    try { data = await authorised('GET', '/v1/reports'); } catch (e) { fail(where, e); return; }
    const open = data.reports.filter(r => r.decisions === 0);
    const answered = data.reports.filter(r => r.decisions > 0);
    const parts = [
      make('p', 'quiet', 'A decision is recorded, with your name and reason, and kept — and it does what it says: '
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
      make('div', 'row-meta', `${r.raisedBy === 'thro' ? 'Raised by THRØ' : 'Reported'} ${when(r.reportedAt)} · answer by ${when(r.answerDueAt)}`
        + (r.decisions ? ` · answered ${r.decisions} time${r.decisions === 1 ? '' : 's'}` : '')),
    );
    // PD-118: what THRØ made of it, beside it — a hint for the person answering, never an answer.
    const reading = readingWords(r.reading);
    if (reading) box.append(make('p', 'reading', reading));
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
    try { mine = await authorised('GET', '/v1/me/seasons'); } catch (e) { fail(where, e, draw); return; }
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
    // The one gate every signed-in page shares (PD-114, PD-117): the phone first, a passkey second.
    if (!signInGate(signInEl, where, 'Sign in to enter this season’s results.', draw)) return;

    // The season as its administrator sees it (PD-099): its dates, divisions and every team that asked in. It is
    // also the page's one question about authority — somebody who does not run this season is told so here,
    // once, rather than by every button refusing in turn.
    let plan, data, policy, registrations, registered, proposals, standings, offers;
    try {
      plan = await authorised('GET', `/v1/seasons/${encodeURIComponent(season)}/teams`);
      offers = await read('/v1/auth/providers').catch(() => ({}));
      data = await read(`/v1/seasons/${encodeURIComponent(season)}/fixtures`);
      policy = (await authorised('GET', `/v1/seasons/${encodeURIComponent(season)}/policy`)).policy;
      ({ registrations, registered } = await authorised('GET', `/v1/seasons/${encodeURIComponent(season)}/registrations`));
      proposals = (await authorised('GET', `/v1/seasons/${encodeURIComponent(season)}/proposals`)).proposals;
      standings = await read(`/v1/seasons/${encodeURIComponent(season)}/standings`);
    } catch (e) { fail(where, e, draw); return; }

    const todo = (data.fixtures || []).filter(f => !f.decided);
    const done = (data.fixtures || []).filter(f => f.decided);
    const title = document.getElementById('title'); if (title) title.textContent = plan.league.name;
    const eyebrow = document.getElementById('eyebrow'); if (eyebrow) eyebrow.textContent = `Run this league · ${plan.label}`;
    document.title = `${plan.league.name} — THRØ`;
    const parts = [...(offers && offers.reads ? [tellSection(plan, data, draw)] : []), ...leagueSection(plan, draw), ...pointsSection(plan, standings, draw), ...teamsSection(plan, draw), ...registrationsSection(plan, policy, registrations, draw), ...registeredSection(plan, registered, draw), ...requestsSection(plan, proposals, draw)];

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
    parts.push(scheduler(plan, draw, !!(offers && offers.reads)));
    parts.push(historySection(plan));
    where.replaceChildren(...parts);
  };

  /**
   * Who changed what (PD-120): the season's own records read back as sentences — who put that result in, who moved
   * that fixture, who set the rules. Folded away, read only when somebody opens it, and only for the people who run it.
   */
  function historySection(plan) {
    const fold = make('details', 'fold');
    fold.append(make('summary', null, 'Who changed what'));
    const body = make('div'); fold.append(body);
    let read = false;
    fold.addEventListener('toggle', async () => {
      if (!fold.open || read) return;
      read = true; body.replaceChildren(make('p', 'quiet', 'Reading…'));
      try {
        const { entries } = await authorised('GET', `/v1/seasons/${encodeURIComponent(plan.leagueSeasonId)}/history`);
        if (!entries.length) { body.replaceChildren(make('p', 'quiet', 'Nothing has been recorded in this season yet.')); return; }
        const list = make('ul', 'rows');
        for (const e of entries) {
          const li = make('li');
          li.append(make('div', 'row-name', e.what), make('div', 'row-meta', `${e.who || 'An official'} · ${when(e.at)}`));
          list.append(li);
        }
        body.replaceChildren(make('p', 'quiet', 'Newest first. Nothing here is edited: a correction is a second line, and the first stays.'), list);
      } catch (e) { read = false; body.replaceChildren(make('p', 'note', e.message)); }
    });
    return fold;
  }

  /**
   * Tell THRØ (PD-119): one sentence, read by a System One model against this season's own fixtures and teams into a
   * card — a result, an award, an annulment, a new fixture — that the secretary confirms. THRØ reads; the person
   * records. Whatever the model was unsure of is the one thing the card asks about, with the choice already made.
   */
  function tellSection(plan, data, redraw) {
    const box = make('div', 'entry tell');
    box.append(make('h2', null, 'Tell THRØ'),
               make('p', 'quiet', 'Say what happened and THRØ fills in the card; you confirm it. Try “Grange A beat Dolphin 5–3 last night”, “Walkover to Riverside, Grange didn’t turn up”, “Move Riverside v Grange to next Thursday”, or “Add Riverside A v Dolphin next Thursday at 8”.'));
    const form = make('div', 'entry-form');
    const text = make('input'); text.type = 'text'; text.maxLength = 400; text.placeholder = 'Grange A beat Dolphin 5–3 last night';
    text.setAttribute('aria-label', 'What happened'); text.style.flex = '1 1 22rem'; text.autocomplete = 'off';
    const go = make('button', 'primary', 'Read it');
    const said = make('p', 'note'); said.hidden = true;
    const card = make('div');
    form.append(text, go);
    box.append(form, said, card);
    const readIt = async () => {
      const t = text.value.trim();
      if (!t) { text.focus(); return; }
      go.disabled = true; said.hidden = true; card.replaceChildren(make('p', 'quiet', 'Reading…'));
      try {
        const u = await authorised('POST', `/v1/seasons/${encodeURIComponent(plan.leagueSeasonId)}/understand`, { text: t });
        card.replaceChildren(readCard(u));
      } catch (e) { card.replaceChildren(); said.hidden = false; said.textContent = e.message; }
      go.disabled = false;
    };
    go.onclick = readIt;
    text.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); readIt(); } });

    const undecided = (data.fixtures || []).filter(f => !f.decided);
    const sure = p => p >= 0.75 ? 'sure' : p >= 0.6 ? 'fairly sure' : 'not sure';

    function readCard(u) {
      const c = make('div', 'entry read');
      if (u.act === 'none') {
        c.append(make('p', null, u.say));
        return c;
      }
      const what = { result: 'a result', award: 'an award', void: 'an annulment', schedule: 'a new fixture', move: 'a move', points: 'the points rules' }[u.act] || u.act;
      c.append(make('div', 'row-name', u.say),
               make('div', 'row-meta', `Read as ${what} · THRØ is ${sure(u.confidence)}${u.doubt ? ` · check ${u.doubt === 'side' ? 'who it goes to' : 'the ' + u.doubt}` : ''}`));
      const fields = make('div', 'entry-form');
      const note = make('p', 'note'); note.hidden = true;
      // The fixture, when the act is about one: the model's pick, with its runners-up and every open fixture to hand.
      let fixture = null;
      if (['result', 'award', 'void', 'move'].includes(u.act)) {
        fixture = make('select'); fixture.setAttribute('aria-label', 'Which fixture');
        const seen = new Set();
        const add = (id, label) => { if (seen.has(id)) return; seen.add(id); fixture.append(new Option(label, id)); };
        if (u.fixture) add(u.fixture.fixtureId, `${u.fixture.home} v ${u.fixture.away}, ${when(u.fixture.scheduledAt)}`);
        for (const a of (u.fixture ? u.fixture.alternatives : [])) add(a.fixtureId, a.label);
        for (const f of (u.act === 'void' ? (data.fixtures || []).filter(f => f.decided) : undecided)) add(f.fixtureId, `${f.home || 'A team'} v ${f.away || 'A team'}, ${when(f.scheduledAt)}`);
        if (!seen.size) { c.append(make('p', 'quiet', u.act === 'void' ? 'No result in this season to annul.' : 'No fixture in this season is waiting for a result.')); return c; }
        fields.append(fixture);
      }
      let home, away, to, reason, on, at, homeTeam, awayTeam;
      if (u.act === 'result') {
        home = make('input'); home.type = 'number'; home.min = '0'; home.inputMode = 'numeric'; home.setAttribute('aria-label', 'Legs for the home side');
        away = make('input'); away.type = 'number'; away.min = '0'; away.inputMode = 'numeric'; away.setAttribute('aria-label', 'Legs for the away side');
        if (u.result) { home.value = u.result.legsHome; away.value = u.result.legsAway; }
        fields.append(home, make('span', 'v', '–'), away);
      }
      if (u.act === 'award') {
        to = make('select'); to.setAttribute('aria-label', 'Awarded to');
        const fill = () => {
          const f = (data.fixtures || []).find(x => x.fixtureId === fixture.value);
          to.replaceChildren();
          if (f) { to.append(new Option(f.home || 'The home side', f.homeTeamId), new Option(f.away || 'The away side', f.awayTeamId)); }
          if (u.award && [...to.options].some(o => o.value === u.award.toTeamId)) to.value = u.award.toTeamId;
        };
        fill(); fixture.onchange = fill;
        fields.append(to);
      }
      if (u.act === 'award' || u.act === 'void') {
        reason = make('input'); reason.type = 'text'; reason.maxLength = 600; reason.value = u.reason || u.text; reason.setAttribute('aria-label', 'Why'); reason.style.flex = '1 1 16rem';
        fields.append(reason);
      }
      if (u.act === 'schedule') {
        homeTeam = make('select'); homeTeam.setAttribute('aria-label', 'Home team');
        awayTeam = make('select'); awayTeam.setAttribute('aria-label', 'Away team');
        for (const t of plan.teams.filter(t => t.status === 'accepted')) { homeTeam.append(new Option(t.name, t.teamId)); awayTeam.append(new Option(t.name, t.teamId)); }
        if (u.schedule) { homeTeam.value = u.schedule.homeTeamId; awayTeam.value = u.schedule.awayTeamId; }
        on = make('input'); on.type = 'date'; on.setAttribute('aria-label', 'On'); on.min = plan.startsOn; on.max = plan.endsOn;
        at = make('input'); at.type = 'time'; at.setAttribute('aria-label', 'At');
        if (u.schedule && u.schedule.on) on.value = u.schedule.on;
        if (u.schedule && u.schedule.time) at.value = u.schedule.time.slice(0, 5);
        fields.append(homeTeam, make('span', 'v', 'v'), awayTeam, on, at);
      }
      let pts = null;
      if (u.act === 'points') {
        // The parts the sentence stated are filled; a part left blank is left as the league has it now.
        pts = {};
        for (const [key, text] of [['win', 'a win'], ['draw', 'a draw'], ['loss', 'a loss'], ['pointsPerLegWon', 'per leg won']]) {
          const box = make('input'); box.type = 'number'; box.min = '0'; box.max = '20'; box.inputMode = 'numeric';
          if (u.points && u.points[key] !== null && u.points[key] !== undefined) box.value = u.points[key];
          const l = make('label', 'spec', text + ' '); l.append(box); fields.append(l); pts[key] = box;
        }
      }
      if (u.act === 'move') {
        on = make('input'); on.type = 'date'; on.setAttribute('aria-label', 'The new day'); on.min = plan.startsOn; on.max = plan.endsOn;
        at = make('input'); at.type = 'time'; at.setAttribute('aria-label', 'The new time');
        if (u.move) { on.value = u.move.on; at.value = u.move.time.slice(0, 5); }
        fields.append(make('span', 'v', '→'), on, at);
      }
      const label = { result: 'Record it', award: 'Award it', void: 'Annul it', schedule: 'Add the fixture', move: 'Move it', points: 'Set the rules' }[u.act];
      const confirm = make('button', 'primary', label);
      const no = make('button', 'quiet-button', 'Not what I meant');
      no.onclick = () => { card.replaceChildren(); text.focus(); };
      confirm.onclick = async () => {
        confirm.disabled = true; note.hidden = true;
        try {
          if (u.act === 'result') {
            const h = parseInt(home.value, 10), a = parseInt(away.value, 10);
            if (!Number.isInteger(h) || !Number.isInteger(a) || h < 0 || a < 0) throw new Error('A result is two numbers, one for each side.');
            await authorised('POST', `/v1/fixtures/${encodeURIComponent(fixture.value)}/result`, { legsHome: h, legsAway: a });
          } else if (u.act === 'award') {
            if (reason.value.trim().length < 3) throw new Error('Say why — this is kept.');
            const f = (data.fixtures || []).find(x => x.fixtureId === fixture.value);
            await authorised('POST', `/v1/fixtures/${encodeURIComponent(fixture.value)}/award`, { toTeamId: to.value, reason: reason.value.trim(), ...(f && f.decided ? { supersedes: f.decided.outcomeId } : {}) });
          } else if (u.act === 'void') {
            if (reason.value.trim().length < 3) throw new Error('Say why — this is kept.');
            const f = (data.fixtures || []).find(x => x.fixtureId === fixture.value);
            if (!f || !f.decided) throw new Error('Only a fixture with a result can be annulled.');
            await authorised('POST', `/v1/fixtures/${encodeURIComponent(fixture.value)}/void`, { supersedes: f.decided.outcomeId, reason: reason.value.trim() });
          } else if (u.act === 'points') {
            const body = {};
            for (const [key, box] of Object.entries(pts)) if (box.value !== '') body[key] = Number(box.value);
            if (!Object.keys(body).length) throw new Error('Say at least how many points a win is worth.');
            await authorised('POST', `/v1/seasons/${encodeURIComponent(plan.leagueSeasonId)}/points`, body);
          } else if (u.act === 'move') {
            if (!on.value || !at.value) throw new Error('A rearrangement is a day and a time.');
            const f = (data.fixtures || []).find(x => x.fixtureId === fixture.value);
            if (!f) throw new Error('Choose the fixture to move.');
            // The same command the fixture's own Move form sends, so its history reads the same either way.
            const res = await fetch(`${API}/v1/commands`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session.get().accessToken}`, 'X-Thro-Device': deviceId() },
              body: JSON.stringify({ type: 'RearrangeFixture', commandId: crypto.randomUUID(), fixtureId: f.fixtureId,
                                     to: new Date(`${on.value}T${at.value}`).toISOString(), expectedVersion: f.version }),
            });
            const body = await res.json().catch(() => ({}));
            if (res.status === 409) throw new Error('This fixture changed while you were looking at it. Reload, and move the one that is standing now.');
            if (!res.ok) throw new Error(body.error || body.reason || `THRØ answered ${res.status}.`);
          } else if (u.act === 'schedule') {
            if (homeTeam.value === awayTeam.value) throw new Error('A fixture is between two different teams.');
            if (!on.value || !at.value) throw new Error('A fixture has a date and a time.');
            const scheduledAt = new Date(`${on.value}T${at.value}:00`).toISOString();
            await authorised('POST', `/v1/seasons/${encodeURIComponent(plan.leagueSeasonId)}/fixtures`, { fixtures: [{ homeTeamId: homeTeam.value, awayTeamId: awayTeam.value, scheduledAt }] });
          }
          note.hidden = false; note.textContent = 'Done.'; text.value = '';
          setTimeout(redraw, 700);
        } catch (e) { note.hidden = false; note.textContent = e.message; confirm.disabled = false; }
      };
      const acts = make('div', 'acts'); acts.append(confirm, no);
      c.append(fields, acts, note, make('p', 'quiet', 'Nothing is recorded until you press the button. Correcting later works as it always has.'));
      return c;
    }
    return box;
  }

  /**
   * The league this season belongs to, and what its starter may do to it (PD-103): rename it, keep it off the public
   * list, or end it. A league THRØ lists from elsewhere is named and left alone — its organiser did not start it here.
   */
  function leagueSection(plan, redraw) {
    const l = plan.league;
    const standing = l.endedAt ? `ended ${when(l.endedAt)}` : (l.visibility === 'private' ? 'private — off the public list' : 'public');
    const out = [make('h2', null, 'The season'), make('p', 'quiet', `${plan.label} · ${day(plan.startsOn)} to ${day(plan.endsOn)} · the league is ${standing}.`)];
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
    out.push(box, nextSeason(l, redraw));
    return out;
  }

  /** The league's next season (PD-100): a label, its dates, its divisions — opened by the starter, run by them. */
  function nextSeason(l, redraw) {
    const box = make('div', 'entry');
    box.append(make('h2', null, 'Open the next season'));
    const form = make('div', 'entry-form');
    const label = make('input'); label.type = 'text'; label.placeholder = 'Season, e.g. 2027-28'; label.maxLength = 40;
    label.setAttribute('aria-label', 'The next season’s label');
    const starts = make('input'); starts.type = 'date'; starts.setAttribute('aria-label', 'First day');
    const ends = make('input'); ends.type = 'date'; ends.setAttribute('aria-label', 'Last day');
    const divisions = make('input'); divisions.type = 'text'; divisions.placeholder = 'Divisions, comma-separated, optional';
    divisions.setAttribute('aria-label', 'Divisions');
    const go = make('button', 'quiet-button', 'Open it');
    const said = make('p', 'note'); said.hidden = true;
    go.onclick = async () => {
      if (!label.value.trim() || !starts.value || !ends.value) { said.hidden = false; said.textContent = 'A season needs a label and two dates.'; return; }
      go.disabled = true;
      try {
        const opened = await authorised('POST', `/v1/leagues/${encodeURIComponent(l.leagueId)}/seasons`,
          { label: label.value.trim(), startsOn: starts.value, endsOn: ends.value,
            divisions: divisions.value.split(',').map(d => d.trim()).filter(Boolean) });
        location.href = `organiser.html?season=${encodeURIComponent(opened.season.leagueSeasonId)}`;
      } catch (e) { said.hidden = false; said.textContent = e.message; go.disabled = false; }
    };
    form.append(label, starts, ends, divisions, go);
    box.append(form, said);
    return box;
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
    if (accepted.length && plan.divisions.length) out.push(divisionMover(plan, accepted, redraw));
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
   * Registering players (PD-107): what a registration with this season needs, and the ones its teams have sent.
   * THRØ checks the facts it can (a name, an age band, a claimed account, consent); anything else — a fee, a form —
   * is confirmed by hand on the team's side and shown here as their word, not THRØ's tick. Sent is not accepted:
   * the one act that registers anybody is the answer given here, from a date.
   */
  function registrationsSection(plan, policy, registrations, redraw) {
    const out = [make('h2', null, 'Registrations')];
    const box = make('div', 'entry');
    const said = make('p', 'note'); said.hidden = true;
    const say = text => { said.hidden = false; said.textContent = text; };
    const facts = [['name', 'a name'], ['age_band', 'an age band'], ['account_claimed', 'a claimed THRØ account'], ['consent', 'consent to be listed']];
    const has = policy ? new Set(policy.requires) : new Set(['name', 'age_band', 'consent']);
    box.append(make('p', 'quiet', policy
      ? `Version ${policy.version}, in force from ${day(policy.effectiveFrom)}. THRØ checks: ${policy.requires.map(r => r.replace('_', ' ')).join(', ') || 'nothing'}.`
        + (policy.manualRequirements.length ? ` Confirmed by hand: ${policy.manualRequirements.join(', ')}.` : '')
        + (policy.registrationClosesOn ? ` Closes ${day(policy.registrationClosesOn)}.` : ` Due ${policy.deadlineDaysBeforeFirstFixture} days before a team's first fixture.`)
      : 'No policy yet, so no team owes a registration. Say what one needs and the teams will be asked.'));
    const form = make('div', 'entry-form');
    const boxes = facts.map(([key, text]) => { const [c, l] = check(text, has.has(key)); c.value = key; return [c, l]; });
    const manual = make('input'); manual.type = 'text'; manual.placeholder = 'Confirmed by hand, e.g. fee, form'; manual.maxLength = 120;
    manual.value = policy ? policy.manualRequirements.join(', ') : '';
    manual.setAttribute('aria-label', 'Requirements a person confirms by hand, separated by commas');
    const days = make('input'); days.type = 'number'; days.min = 0; days.max = 365; days.value = policy && policy.deadlineDaysBeforeFirstFixture != null ? policy.deadlineDaysBeforeFirstFixture : 7;
    days.setAttribute('aria-label', 'Days before a team’s first fixture that a registration is due');
    const daysLabel = make('label', 'spec', 'due '); daysLabel.append(days, ' days before the first fixture');
    const set = make('button', 'primary', policy ? 'Set a new version' : 'Set the policy');
    set.onclick = async () => {
      set.disabled = true;
      try {
        const made = await authorised('POST', `/v1/seasons/${encodeURIComponent(plan.leagueSeasonId)}/policy`, {
          requires: boxes.filter(([c]) => c.checked).map(([c]) => c.value),
          manualRequirements: manual.value.split(',').map(x => x.trim()).filter(Boolean),
          deadlineDaysBeforeFirstFixture: Number(days.value),
        });
        say(`Version ${made.policy.version} is in force. Teams find out what they owe when they next look.`);
        setTimeout(redraw, 900);
      } catch (e) { say(e.message); set.disabled = false; }
    };
    form.append(...boxes.map(([, l]) => l), manual, daysLabel, set);
    box.append(form, said);
    out.push(box);

    if (!registrations.length) {
      if (policy) out.push(make('p', 'quiet', 'No team has sent a registration yet.'));
      return out;
    }
    const open = registrations.filter(r => r.state === 'delivered' || r.state === 'acknowledged');
    const answered = registrations.filter(r => !(r.state === 'delivered' || r.state === 'acknowledged'));
    const list = make('ul', 'rows');
    for (const r of open) list.append(registrationRow(r, redraw));
    if (open.length) out.push(make('p', 'quiet', `${open.length} waiting for your answer.`), list);
    if (answered.length) {
      const doneList = make('ul', 'rows');
      for (const r of answered) {
        const li = make('li'); const head = make('div', 'row-head');
        head.append(make('div', 'row-name', `${r.player || 'A player'} · ${r.team}`), make('span', 'quiet', r.state.replace('_', ' ')));
        li.append(head); doneList.append(li);
      }
      out.push(make('p', 'quiet', `${answered.length} answered.`), doneList);
    }
    return out;
  }

  /** One registration waiting for the league: accepted from a date, or rejected with a reason. */
  function registrationRow(r, redraw) {
    const li = make('li');
    const head = make('div', 'row-head');
    head.append(make('div', 'row-name', `${r.player || 'A player THRØ may not name'} · ${r.team}`),
                make('span', 'quiet', `sent ${when(r.sentAt)}`));
    const form = make('div', 'entry-form');
    const from = make('input'); from.type = 'date'; from.value = new Date().toISOString().slice(0, 10);
    from.setAttribute('aria-label', 'Registered from');
    const note = make('input'); note.type = 'text'; note.placeholder = 'Reason, if rejecting'; note.maxLength = 200;
    note.setAttribute('aria-label', 'A note, required for a rejection');
    const said = make('p', 'note'); said.hidden = true;
    const answer = async (body, button) => {
      button.disabled = true;
      try {
        await authorised('POST', `/v1/submissions/${encodeURIComponent(r.submissionId)}/answer`, body);
        redraw();
      } catch (e) { said.hidden = false; said.textContent = e.message; button.disabled = false; }
    };
    const accept = make('button', 'primary', 'Accept from');
    accept.onclick = () => answer({ answer: 'accepted', registeredFrom: from.value, note: note.value.trim() || undefined }, accept);
    const reject = make('button', 'quiet-button', 'Reject');
    reject.onclick = () => {
      if (!note.value.trim()) { said.hidden = false; said.textContent = 'A rejection says why: write the reason first.'; return; }
      answer({ answer: 'rejected', note: note.value.trim() }, reject);
    };
    form.append(accept, from, note, reject);
    li.append(head, form, said);
    return li;
  }

  /**
   * Requests to move fixtures (PD-108): a team proposed a date, the other team agrees or declines from its inbox, and
   * the league applies what was agreed here — through the same command as any rearrangement, naming the version it
   * last saw, so the fixture's history says which proposal moved it. Nothing here moves a fixture the teams did not agree.
   */
  function requestsSection(plan, proposals, redraw) {
    if (!proposals.length) return [];
    const out = [make('h2', null, 'Requests to move a fixture'), make('p', 'quiet', `${proposals.length} open.`)];
    const list = make('ul', 'rows');
    for (const p of proposals) {
      const li = make('li');
      const head = make('div', 'row-head');
      head.append(make('div', 'row-name', `${p.byTeam} v ${p.toTeam}`),
                  // PD-128: and where, when the proposal names somewhere else to play it.
                  make('span', 'quiet', `${when(p.scheduledAt)} → ${when(p.to)}${p.venue ? ` at ${p.venue.name}` : ''}${p.reason ? ` — ${p.reason}` : ''}`));
      const said = make('p', 'note'); said.hidden = true;
      if (p.state === 'accepted') {
        const apply = make('button', 'primary', p.venue ? 'Apply the agreed date and place' : 'Apply the agreed date');
        apply.onclick = async () => {
          apply.disabled = true;
          try {
            await authorised('POST', `/v1/proposals/${encodeURIComponent(p.proposalId)}/apply`, { expectedVersion: p.fixtureVersion });
            redraw();
          } catch (e) { said.hidden = false; said.textContent = e.message; apply.disabled = false; }
        };
        head.append(apply);
      } else {
        head.append(make('span', 'quiet', `waiting for ${p.toTeam}`));
      }
      li.append(head, said);
      list.append(li);
    }
    out.push(list);
    return out;
  }

  /**
   * Which division each team plays in (PD-112). A move is refused while the team has an undecided fixture in its
   * division — the server says so, and the fixture is rearranged or voided first.
   */
  function divisionMover(plan, accepted, redraw) {
    const box = make('div', 'entry');
    box.append(make('h2', null, 'Divisions'));
    const list = make('ul', 'rows');
    for (const t of accepted) {
      const li = make('li');
      const head = make('div', 'row-head');
      head.append(make('div', 'row-name', t.name));
      const pick = make('select'); pick.setAttribute('aria-label', `${t.name}’s division`);
      pick.append(new Option('No division', ''));
      for (const d of plan.divisions) pick.append(new Option(d.name, d.divisionId));
      pick.value = t.divisionId || '';
      const said = make('p', 'note'); said.hidden = true;
      pick.onchange = async () => {
        pick.disabled = true;
        try { await authorised('POST', `/v1/seasons/${encodeURIComponent(plan.leagueSeasonId)}/teams/${encodeURIComponent(t.teamId)}/division`, { divisionId: pick.value || null }); redraw(); }
        catch (e) { said.hidden = false; said.textContent = e.message; pick.value = t.divisionId || ''; pick.disabled = false; }
      };
      head.append(pick);
      li.append(head, said);
      list.append(li);
    }
    box.append(list);
    return box;
  }

  /**
   * Who is registered, by any route (PD-112), and a transfer: the current registration ends on a date and a new one
   * with the other team begins, naming the one it supersedes. Registered throughout; the old row stays.
   */
  function registeredSection(plan, registered, redraw) {
    if (!registered.length) return [];
    const current = registered.filter(r => !r.until);
    const out = [make('h2', null, 'Registered players'), make('p', 'quiet', `${current.length} registered now${registered.length > current.length ? `, ${registered.length - current.length} earlier registrations kept` : ''}.`)];
    const list = make('ul', 'rows');
    for (const r of registered) {
      const li = make('li');
      const head = make('div', 'row-head');
      head.append(make('div', 'row-name', `${r.player || 'A player THRØ may not name'} · ${r.team || 'no team'}`),
                  make('span', 'quiet', `from ${day(r.from)}${r.until ? ` to ${day(r.until)}` : ''} · ${r.source}${r.supersedes ? ' · transfer' : ''}`));
      li.append(head);
      list.append(li);
    }
    out.push(list);
    const teams = plan.teams.filter(t => t.status === 'accepted');
    if (current.length && teams.length > 1) {
      const box = make('div', 'entry');
      box.append(make('h2', null, 'Transfer a player'));
      const form = make('div', 'entry-form');
      const who = make('select'); who.setAttribute('aria-label', 'The player');
      for (const r of current) who.append(new Option(`${r.player || 'A player'} (${r.team || 'no team'})`, r.playerId));
      const to = make('select'); to.setAttribute('aria-label', 'To which team');
      for (const t of teams) to.append(new Option(t.name, t.teamId));
      const from = make('input'); from.type = 'date'; from.value = new Date().toISOString().slice(0, 10); from.setAttribute('aria-label', 'From');
      const why = make('input'); why.type = 'text'; why.placeholder = 'Why, e.g. moved house'; why.maxLength = 200; why.setAttribute('aria-label', 'Why');
      const said = make('p', 'note'); said.hidden = true;
      const go = make('button', 'primary', 'Transfer');
      go.onclick = async () => {
        if (!why.value.trim()) { said.hidden = false; said.textContent = 'A transfer says why.'; return; }
        go.disabled = true;
        try { await authorised('POST', `/v1/seasons/${encodeURIComponent(plan.leagueSeasonId)}/registrations/${encodeURIComponent(who.value)}/transfer`, { toTeamId: to.value, from: from.value, note: why.value.trim() }); redraw(); }
        catch (e) { said.hidden = false; said.textContent = e.message; go.disabled = false; }
      };
      form.append(who, to, from, why, go);
      box.append(form, said);
      out.push(box);
    }
    return out;
  }

  /**
   * The points rules the table is ordered by (PD-112). Until the league sets its own, the table says it is ordered by
   * THRØ's standard; once set, by this league's own rules — the same sentence the public table shows.
   */
  function pointsSection(plan, standings, redraw) {
    const rules = standings.rules || {};
    const box = make('div', 'entry');
    box.append(make('h2', null, 'Points'), make('p', 'quiet', rules.says || 'Ordered by THRØ’s standard until the league sets its own.'));
    const form = make('div', 'entry-form');
    const num = (label, value) => { const i = make('input'); i.type = 'number'; i.min = 0; i.max = 20; i.value = value; i.setAttribute('aria-label', label); const l = make('label', 'spec', label + ' '); l.append(i); return [i, l]; };
    const [win, winL] = num('a win', 2), [draw, drawL] = num('a draw', 1), [loss, lossL] = num('a loss', 0), [leg, legL] = num('per leg won', 0);
    const order = make('input'); order.type = 'text'; order.value = (rules.orderedBy || ['points', 'leg_difference', 'legs_for', 'head_to_head']).join(', '); order.maxLength = 80;
    order.setAttribute('aria-label', 'Tie-breaks, in order: points, leg_difference, legs_for, head_to_head, played');
    const said = make('p', 'note'); said.hidden = true;
    const set = make('button', 'primary', 'Set the rules');
    set.onclick = async () => {
      set.disabled = true;
      try {
        const made = await authorised('POST', `/v1/seasons/${encodeURIComponent(plan.leagueSeasonId)}/points`, {
          win: Number(win.value), draw: Number(draw.value), loss: Number(loss.value), pointsPerLegWon: Number(leg.value),
          tieBreak: order.value.split(',').map(x => x.trim().toLowerCase().replace(/ /g, '_')).filter(Boolean),
        });
        said.hidden = false; said.textContent = `Version ${made.points.version}: ${made.points.says}`;
        setTimeout(redraw, 900);
      } catch (e) { said.hidden = false; said.textContent = e.message; set.disabled = false; }
    };
    form.append(winL, drawL, lossL, legL, order, set);
    box.append(form, said, make('p', 'quiet', 'Tie-breaks in order, from: points, leg_difference, legs_for, head_to_head, played.'));
    return [box];
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
  function scheduler(plan, redraw, reads) {
    const box = make('div', 'entry');
    box.append(make('h2', null, 'Add fixtures'));
    const accepted = plan.teams.filter(t => t.status === 'accepted');
    if (accepted.length < 2) {
      box.append(make('p', 'quiet', 'A fixture needs two teams in the season. Let them in first.'));
      return box;
    }
    const named = id => (plan.teams.find(t => t.teamId === id) || {}).name || 'A team';
    const label = (text, input) => { const l = make('label', 'spec', text + ' '); l.append(input); return l; };
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
    const onDay = make('input'); onDay.type = 'date'; onDay.min = plan.startsOn; onDay.max = plan.endsOn; onDay.setAttribute('aria-label', 'The day');
    const time = make('input'); time.type = 'time'; time.value = '19:30';
    const add = make('button', 'primary', 'Add');
    const refill = () => {
      for (const s of [home, away]) {
        s.replaceChildren(new Option(s === home ? 'Home' : 'Away', ''));
        for (const t of inPool()) s.append(new Option(t.name, t.teamId));
      }
    };
    add.onclick = () => {
      if (!home.value || !away.value || !onDay.value || !time.value) { say('A fixture is a home team, an away team, a day and a time.'); return; }
      send([{ homeTeamId: home.value, awayTeamId: away.value, scheduledAt: instant(onDay.value, time.value),
              ...(pool.value ? { divisionId: pool.value } : {}) }], add);
    };
    one.append(home, make('span', 'v', 'v'), away, onDay, time, add);

    // A whole division.
    const whole = make('div', 'entry-form');
    const first = make('input'); first.type = 'date'; first.min = plan.startsOn; first.max = plan.endsOn;
    const wholeTime = make('input'); wholeTime.type = 'time'; wholeTime.value = '19:30';
    const [twice, twiceL] = check('Home and away', true);
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
    whole.append(label('First round', first), wholeTime, twiceL, draw_up);

    pool.onchange = () => { refill(); preview.replaceChildren(); };
    refill();
    box.append(label('Division', pool),
               make('p', 'quiet', 'One fixture'), one,
               make('p', 'quiet', `Or the whole division as a round robin, inside the season (${day(plan.startsOn)} to ${day(plan.endsOn)})`), whole,
               preview, said);
    if (reads) box.append(pasteList());
    return box;

    /**
     * Paste the league's list (PD-122). The season is usually already typed somewhere — a sheet, an email, last year's
     * page — so the desk takes it as it is written. THRØ reads each line into a row; the rows it is sure of are ticked,
     * the ones in doubt say what to settle, and nothing is added until the person presses the button.
     */
    function pasteList() {
      const wrap = make('div', 'paste');
      wrap.append(make('p', 'quiet', 'Or paste the league’s own list, as it is written — a date on its own line carries down to the fixtures under it.'));
      const area = make('textarea'); area.rows = 6; area.setAttribute('aria-label', 'The fixture list');
      area.placeholder = 'Thursday 8 October\nRiverside A v Grange A 7.30pm\nDolphin v Bell B\n15 Oct - Grange A v Dolphin 8pm';
      const go = make('button', 'primary', 'Read the list');
      const note = make('p', 'note'); note.hidden = true;
      const out = make('div');
      const acts = make('div', 'acts'); acts.append(go);
      wrap.append(area, acts, note, out);
      go.onclick = async () => {
        if (!area.value.trim()) { area.focus(); return; }
        go.disabled = true; note.hidden = true; out.replaceChildren(make('p', 'quiet', 'Reading each line…'));
        try {
          const read = await authorised('POST', `/v1/seasons/${encodeURIComponent(plan.leagueSeasonId)}/fixtures/read`, { text: area.value });
          out.replaceChildren(rowsOf(read));
        } catch (e) { out.replaceChildren(); note.hidden = false; note.textContent = e.message; }
        go.disabled = false;
      };

      function rowsOf(read) {
        const holder = make('div');
        if (!read.rows.length) { holder.append(make('p', 'quiet', 'THRØ found no fixture in that. One to a line: “Riverside A v Grange A 7.30pm”.')); return holder; }
        const usual = make('input'); usual.type = 'time'; usual.value = (read.rows.find(r => r.time) || {}).time ? read.rows.find(r => r.time).time.slice(0, 5) : '19:30';
        usual.setAttribute('aria-label', 'The time for fixtures that state none');
        const needTime = read.rows.some(r => !r.time);
        if (needTime) { const l = make('label', 'spec', 'No time is stated on some lines. Play them at '); l.append(usual); holder.append(l); }
        const list = make('ul', 'rows');
        const made = [];
        for (const r of read.rows) {
          const li = make('li', 'paste-row');
          const tick = make('input'); tick.type = 'checkbox'; tick.checked = !r.doubt || r.doubt === 'time';
          tick.setAttribute('aria-label', `Add ${r.home || 'a team'} v ${r.away || 'a team'}`);
          const homeSel = select(accepted.map(t => [t.teamId, t.name]), 'Home'); const awaySel = select(accepted.map(t => [t.teamId, t.name]), 'Away');
          if (r.homeTeamId) homeSel.value = r.homeTeamId; if (r.awayTeamId) awaySel.value = r.awayTeamId;
          const on = make('input'); on.type = 'date'; on.min = plan.startsOn; on.max = plan.endsOn; if (r.on) on.value = r.on;
          on.setAttribute('aria-label', 'The day');
          const at = make('input'); at.type = 'time'; if (r.time) at.value = r.time.slice(0, 5);
          at.setAttribute('aria-label', 'The time');
          const form = make('div', 'entry-form'); form.append(tick, homeSel, make('span', 'v', 'v'), awaySel, on, at);
          const doubt = { teams: 'check the teams', date: 'check the date', time: null }[r.doubt];
          li.append(make('div', 'row-meta', `“${r.text}”` + (doubt ? ` · ${doubt}` : '')), form);
          list.append(li);
          made.push({ tick, homeSel, awaySel, on, at });
        }
        holder.append(list);
        if (read.skipped.length) holder.append(make('p', 'quiet', `Left out: ${read.skipped.map(s => `“${s.text}” (${s.why})`).join(' · ')}`));
        const add = make('button', 'primary', 'Add the ticked fixtures');
        const told = make('p', 'note'); told.hidden = true;
        add.onclick = async () => {
          const fixtures = [];
          for (const m of made) {
            if (!m.tick.checked) continue;
            const time = m.at.value || usual.value;
            if (!m.homeSel.value || !m.awaySel.value || m.homeSel.value === m.awaySel.value || !m.on.value || !time) {
              told.hidden = false; told.textContent = 'Every ticked line needs two different teams, a day and a time. Untick the ones to leave out.'; return;
            }
            const division = (accepted.find(t => t.teamId === m.homeSel.value) || {}).divisionId;
            fixtures.push({ homeTeamId: m.homeSel.value, awayTeamId: m.awaySel.value, scheduledAt: instant(m.on.value, time), ...(division ? { divisionId: division } : {}) });
          }
          if (!fixtures.length) { told.hidden = false; told.textContent = 'Tick the fixtures to add.'; return; }
          told.hidden = true;
          await send(fixtures, add);
        };
        const foot = make('div', 'acts'); foot.append(add);
        holder.append(foot, told, make('p', 'quiet', 'They are added together or not at all: if one cannot be played, THRØ says which and adds none.'));
        return holder;
      }
      return wrap;
    }
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
    if (!replacing) box.append(otherwise(f, redraw, said));
    return box;
  }

  /**
   * What else can happen to an open fixture (PD-106): it is awarded to one side — a decision with a reason and never
   * a scoreline (ADR-012) — or it is moved to another day. Both fold away behind a word, because most fixtures are
   * played as planned. A move names the row version it read, so two officials moving the same fixture do not
   * silently overwrite each other: the second is told to reload.
   */
  function otherwise(f, redraw, said) {
    const row = make('div', 'row-meta');
    const award = make('button', 'quiet-button', 'Award'); award.setAttribute('aria-expanded', 'false');
    const move = make('button', 'quiet-button', 'Rearrange'); move.setAttribute('aria-expanded', 'false');
    const acts = make('div', 'acts'); acts.append(award, move);
    row.append(acts);
    const wrap = make('div');
    let open = null;
    const shut = () => {
      if (open) { open.remove(); open = null; }
      award.textContent = 'Award'; award.setAttribute('aria-expanded', 'false');
      move.textContent = 'Rearrange'; move.setAttribute('aria-expanded', 'false');
    };
    award.onclick = () => {
      const was = award.getAttribute('aria-expanded') === 'true'; shut(); if (was) return;
      open = awarding(f, redraw); award.textContent = 'Leave it'; award.setAttribute('aria-expanded', 'true'); wrap.append(open);
    };
    move.onclick = () => {
      const was = move.getAttribute('aria-expanded') === 'true'; shut(); if (was) return;
      open = moving(f, redraw); move.textContent = 'Leave it'; move.setAttribute('aria-expanded', 'true'); wrap.append(open);
    };
    wrap.append(row);
    return wrap;
  }

  function awarding(f, redraw) {
    const box = make('div', 'entry');
    box.append(make('p', 'quiet', 'A fixture nobody played goes to one side with a reason, and never a scoreline: the points move, the legs do not.'));
    const form = make('div', 'entry-form');
    const to = make('select'); to.setAttribute('aria-label', 'Which team the fixture is awarded to');
    to.append(new Option(`To ${f.home || 'the home team'}`, f.homeTeamId), new Option(`To ${f.away || 'the away team'}`, f.awayTeamId));
    const why = make('input'); why.type = 'text'; why.placeholder = 'Why — e.g. away side did not turn up';
    why.setAttribute('aria-label', 'Why the fixture is awarded');
    const go = make('button', 'primary', 'Award it');
    const said = make('p', 'note'); said.hidden = true;
    go.onclick = async () => {
      const reason = why.value.trim();
      if (!reason) { said.hidden = false; said.textContent = 'An award says why. A decision with no reason is one nobody can answer for.'; return; }
      go.disabled = true;
      try {
        await authorised('POST', `/v1/fixtures/${encodeURIComponent(f.fixtureId)}/award`, { toTeamId: to.value, reason });
        said.hidden = false; said.textContent = 'Awarded, with the reason on the record.';
        setTimeout(redraw, 900);
      } catch (e) { said.hidden = false; said.textContent = e.message; go.disabled = false; }
    };
    form.append(to, why, go);
    box.append(form, said);
    return box;
  }

  function moving(f, redraw) {
    const box = make('div', 'entry');
    box.append(make('p', 'quiet', 'Moves the fixture to another day and time. The change is recorded against the fixture; nothing about the teams changes.'));
    const form = make('div', 'entry-form');
    const was = new Date(f.scheduledAt);
    const day = make('input'); day.type = 'date'; day.value = was.toISOString().slice(0, 10);
    day.setAttribute('aria-label', 'The new day');
    const time = make('input'); time.type = 'time';
    time.value = `${String(was.getHours()).padStart(2, '0')}:${String(was.getMinutes()).padStart(2, '0')}`;
    time.setAttribute('aria-label', 'The new time');
    const go = make('button', 'primary', 'Move it');
    const said = make('p', 'note'); said.hidden = true;
    go.onclick = async () => {
      if (!day.value || !time.value) { said.hidden = false; said.textContent = 'A rearrangement is a day and a time.'; return; }
      go.disabled = true;
      try {
        const res = await fetch(`${API}/v1/commands`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session.get().accessToken}`, 'X-Thro-Device': deviceId() },
          body: JSON.stringify({ type: 'RearrangeFixture', commandId: crypto.randomUUID(), fixtureId: f.fixtureId,
                                 to: new Date(`${day.value}T${time.value}`).toISOString(), expectedVersion: f.version }),
        });
        const body = await res.json().catch(() => ({}));
        if (res.status === 409) throw new Error('This fixture changed while you were looking at it. Reload, and move the one that is standing now.');
        if (!res.ok) throw new Error(body.error || body.reason || `THRØ answered ${res.status}.`);
        said.hidden = false; said.textContent = 'Moved.';
        setTimeout(redraw, 900);
      } catch (e) { said.hidden = false; said.textContent = e.message; go.disabled = false; }
    };
    form.append(day, time, go);
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

// --- events: a knockout run on THRØ (PD-109) -----------------------------------------------------------------------

/**
 * `events.html` is two pages. With `?event=<id>` it is one event's page — public: what, when, where, how many places,
 * and the first round once drawn — with the organiser's acts on it when the signed-in person is its organiser.
 * Without, it is the organiser's lobby: the events they run, and the form that opens one.
 */
async function mountEvents(where, signInEl) {
  const eventId = new URLSearchParams(location.search).get('event');
  if (eventId) { await mountEvent(where, signInEl, eventId); return; }
  const draw = async () => {
    if (!signInGate(signInEl, where, 'Sign in to run a knockout.', draw)) return;
    let mine;
    try { mine = await authorised('GET', '/v1/me/events'); } catch (e) { fail(where, e, draw); return; }
    const parts = [make('h2', null, 'Events you run')];
    if (!mine.events.length) {
      parts.push(make('p', 'quiet', 'None yet. Open one below.'));
    } else {
      const list = make('ul', 'rows');
      for (const e of mine.events) {
        const li = make('li');
        const link = make('a', 'row-name', e.name);
        link.href = `events.html?event=${encodeURIComponent(e.eventId)}`;
        li.append(link, make('div', 'row-meta', `${when(e.startsAt)} · ${e.state.replace('_', ' ')} · ${e.entries} entered`));
        list.append(li);
      }
      parts.push(list);
    }
    parts.push(eventOpener(draw));
    where.replaceChildren(...parts);
  };
  await draw();
}

/** Opening an edition: a name, a day and time, when the session ends, a venue on THRØ or a label, places, and when entries close. */
function eventOpener(redraw) {
  const box = make('div', 'entry');
  box.append(make('h2', null, 'Open a knockout'));
  const form = make('div', 'entry-form');
  const name = make('input'); name.type = 'text'; name.placeholder = 'Sun Inn Open'; name.maxLength = 80; name.setAttribute('aria-label', 'The event’s name');
  const day = make('input'); day.type = 'date'; day.setAttribute('aria-label', 'The day');
  const start = make('input'); start.type = 'time'; start.value = '11:00'; start.setAttribute('aria-label', 'Starts at');
  const end = make('input'); end.type = 'time'; end.value = '22:00'; end.setAttribute('aria-label', 'The session ends at');
  const venueQ = make('input'); venueQ.type = 'search'; venueQ.placeholder = 'Venue on THRØ (type to find)'; venueQ.setAttribute('aria-label', 'Find the venue');
  const venue = make('select'); venue.append(new Option('No venue on THRØ yet', '')); venue.setAttribute('aria-label', 'The venue');
  const label = make('input'); label.type = 'text'; label.placeholder = 'Or a label: “ask at the bar”'; label.maxLength = 80; label.setAttribute('aria-label', 'Venue label');
  const capacity = make('input'); capacity.type = 'number'; capacity.min = 2; capacity.max = 512; capacity.placeholder = 'Places'; capacity.setAttribute('aria-label', 'Places available');
  const closes = make('input'); closes.type = 'datetime-local'; closes.setAttribute('aria-label', 'Entries close at');
  const access = make('select'); access.append(new Option('Open entry — on the notice on the door', 'open'), new Option('Invitational — you name who plays', 'invitational'));
  access.setAttribute('aria-label', 'Who may enter');
  const kind = make('select'); kind.append(new Option('Singles — players enter', 'player'), new Option('Doubles — pairs enter', 'pair'), new Option('Teams — a team enters', 'team'));
  kind.setAttribute('aria-label', 'Who plays: players, pairs or teams');
  const said = make('p', 'note'); said.hidden = true;
  const say = text => { said.hidden = false; said.textContent = text; };
  let searching;
  venueQ.oninput = () => {
    clearTimeout(searching);
    const q = venueQ.value.trim();
    if (q.length < 2) return;
    searching = setTimeout(async () => {
      try {
        const found = await read(`/v1/venues?q=${encodeURIComponent(q)}`);
        venue.replaceChildren(new Option('No venue on THRØ yet', ''));
        for (const v of found.venues || []) venue.append(new Option(`${v.name}${v.locality ? ` · ${v.locality}` : ''}`, v.venueId));
      } catch (e) { say(e.message); }
    }, 300);
  };
  const open = make('button', 'primary', 'Open it');
  open.onclick = async () => {
    if (!name.value.trim() || !day.value || !start.value || !end.value) { say('An event is a name, a day, a start and a session end.'); return; }
    const at = t => new Date(`${day.value}T${t}`).toISOString();
    open.disabled = true;
    try {
      const made = await authorised('POST', '/v1/events', {
        name: name.value.trim(), startsAt: at(start.value), sessionEndsAt: at(end.value),
        ...(venue.value ? { venueId: venue.value } : {}), ...(label.value.trim() ? { venueLabel: label.value.trim() } : {}),
        ...(capacity.value ? { capacity: Number(capacity.value) } : {}), ...(closes.value ? { entriesCloseAt: new Date(closes.value).toISOString() } : {}),
        access: access.value, entrantKind: kind.value,
      });
      location.search = `?event=${encodeURIComponent(made.eventId)}`;
    } catch (e) { say(e.message); open.disabled = false; }
  };
  form.append(name, day, start, end, venueQ, venue, label, capacity, closes, kind, access, open);
  box.append(form, said, make('p', 'quiet', 'THRØ draws the first round from the entries — seeds apart — and the next from the winners, until the final.'));
  return box;
}

/**
 * The organiser's entrants (PD-113): who is in, checked in or not, each removable before the draw; and an invitation —
 * a player from one of the organiser's own teams' rosters, or by id. On the public page no entrant is named before
 * the draw; this section only exists when the server sent `entrants`, which it does for the organiser alone.
 */
function entrantsSection(e, redraw) {
  const who = e.entrantKind === 'pair' ? 'Pairs' : e.entrantKind === 'team' ? 'Teams' : 'Entered';
  const out = [make('h2', null, `${who} · ${e.entrants.length}`)];
  const list = make('ul', 'rows');
  const before = e.state === 'open' || e.state === 'entries_closed';
  for (const p of e.entrants) {
    const li = make('li');
    const head = make('div', 'row-head');
    head.append(make('div', 'row-name', p.name || 'A player THRØ may not name'),
                make('span', 'quiet', p.kind === 'guest' ? 'walk-up · here' : p.checkedIn ? 'checked in' : 'not yet checked in'));
    const said = make('p', 'note'); said.hidden = true;
    if (before) {
      // The seed, as the draw will honour it: 1 at the top, 2 at the bottom, apart until the final.
      const seed = make('input'); seed.type = 'number'; seed.min = 1; seed.max = 128; seed.value = p.seed || ''; seed.placeholder = 'seed';
      seed.setAttribute('aria-label', `${p.name || 'this entrant'}’s seed`); seed.style.width = '5rem';
      seed.onchange = async () => {
        try { await authorised('POST', `/v1/events/${encodeURIComponent(e.eventId)}/entries/${encodeURIComponent(p.playerId)}/seed`, { seed: seed.value ? Number(seed.value) : null }); redraw(); }
        catch (err) { said.hidden = false; said.textContent = err.message; seed.value = p.seed || ''; }
      };
      const remove = make('button', 'quiet-button', 'Remove');
      remove.onclick = async () => {
        remove.disabled = true;
        try { await authorised('POST', `/v1/events/${encodeURIComponent(e.eventId)}/entries/${encodeURIComponent(p.playerId)}/remove`, {}); redraw(); }
        catch (err) { said.hidden = false; said.textContent = err.message; remove.disabled = false; }
      };
      const acts = make('div', 'acts'); acts.append(seed, remove);
      li.append(head, acts, said);
    } else {
      if (p.seed) head.append(make('span', 'quiet', `seed ${p.seed}`));
      li.append(head, said);
    }
    list.append(li);
  }
  out.push(list);
  if (before) {
    const box = make('div', 'entry');
    const verb = e.access === 'invitational' ? 'Invite' : 'Enter';
    box.append(make('h2', null, e.entrantKind === 'pair' ? `${verb} a pair` : e.entrantKind === 'team' ? `${verb} a team` : `${verb} a player`));
    const form = make('div', 'entry-form');
    const said = make('p', 'note'); said.hidden = true;
    const pick = make('select'); pick.setAttribute('aria-label', e.entrantKind === 'team' ? 'One of your teams' : 'A player from one of your teams');
    pick.append(new Option(e.entrantKind === 'team' ? 'Your teams…' : 'From your teams…', ''));
    const pick2 = make('select'); pick2.setAttribute('aria-label', 'The partner'); pick2.append(new Option('…and their partner', ''));
    const byId = make('input'); byId.type = 'text'; byId.placeholder = e.entrantKind === 'team' ? 'Or a team id' : 'Or a player id'; byId.maxLength = 36;
    byId.setAttribute('aria-label', e.entrantKind === 'team' ? 'A team id' : 'A player id');
    (async () => {
      try {
        const mine = await authorised('GET', '/v1/me/teams');
        for (const t of mine.teams || []) {
          if (e.entrantKind === 'team') { pick.append(new Option(t.name, t.teamId)); continue; }
          const front = await read(`/v1/teams/${encodeURIComponent(t.teamId)}`);
          for (const m of front.roster || []) if (m.playerId && !e.entrants.some(x => x.playerId === m.playerId)) {
            pick.append(new Option(`${m.name || 'A player'} · ${t.name}`, m.playerId));
            pick2.append(new Option(`${m.name || 'A player'} · ${t.name}`, m.playerId));
          }
        }
      } catch (err) { said.hidden = false; said.textContent = err.message; }
    })();
    const add = make('button', 'primary', verb);
    add.onclick = async () => {
      const id = pick.value || byId.value.trim();
      if (!id) { said.hidden = false; said.textContent = e.entrantKind === 'team' ? 'Pick a team, or paste its id.' : 'Pick a player, or paste their id.'; return; }
      const body = e.entrantKind === 'team' ? { teamId: id }
        : e.entrantKind === 'pair' ? (pick2.value ? { playerIds: [id, pick2.value] } : null)
        : { playerId: id };
      if (!body) { said.hidden = false; said.textContent = 'A pair is two players: pick the partner too.'; return; }
      add.disabled = true;
      try { await authorised('POST', `/v1/events/${encodeURIComponent(e.eventId)}/entries`, body); redraw(); }
      catch (err) { said.hidden = false; said.textContent = err.message; add.disabled = false; }
    };
    form.append(pick);
    if (e.entrantKind === 'pair') form.append(pick2);
    form.append(byId, add);
    box.append(form, said);
    out.push(box);
    // PD-124: a walk-up — somebody in the pub with no account, added by name. PD-130: on a pairs night, a pair with a
    // walk-up in it: two names, or a name and a partner who is on THRØ.
    if (e.entrantKind === 'player' || e.entrantKind === 'pair') {
      const pairs = e.entrantKind === 'pair';
      const walk = make('div', 'entry');
      walk.append(make('h2', null, pairs ? 'Add a pair with a walk-up' : 'Add a walk-up'),
                  make('p', 'quiet', pairs
                    ? 'Somebody here tonight with no THRØ account, and who they are throwing with: another walk-up, or somebody on THRØ. The pair goes in the draw like any other, and you decide its ties by hand.'
                    : 'Somebody here tonight with no THRØ account. They go in the draw like anybody else, and you decide their ties by hand.'));
      const wform = make('div', 'entry-form');
      const input = (placeholder, label) => {
        const i = make('input'); i.type = 'text'; i.maxLength = 60; i.placeholder = placeholder; i.setAttribute('aria-label', label);
        i.style.flex = '1 1 14rem'; i.autocomplete = 'off'; return i;
      };
      const name = input('Their name, as it goes on the board', 'The walk-up’s name');
      const name2 = input('Their partner’s name', 'The partner’s name, if they are a walk-up too');
      const onThro = make('select'); onThro.setAttribute('aria-label', 'Or a partner who is on THRØ'); onThro.append(new Option('…or a partner on THRØ', ''));
      if (pairs) (async () => {
        try {
          const mine = await authorised('GET', '/v1/me/teams');
          for (const t of mine.teams || []) {
            const front = await read(`/v1/teams/${encodeURIComponent(t.teamId)}`);
            for (const m of front.roster || []) if (m.playerId) onThro.append(new Option(`${m.name || 'A player'} · ${t.name}`, m.playerId));
          }
        } catch (err) { /* the two names still work */ }
      })();
      const [namedBox, namedLabel] = check(pairs ? 'Whoever is named here is 18 or over, and happy to be named on the public draw'
                                                 : 'They are 18 or over, and happy to be named on the public draw');
      const addWalk = make('button', 'primary', pairs ? 'Add the pair' : 'Add them');
      const told = make('p', 'note'); told.hidden = true;
      const send = async () => {
        if (!name.value.trim()) { name.focus(); return; }
        let body = { name: name.value.trim(), mayBeNamed: namedBox.checked };
        if (pairs) {
          if (onThro.value) body = { name: name.value.trim(), partnerId: onThro.value, mayBeNamed: namedBox.checked };
          else if (name2.value.trim()) body = { names: [name.value.trim(), name2.value.trim()], mayBeNamed: namedBox.checked };
          else { told.hidden = false; told.textContent = 'A pair is two: their partner’s name, or a partner on THRØ.'; name2.focus(); return; }
        }
        addWalk.disabled = true;
        try { await authorised('POST', `/v1/events/${encodeURIComponent(e.eventId)}/guests`, body); redraw(); }
        catch (err) { told.hidden = false; told.textContent = err.message; addWalk.disabled = false; }
      };
      addWalk.onclick = send;
      for (const i of [name, name2]) i.addEventListener('keydown', ev => { if (ev.key === 'Enter') { ev.preventDefault(); send(); } });
      // One partner or the other: choosing somebody on THRØ clears the typed name, and typing clears the choice.
      onThro.onchange = () => { if (onThro.value) name2.value = ''; };
      name2.oninput = () => { if (name2.value) onThro.value = ''; };
      wform.append(name);
      if (pairs) wform.append(name2, onThro);
      const wacts = make('div', 'acts'); wacts.append(addWalk);
      walk.append(wform, namedLabel, wacts, told,
                  make('p', 'quiet', 'Without that tick only you see the name; the public draw says “A guest”. Thirty days after the night, THRØ forgets a walk-up’s name either way.'));
      out.push(walk);
    }
    // The boards: named once, then each tie is sent to one.
    const boards = make('div', 'entry');
    boards.append(make('h2', null, 'Boards'), make('p', 'quiet', e.boards.length ? `${e.boards.join(', ')}.` : 'Name the boards and each tie can be sent to one.'));
    const bform = make('div', 'entry-form');
    const labels = make('input'); labels.type = 'text'; labels.placeholder = 'Board 1, Board 2, Back room'; labels.maxLength = 200; labels.setAttribute('aria-label', 'Board names, separated by commas');
    const bsaid = make('p', 'note'); bsaid.hidden = true;
    const name = make('button', 'quiet-button', 'Name them');
    name.onclick = async () => {
      name.disabled = true;
      try { await authorised('POST', `/v1/events/${encodeURIComponent(e.eventId)}/boards`, { labels: labels.value.split(',').map(x => x.trim()).filter(Boolean) }); redraw(); }
      catch (err) { bsaid.hidden = false; bsaid.textContent = err.message; name.disabled = false; }
    };
    bform.append(labels, name);
    boards.append(bform, bsaid);
    out.push(boards);
  }
  return out;
}

async function mountEvent(where, signInEl, eventId) {
  const draw = async () => {
    // The page reads without a session; the organiser's acts appear with one.
    let e;
    try { e = session.get() ? await authorised('GET', `/v1/events/${encodeURIComponent(eventId)}`) : await read(`/v1/events/${encodeURIComponent(eventId)}`); }
    catch (err) { fail(where, err, draw); return; }
    signInEl.replaceChildren();
    if (session.get()) {
      const out = make('button', 'quiet-button', 'Sign out'); out.onclick = () => { signOut(); draw(); }; signInEl.append(out);
    }
    const whereAt = e.venue ? `${e.venue}${e.locality ? `, ${e.locality}` : ''}` : (e.venueLabel || 'venue to be announced');
    const title = document.getElementById('title'); if (title) title.textContent = e.name;
    const eyebrow = document.getElementById('eyebrow'); if (eyebrow) eyebrow.textContent = `${when(e.startsAt)} · ${whereAt}`;
    document.title = `${e.name} — THRØ`;
    const places = e.capacity == null ? 'places not stated' : (e.spotsRemaining === 0 ? 'full' : `${e.spotsRemaining} of ${e.capacity} places left`);
    const parts = [
      make('h2', null, 'The day'),
      make('p', 'quiet', `${when(e.startsAt)} · ${whereAt} · ${e.entries} entered · ${places} · ${e.state.replace('_', ' ')}`
        + (e.entriesCloseAt ? ` · entries close ${when(e.entriesCloseAt)}` : '')),
    ];
    if (e.you) {
      parts.push(make('p', 'quiet', e.you.entered ? (e.you.checkedIn ? 'You are entered and checked in.' : 'You are entered. Check in from the app on the day.')
        : (e.access === 'open' ? 'Entering is done in the app: open this night there, below.' : 'Invitational: the organiser names who plays.')));
    }
    // One address for the night (PD-127). Whoever runs it is given it to post; everybody else is given the way into the app,
    // because entering, checking in and scoring are done there.
    const address = `${location.origin}/event/${encodeURIComponent(eventId)}`;
    if (e.entrants) {
      const share = make('div', 'entry');
      const line = make('p', 'address', address.replace(/^https?:\/\//, ''));
      const copy = make('button', 'quiet-button', 'Copy the address');
      copy.onclick = async () => { try { await navigator.clipboard.writeText(address); copy.textContent = 'Copied'; } catch (err) { copy.textContent = 'Select it above and copy'; } };
      share.append(make('h2', null, 'This night\u2019s address'), line, copy,
        make('p', 'quiet', 'Post it in the pub\u2019s group chat. On a phone with THRØ it opens the night in the app, where players enter; on anything else it is this page.'));
      parts.push(share);
    } else if (e.state === 'open' || e.state === 'entries_closed' || e.state === 'drawn' || e.state === 'in_progress') {
      parts.push(openInApp('event', eventId, {
        phone: 'THRØ is a darts app for iPhone. In it you enter this night, check in on the day and find your tie in the draw.',
        screen: 'Point your phone\u2019s camera here. With THRØ on it, this night opens in the app: enter, check in on the day, and find your tie in the draw.',
      }));
    }
    if (e.entrants) parts.push(...entrantsSection(e, draw));
    if (e.draw.length) {
      // The bracket, round by round. A decided tie says how; a bye says it is one; the final says who won the day.
      const rounds = [...new Set(e.draw.map(t => t.round))].sort((a, b) => a - b);
      const last = rounds[rounds.length - 1];
      const roundName = (r, ties) => ties.length === 1 && e.state === 'complete' ? 'Final' : (ties.length === 1 ? 'Final' : ties.length === 2 ? 'Semi-finals' : ties.length === 4 ? 'Quarter-finals' : `Round ${r}`);
      if (e.winnerId) {
        const champion = e.draw.filter(t => t.round === last).map(t => t.winnerId === t.homeId ? t.home : t.away)[0];
        parts.push(make('p', 'wordmark', `${champion || 'A player'} won it`));
      }
      for (const r of rounds) {
        const ties = e.draw.filter(t => t.round === r);
        parts.push(make('h2', null, roundName(r, ties)));
        const list = make('ul', 'rows');
        for (const t of ties) {
          const li = make('li');
          const head = make('div', 'row-head');
          const name = who => who || 'A player';
          const line = t.isBye ? `${name(t.home)} — bye` : `${name(t.home)} v ${name(t.away)}`;
          const standing = t.isBye ? 'through without a game'
            : t.winnerId ? `${t.winnerId === t.homeId ? name(t.home) : name(t.away)} won · ${t.outcome === 'played' ? 'scored on THRØ' : t.outcome}${t.note ? ` — ${t.note}` : ''}`
            : (t.board ? `${t.board} · to be played` : 'to be played');
          head.append(make('div', 'row-name', line), make('span', 'quiet', standing));
          li.append(head);
          // The organiser sends an unplayed tie to a board it named.
          if (session.get() && e.entrants && e.boards && e.boards.length && !t.isBye && !t.winnerId) {
            const board = make('select'); board.setAttribute('aria-label', 'Which board');
            board.append(new Option(t.board ? `On ${t.board}` : 'Send to a board…', ''));
            for (const b of e.boards) if (b !== t.board) board.append(new Option(b, b));
            board.onchange = async () => {
              if (!board.value) return;
              try { await authorised('POST', `/v1/events/${encodeURIComponent(eventId)}/ties/${encodeURIComponent(t.tieId)}/board`, { label: board.value }); draw(); }
              catch (err) { const said = make('p', 'note', err.message); li.append(said); }
            };
            const acts = make('div', 'acts'); acts.append(board); li.append(acts);
          }
          // The organiser decides an undecided tie here: a walkover or an award, with a reason. A played tie is
          // cited from the app by somebody who played it; the winner is the record's, never typed here.
          if (session.get() && !t.isBye && !t.winnerId && (e.state === 'drawn' || e.state === 'in_progress')) {
            const form = make('div', 'entry-form'); form.hidden = true;
            const winner = make('select'); winner.append(new Option('Who goes through', ''), new Option(name(t.home), t.homeId), new Option(name(t.away), t.awayId));
            winner.setAttribute('aria-label', 'Who goes through');
            const how = make('select'); how.append(new Option('walkover', 'walkover'), new Option('awarded', 'awarded'));
            how.setAttribute('aria-label', 'How it was decided');
            const why = make('input'); why.type = 'text'; why.placeholder = 'Why, e.g. did not arrive'; why.maxLength = 280; why.setAttribute('aria-label', 'Why');
            const said = make('p', 'note'); said.hidden = true;
            const reveal = make('button', 'quiet-button', 'Decide it by hand'); reveal.setAttribute('aria-expanded', 'false');
            reveal.onclick = () => { form.hidden = !form.hidden; reveal.setAttribute('aria-expanded', String(!form.hidden)); reveal.textContent = form.hidden ? 'Decide it by hand' : 'Leave it to the board'; };
            const decide = make('button', 'primary', 'Record it');
            decide.onclick = async () => {
              if (!winner.value || !why.value.trim()) { said.hidden = false; said.textContent = 'Say who goes through and why.'; return; }
              decide.disabled = true;
              try { await authorised('POST', `/v1/events/${encodeURIComponent(eventId)}/ties/${encodeURIComponent(t.tieId)}/result`, { winnerId: winner.value, outcome: how.value, note: why.value.trim() }); draw(); }
              catch (err) { said.hidden = false; said.textContent = err.message; decide.disabled = false; }
            };
            form.append(winner, how, why, decide);
            const acts = make('div', 'acts'); acts.append(reveal);
            li.append(acts, form, said);
          }
          list.append(li);
        }
        parts.push(list);
      }
    }
    // The organiser's acts: shown to a signed-in person and refused by the server for anybody who is not the organiser.
    if (session.get() && (e.state === 'open' || e.state === 'entries_closed' || e.state === 'drawn' || e.state === 'in_progress')) {
      const box = make('div', 'entry');
      const said = make('p', 'note'); said.hidden = true;
      const act = async (path, button) => {
        button.disabled = true;
        try { await authorised('POST', `/v1/events/${encodeURIComponent(eventId)}/${path}`, {}); draw(); }
        catch (err) { said.hidden = false; said.textContent = err.message; button.disabled = false; }
      };
      const form = make('div', 'entry-form');
      if (e.state === 'open') { const close = make('button', 'quiet-button', 'Close entries'); close.onclick = () => act('close', close); form.append(close); }
      if (e.state === 'open' || e.state === 'entries_closed') {
        const drawIt = make('button', 'primary', 'Make the draw');
        drawIt.onclick = () => { if (drawIt.textContent !== 'Draw it — this cannot be undone') { drawIt.textContent = 'Draw it — this cannot be undone'; return; } act('draw', drawIt); };
        form.append(drawIt);
        box.append(make('h2', null, 'As the organiser'), form, said,
                   make('p', 'quiet', 'The draw is made once, from the entries as they stand: byes to the highest seeds, the rest paired. A bye is not a win.'));
      } else {
        const advance = make('button', 'primary', 'Draw the next round');
        advance.onclick = () => act('advance', advance);
        form.append(advance);
        box.append(make('h2', null, 'As the organiser'), form, said,
                   make('p', 'quiet', 'Once every tie in the round is decided — scored on THRØ and named from the app, or recorded above — the winners are paired in order. A round of one decided tie ends the event.'));
      }
      parts.push(box);
    } else if (!session.get()) {
      // Folded, and made only when opened (PD-127): this page is what gets shared, and a sign-in code started for every
      // reader who will never use one is a request to the server per visitor and a wall between a player and the night.
      const fold = make('details', 'fold');
      fold.append(make('summary', null, 'Run this night? Sign in'));
      fold.addEventListener('toggle', () => { if (fold.open && fold.children.length === 1) fold.append(signInPanel(draw)); });
      parts.push(fold);
    }
    where.replaceChildren(...parts);
  };
  await draw();
}

/**
 * The site's places, on every page, in the header: what a person can do here. The current page is marked, the sign-in
 * state is said, and nothing is a footnote. The footer keeps the legal words.
 */
function mountNav(where) {
  const here = location.pathname.split('/').pop() || 'index.html';
  const places = [['index.html', 'Leagues'], ['organiser.html', 'Run a league'], ['events.html', 'Knockouts'], ['tv.html', 'Pub screen']];
  const nav = make('nav', 'nav'); nav.setAttribute('aria-label', 'THRØ');
  for (const [href, label] of places) {
    const a = make('a', here === href ? 'here' : null, label); a.href = href;
    if (here === href) a.setAttribute('aria-current', 'page');
    nav.append(a);
  }
  const state = make('span', 'nav-state', session.get() ? 'Signed in' : '');
  nav.append(state);
  where.replaceChildren(nav);
}

window.THRO = { mountNav, mountLeagues, mountLeague, mountTeam, mountEvent, idFromPath, openInApp, mountTable, mountFixtures, mountOrganiser, mountModeration, mountEvents, mountNotice, mountNoticeBanner, signInWithPasskey, whoAmI, signOut, session, authorised, passkeysPossible };
