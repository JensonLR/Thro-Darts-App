// The board on a pub television, in whatever browser the television has (PD-090).
//
// **Why a web page is the right answer and not a consolation prize.** The alternatives all put something
// between the league and the screen: a cable (an adapter, and a phone tied up all night), AirPlay (a phone
// tied up all night, and pub guest Wi-Fi routinely isolates clients so discovery dies), or an Apple TV
// (£150). A URL costs nothing, is typed once, and needs **no phone in the room** — which is the actual
// requirement, because the person who set it up goes home at eleven and the screen is still on at closing.
//
// Every route this reads is public and unauthenticated, which is what makes it possible at all: there is
// no session to establish, no token to store on a television that a hundred strangers walk past, and
// nothing to sign out of. That is a property of PD-088's design rather than a convenience discovered here.
//
// **No framework and no build step**, the same bargain the rest of `apps/web` makes. It is a rotation, a
// fetch and some DOM.

const API = new URLSearchParams(location.search).get('api') || window.THRO_API || '';

// How often each thing is asked for again. A league table changes on the night it changes; a leg changes
// while somebody is looking at it. The same two numbers as the app (PD-088), for the same reason.
const REFRESH = 120_000;
const LIVE_REFRESH = 10_000;
// How long one panel holds before the next. Long enough to read a table twice from six metres.
const DWELL = 20_000;
// A wall says how old it is, and stops asserting a table after this long without an answer.
const STALE = 15 * 60_000;

const TABLE_ROWS = 12;
const FIXTURE_ROWS = 8;
const LIVE_ROWS = 4;
const RECENT_RESULTS = 16;

const REMEMBERED = 'thro.wall.season';

const state = { standings: null, fixtures: null, live: [], heardAt: null, trouble: null, started: Date.now() };

const el = (tag, cls, text) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text !== undefined) n.textContent = text;
  return n;
};

async function read(path) {
  const res = await fetch(`${API}${path}`, { headers: { Accept: 'application/json' } });
  if (!res.ok) {
    const e = new Error(`THRØ answered ${res.status}`);
    e.status = res.status;
    throw e;
  }
  return res.json();
}

// --- what is on the screen ----------------------------------------------------------------------

function paginate(items, per) {
  const out = [];
  for (let i = 0; i < items.length; i += per) out.push(items.slice(i, i + per));
  return out;
}

/**
 * Every panel with something on it, then the live pages woven between them.
 *
 * The order and the interleave are the app's (PD-079, PD-088) and are repeated here rather than shared,
 * because there is no way to share code between Swift and a page with no build step. `wall.test.js` holds
 * the same properties the Swift tests hold, so the two cannot drift silently.
 */
function panels() {
  const out = [];
  for (const division of state.standings?.divisions ?? []) {
    if (!division.rows?.length) continue;
    const pages = paginate(division.rows, TABLE_ROWS);
    pages.forEach((rows, i) => out.push({ kind: 'table', division: division.name, page: i + 1, of: pages.length, rows }));
  }
  const toPlay = (state.fixtures?.fixtures ?? []).filter(f => !f.decided);
  paginate(toPlay, FIXTURE_ROWS).forEach((rows, i, all) =>
    out.push({ kind: 'toPlay', page: i + 1, of: all.length, rows }));
  const done = (state.fixtures?.fixtures ?? []).filter(f => f.decided).slice(0, RECENT_RESULTS);
  paginate(done, FIXTURE_ROWS).forEach((rows, i, all) =>
    out.push({ kind: 'results', page: i + 1, of: all.length, rows }));

  const livePages = paginate(state.live, LIVE_ROWS)
    .map((games, i, all) => ({ kind: 'live', page: i + 1, of: all.length, games }));
  return interleave(livePages, out);
}

/** Live first and again between each of the others, so a game is never more than one panel away. */
function interleave(live, rest) {
  if (!live.length) return rest;
  if (!rest.length) return live;
  const out = [];
  let next = 0;
  for (const panel of rest) {
    out.push(live[next % live.length]);
    next += 1;
    out.push(panel);
  }
  while (next < live.length) out.push(live[next++]);
  return out;
}

function showing(all, now) {
  if (!all.length) return null;
  return all[Math.floor(Math.max(0, now - state.started) / DWELL) % all.length];
}

// --- the words ----------------------------------------------------------------------------------

/**
 * One side of a live game: the player where THRØ may name them, else the team they play for.
 *
 * **The server omits the key for a player who has not agreed** (PD-088), so a missing name is the ordinary
 * case and not an error. The fallback is their team, which is published anyway — a person who has not
 * said yes should not be the one row on a pub wall that looks redacted.
 */
const side = (name, team) => name || team || 'Not named';

const sides = f => `${f.home ?? 'Not named'} v ${f.away ?? 'Not named'}`;

function outcome(f) {
  const d = f.decided;
  if (!d) return '';
  if (d.kind === 'awarded' || d.kind === 'walkover') {
    return d.awardedToHome === null || d.awardedToHome === undefined ? 'Awarded'
      : `Awarded to ${d.awardedToHome ? f.home ?? 'the home side' : f.away ?? 'the away side'}`;
  }
  return d.legsHome === null || d.legsHome === undefined ? 'Played' : `${d.legsHome}–${d.legsAway}`;
}

const day = iso => new Date(iso).toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' });

function heard(now) {
  if (!state.heardAt) return 'Waiting for THRØ';
  const mins = Math.floor((now - state.heardAt) / 60_000);
  if (mins < 1) return 'Just now';
  return mins === 1 ? '1 minute ago' : `${mins} minutes ago`;
}

// --- drawing ------------------------------------------------------------------------------------

function drawTable(panel) {
  const wrap = el('div', 'panel');
  wrap.append(head(panel.division, panel.page, panel.of));
  const table = el('table', 'wall-table');
  for (const row of panel.rows) {
    const tr = el('tr');
    tr.append(el('td', 'pos', String(row.position)));
    tr.append(el('td', 'team', row.name));
    tr.append(el('td', 'num', String(row.played)));
    tr.append(el('td', 'num', String(row.won)));
    tr.append(el('td', 'num', row.legDifference > 0 ? `+${row.legDifference}` : String(row.legDifference)));
    tr.append(el('td', 'points', String(row.points)));
    table.append(tr);
  }
  wrap.append(table);
  if (state.standings?.rules?.says) wrap.append(el('p', 'foot', state.standings.rules.says));
  return wrap;
}

function drawFixtures(panel, title) {
  const wrap = el('div', 'panel');
  wrap.append(head(title, panel.page, panel.of));
  const table = el('table', 'wall-table');
  for (const f of panel.rows) {
    const tr = el('tr');
    tr.append(el('td', 'team', sides(f)));
    tr.append(el('td', 'aside', panel.kind === 'results' ? outcome(f) : (f.venue ?? '')));
    tr.append(el('td', 'aside', day(f.scheduledAt)));
    table.append(tr);
  }
  wrap.append(table);
  return wrap;
}

function drawLive(panel) {
  const wrap = el('div', 'panel');
  wrap.append(head('Playing now', panel.page, panel.of));
  const games = el('div', 'games');
  for (const g of panel.games) {
    const row = el('div', 'game');
    row.append(drawSide(g.homeName, g.homeTeam, g.homeRemaining, g.thrower === 'home', 'left'));
    const middle = el('div', 'legs');
    middle.append(el('div', 'legs-score', `${g.homeLegs}–${g.awayLegs}`));
    middle.append(el('div', 'legs-label', 'LEGS'));
    row.append(middle);
    row.append(drawSide(g.awayName, g.awayTeam, g.awayRemaining, g.thrower === 'away', 'right'));
    games.append(row);
  }
  wrap.append(games);
  // Said once, at the foot, and only when the whole page is teams: beside a name it would read as an
  // explanation of that person.
  if (panel.games.length && panel.games.every(g => !g.homeName && !g.awayName)) {
    wrap.append(el('p', 'foot', 'Players are named here once they have said they are happy to be.'));
  }
  return wrap;
}

function drawSide(name, team, remaining, throwing, align) {
  const box = el('div', `side ${align}`);
  box.append(el('div', 'side-name', side(name, team)));
  // Whose throw it is, said as brightness rather than a word: from six metres the question is who is on,
  // and the answer wants to be readable without reading.
  box.append(el('div', `side-score${throwing ? ' throwing' : ''}`, String(remaining)));
  return box;
}

function head(title, page, of) {
  const h = el('div', 'panel-head');
  h.append(el('h2', null, title));
  if (of > 1) h.append(el('span', 'page', `${page} of ${of}`));
  return h;
}

function draw() {
  const now = Date.now();
  const root = document.getElementById('wall');
  const all = panels();
  const panel = showing(all, now);

  // Blank rather than the brand's name: the mark is already in the corner, and a heading reading
  // "THRØ" over a board that says THRØ is the app talking about itself on somebody's wall.
  document.getElementById('league').textContent = state.standings?.league ?? '';
  const stale = state.heardAt && now - state.heardAt > STALE;
  const foot = document.getElementById('foot');
  foot.textContent = state.trouble ? `${heard(now)} · ${state.trouble}` : heard(now);
  foot.className = state.trouble || stale ? 'trouble' : '';

  const next = panel ? panel.kind + (panel.division ?? '') + panel.page : 'nothing';
  if (root.dataset.showing === next && !panel?.kind.startsWith('live')) return;
  root.dataset.showing = next;
  root.replaceChildren();

  if (!panel) {
    const wrap = el('div', 'panel');
    wrap.append(el('h2', null, 'Nothing to show yet'));
    wrap.append(el('p', 'saying', 'When this league has a table or a fixture list, it appears here.'));
    root.append(wrap);
    return;
  }
  if (panel.kind === 'table') root.append(drawTable(panel));
  else if (panel.kind === 'live') root.append(drawLive(panel));
  else root.append(drawFixtures(panel, panel.kind === 'toPlay' ? 'Still to play' : 'Results'));
}

// --- reading ------------------------------------------------------------------------------------

async function readSeason(season) {
  try {
    const [standings, fixtures] = await Promise.all([
      read(`/v1/seasons/${season}/standings`),
      read(`/v1/seasons/${season}/fixtures`),
    ]);
    state.standings = standings;
    state.fixtures = fixtures;
    state.heardAt = Date.now();
    state.trouble = null;
  } catch (e) {
    // What is on screen stays on screen. A dropped request is not news that the league has no table,
    // and blanking a wall on a flaky pub connection turns one bad minute into an empty evening.
    state.trouble = e.message;
  }
}

async function readLive(season) {
  try {
    state.live = (await read(`/v1/seasons/${season}/live`)).games ?? [];
    state.heardAt = Date.now();
    state.trouble = null;
  } catch (e) {
    // **A 404 is a server without the route, not a fault.** This page is a URL, so it will be pointed
    // at servers of every vintage — a venue's bookmark outlives a deployment. An older THRØ has no
    // live route, which means there are no live games to show and nothing is wrong; saying "404" on a
    // pub wall all evening would be the newer page complaining about the older server, in front of the
    // customers. Anything else leaves the last games up and says when they were last heard.
    if (e.status === 404) { state.live = []; return; }
    state.trouble = e.message;
  }
}

/**
 * Keep the television awake.
 *
 * A browser on a smart TV will dim or screensaver over the board, and the whole point of this page is
 * that nobody is in the room to touch it. The lock is re-taken on visibility change because the browser
 * drops it whenever the page is backgrounded. Not supported everywhere, and a failure is silent by
 * design: a board that works and dims is better than one that refuses to start.
 */
async function stayAwake() {
  if (!('wakeLock' in navigator)) return;
  const take = async () => { try { await navigator.wakeLock.request('screen'); } catch { /* no lock, still a board */ } };
  document.addEventListener('visibilitychange', () => { if (!document.hidden) take(); });
  await take();
}

async function mountWall(season) {
  document.body.classList.add('wall-on');
  localStorage.setItem(REMEMBERED, season);
  stayAwake();
  draw();
  setInterval(draw, 1000);
  (async function tableLoop() {
    for (;;) { await readSeason(season); draw(); await new Promise(r => setTimeout(r, REFRESH)); }
  })();
  (async function liveLoop() {
    for (;;) { await readLive(season); draw(); await new Promise(r => setTimeout(r, LIVE_REFRESH)); }
  })();
}

/** Which league this screen is for, asked once and remembered. */
async function mountChooser(root) {
  root.replaceChildren(el('p', 'saying', 'Reading the leagues…'));
  let leagues;
  try {
    leagues = (await read('/v1/leagues')).leagues ?? [];
  } catch (e) {
    // A television has no keyboard and usually no reachable reload (PD-148). Left as a sentence, this was
    // the end of the screen: a landlord watching a green rectangle with no way to ask again short of
    // finding the browser's own controls on an unfamiliar remote. So it says it, offers a button a remote
    // can reach, and keeps asking on its own — the board already runs two refresh loops, and a screen
    // whose wifi comes back at closing time should be showing the league by opening time.
    const said = el('p', 'saying', `THRØ could not be reached. ${e.message}`);
    const again = el('button', 'choice');
    again.append(el('span', 'choice-name', 'Try again'));
    again.addEventListener('click', () => mountChooser(root));
    root.replaceChildren(said, again);
    again.focus();
    clearTimeout(mountChooser.retry);
    mountChooser.retry = setTimeout(() => mountChooser(root), 30000);
    return;
  }
  clearTimeout(mountChooser.retry);
  const choosable = leagues.filter(l => l.seasons?.length);
  root.replaceChildren();
  root.append(el('h2', null, 'Which league is this screen for?'));
  root.append(el('p', 'saying', 'Pick it once. This screen shows that league from then on, and remembers it '
    + 'if the television is switched off. To change it later, open this page with ?season= and nothing after it.'));
  if (!choosable.length) {
    // Nothing to pick is not nothing to do: the first league to publish a season should appear here
    // without anybody touching the television (PD-148).
    root.append(el('p', 'saying', 'No league has published a season yet. There is nothing a screen could show.'));
    root.append(el('p', 'saying', 'This screen keeps looking. Leave it on.'));
    clearTimeout(mountChooser.retry);
    mountChooser.retry = setTimeout(() => mountChooser(root), 300000);
    return;
  }
  const list = el('div', 'choices');
  for (const league of choosable) {
    const season = league.seasons.find(s => s.current) ?? league.seasons[0];
    const b = el('button', 'choice');
    b.append(el('span', 'choice-name', league.name));
    b.append(el('span', 'choice-season', season.label ?? ''));
    b.addEventListener('click', () => {
      // The season goes in the URL as well as in storage, so the landlord can write the finished address
      // on a beer mat and type it straight in next time, on this television or another.
      history.replaceState(null, '', `?season=${season.leagueSeasonId}`);
      start();
    });
    list.append(b);
  }
  root.append(list);
}

function start() {
  // `?season=` with nothing after it forgets the remembered league and asks again (PD-148). The chooser
  // says so, and a sentence that says a thing has to be a thing: without this the empty value is falsy,
  // the remembered season wins, and the screen a landlord is trying to re-point stays where it was.
  const params = new URLSearchParams(location.search);
  const named = params.get('season');
  if (named === '') localStorage.removeItem(REMEMBERED);
  const asked = named || (named === '' ? null : localStorage.getItem(REMEMBERED));
  const root = document.getElementById('wall');
  if (asked) return mountWall(asked);
  document.body.classList.remove('wall-on');
  mountChooser(root);
}

window.THRO_WALL = { panels, interleave, side, sides, outcome, heard, state, paginate };
if (typeof document !== 'undefined' && document.getElementById('wall')) start();
