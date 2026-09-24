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
// A game in play is a score that changes every visit, so it goes stale in a minute rather than a quarter of an hour.
// Past this without an answer from the live read, "Playing now" is taken down rather than left up with old scores:
// a leg that finished twenty minutes ago, still on the wall as though it were being thrown, is worse than no board.
// Long enough that one dropped request among the ten-second reads does not make the games blink off and on.
const LIVE_STALE = 45_000;
// How long a read is waited for. A request left hanging on a pub's Wi-Fi would stop its loop for good — the loop
// awaits it — and the wall would never ask again.
const PATIENCE = 10_000;

// The most rows a page holds. What a page actually holds is measured on the screen it is on (see fit): twelve rows
// of a table at the sizes below are taller than a 16:9 television, and the bottom four were cut off by the edge of
// the screen, on every television, with nothing to say they were there.
const TABLE_ROWS = 12;
const FIXTURE_ROWS = 8;
const LIVE_ROWS = 4;
const RECENT_RESULTS = 16;

const REMEMBERED = 'thro.wall.season';

// Two feeds, each with its own last answer. They shared one "last heard" and one fault, so a live read that
// succeeded every ten seconds cleared the error of a table read that had been failing for an hour, and the wall
// said "Just now" over a table nobody had fetched since the first darts.
const state = {
  standings: null, fixtures: null, live: [], started: Date.now(),
  table: { at: null, trouble: null, version: 0 },
  games: { at: null, trouble: null, version: 0 },
};

const el = (tag, cls, text) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text !== undefined) n.textContent = text;
  return n;
};

async function read(path) {
  const signal = typeof AbortSignal !== 'undefined' && AbortSignal.timeout ? AbortSignal.timeout(PATIENCE) : undefined;
  let res;
  try {
    res = await fetch(`${API}${path}`, { headers: { Accept: 'application/json' }, ...(signal ? { signal } : {}) });
  } catch (e) {
    if (e && (e.name === 'TimeoutError' || e.name === 'AbortError')) throw new Error('THRØ is taking longer than usual to answer');
    throw e;
  }
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
function panels(now = Date.now()) {
  const out = [];
  if (tableStale(now)) {
    // What the comment at the top promises: past the limit the wall stops asserting the table. One panel says so,
    // in the heading's size, and the table, the fixtures and the results come back by themselves on the next answer.
    out.push({ kind: 'stale', page: 1, of: 1 });
  } else {
    for (const division of state.standings?.divisions ?? []) {
      if (!division.rows?.length) continue;
      const pages = paginate(division.rows, rowsPer('table'));
      pages.forEach((rows, i) => out.push({ kind: 'table', division: division.name, page: i + 1, of: pages.length, rows }));
    }
    const toPlay = (state.fixtures?.fixtures ?? []).filter(f => !f.decided);
    paginate(toPlay, rowsPer('fixtures')).forEach((rows, i, all) =>
      out.push({ kind: 'toPlay', page: i + 1, of: all.length, rows }));
    const done = (state.fixtures?.fixtures ?? []).filter(f => f.decided).slice(0, RECENT_RESULTS);
    paginate(done, rowsPer('fixtures')).forEach((rows, i, all) =>
      out.push({ kind: 'results', page: i + 1, of: all.length, rows }));
  }

  const livePages = gamesCurrent(now) ? paginate(state.live, LIVE_ROWS)
    .map((games, i, all) => ({ kind: 'live', page: i + 1, of: all.length, games })) : [];
  return interleave(livePages, out);
}

/** The table has had no answer for longer than a wall may go on showing it. */
const tableStale = now => !!state.table.at && now - state.table.at > STALE;
/** The games in play were read recently enough to be called "now". */
const gamesCurrent = now => !!state.games.at && now - state.games.at <= LIVE_STALE;

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

/**
 * The day, and for a fixture still to play the time: "Thu 8 Oct 19:30". It was the day alone, so a wall showing
 * tonight's fixtures could not say which board started first. London's time, whatever the television's clock is set
 * to, because a pub television's clock is set to whatever it was set to in the shop. An instant at exactly midnight
 * is a date with no time in it, and says the day alone.
 */
const day = (iso, withTime) => {
  const d = new Date(iso);
  if (!iso || Number.isNaN(d.getTime())) return '';
  const date = d.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'Europe/London' });
  if (!withTime || !/T\d/.test(iso)) return date;
  const time = d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', hourCycle: 'h23', timeZone: 'Europe/London' });
  return time === '00:00' ? date : `${date} ${time}`;
};

/** How long ago [at] was, in words a room reads at a glance. The table's answer unless another is named. */
function heard(now, at = state.table.at) {
  if (!at) return 'Waiting for THRØ';
  const mins = Math.floor((now - at) / 60_000);
  if (mins < 1) return 'Just now';
  return mins === 1 ? '1 minute ago' : `${mins} minutes ago`;
}

// --- how much fits ------------------------------------------------------------------------------------------------

// Rows per page, measured on this screen. Everything on the wall scales off the viewport's width, so how many rows fit
// its height depends on the television's shape and nothing else: a 16:9 set holds about seven rows of the table, a
// 4:3 monitor behind a bar more. Measured rather than worked out from the stylesheet's numbers, because the numbers
// are font sizes and a row is as tall as the face that loaded draws it.
const fitted = {};

function rowsPer(kind) {
  return fitted[kind] || (kind === 'table' ? TABLE_ROWS : FIXTURE_ROWS);
}

function fit() {
  const root = document.getElementById('wall');
  if (!root || !root.clientHeight) return;
  const sample = new Date().toISOString();
  const probes = {
    table: drawTable({ kind: 'table', division: 'Division', page: 1, of: 2,
                       rows: [{ position: 10, name: 'Team', played: 10, won: 10, legDifference: 10, points: 10 }] }, 'Rules'),
    fixtures: drawFixtures({ kind: 'toPlay', page: 1, of: 2,
                             rows: [{ home: 'Team', away: 'Team', venue: 'Venue', scheduledAt: sample }] }, 'Still to play'),
  };
  for (const [kind, probe] of Object.entries(probes)) {
    probe.style.cssText = 'position:absolute;left:0;right:0;top:0;height:auto;visibility:hidden';
    root.append(probe);
    const row = probe.querySelector('tbody tr');
    const rowHeight = row ? row.getBoundingClientRect().height : 0;
    const chrome = probe.getBoundingClientRect().height - rowHeight;
    probe.remove();
    if (rowHeight > 0) {
      fitted[kind] = Math.max(3, Math.min(kind === 'table' ? TABLE_ROWS : FIXTURE_ROWS,
                                           Math.floor((root.clientHeight - chrome) / rowHeight)));
    }
  }
  fitted.done = true;
}

/** A new shape of screen, or the brand's face arriving after the fallback's, is measured again. */
function refit() {
  for (const k of Object.keys(fitted)) delete fitted[k];
  const root = document.getElementById('wall');
  if (root) delete root.dataset.showing;
}

// --- drawing ------------------------------------------------------------------------------------

function drawTable(panel, says = state.standings?.rules?.says) {
  const wrap = el('div', 'panel');
  wrap.append(head(panel.division, panel.page, panel.of));
  const table = el('table', 'wall-table standings');
  // The columns say what they are. Four bare columns of numbers under a team's name were a puzzle from the bar —
  // which is played, which is won — and a regular who knew the app's table still had to guess this one's order.
  const thead = el('thead');
  const hr = el('tr');
  for (const [cls, label, title] of [['pos', '', 'Position'], ['team', 'Team', 'Team'], ['num', 'P', 'Played'],
                                     ['num', 'W', 'Won'], ['num', '+/−', 'Leg difference'], ['points', 'Pts', 'Points']]) {
    const th = el('th', cls, label);
    th.scope = 'col';
    if (!label) { th.setAttribute('aria-label', title); } else th.title = title;
    hr.append(th);
  }
  thead.append(hr);
  const body = el('tbody');
  for (const row of panel.rows) {
    const tr = el('tr');
    tr.append(el('td', 'pos', String(row.position)));
    tr.append(el('td', 'team', row.name));
    tr.append(el('td', 'num', String(row.played)));
    tr.append(el('td', 'num', String(row.won)));
    tr.append(el('td', 'num', row.legDifference > 0 ? `+${row.legDifference}` : String(row.legDifference)));
    tr.append(el('td', 'points', String(row.points)));
    body.append(tr);
  }
  table.append(thead, body);
  wrap.append(table);
  if (says) wrap.append(el('p', 'foot', says));
  return wrap;
}

function drawFixtures(panel, title) {
  const wrap = el('div', 'panel');
  wrap.append(head(title, panel.page, panel.of));
  const table = el('table', 'wall-table fixtures');
  const body = el('tbody');
  for (const f of panel.rows) {
    const tr = el('tr');
    tr.append(el('td', 'team', sides(f)));
    tr.append(el('td', 'aside what', panel.kind === 'results' ? outcome(f) : (f.venue ?? '')));
    tr.append(el('td', 'aside when', day(f.scheduledAt, panel.kind !== 'results')));
    body.append(tr);
  }
  table.append(body);
  wrap.append(table);
  return wrap;
}

/** Past the limit: the table is taken down, and the wall says why in words the far end of the room can read. */
function drawStale(now) {
  const wrap = el('div', 'panel stale');
  wrap.append(head('The table is not up to date', 1, 1));
  const mins = Math.floor((now - state.table.at) / 60_000);
  wrap.append(el('p', 'saying', `THRØ has not answered for ${mins} minutes, so the table and fixtures are off the `
    + 'screen in case they have changed. This screen keeps asking, and they come back by themselves.'));
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

  // Blank rather than the brand's name: the mark is already in the corner, and a heading reading
  // "THRØ" over a board that says THRØ is the app talking about itself on somebody's wall.
  document.getElementById('league').textContent = state.standings?.league ?? '';
  const foot = document.getElementById('foot');
  // Each feed says its own age and its own fault. The table's is always said; the games' only when something is
  // wrong with them, because "games: just now" every ten seconds is noise on a wall with no game on.
  const said = [`Table ${state.table.at ? heard(now).toLowerCase() : 'not read yet'}`];
  if (state.table.trouble) said.push(state.table.trouble);
  const gamesLost = state.games.trouble && !gamesCurrent(now);
  if (gamesLost) {
    const mins = state.games.at ? Math.max(1, Math.round((now - state.games.at) / 60_000)) : 0;
    said.push(mins ? `Games in play not read for ${mins === 1 ? 'a minute' : `${mins} minutes`}, so none are shown`
                   : 'Games in play could not be read');
  }
  foot.textContent = said.join(' · ');
  foot.className = state.table.trouble || tableStale(now) || gamesLost ? 'trouble' : '';

  if (!fitted.done) fit();
  const all = panels(now);
  const panel = showing(all, now);

  // Drawn again when a different panel is due, or when the feed behind the one showing has answered since: a wall
  // whose league fits on one panel showed the same panel for ever, and so it never drew a result that came in.
  const feed = panel?.kind === 'live' ? state.games : state.table;
  const next = panel
    ? [panel.kind, panel.division ?? '', panel.page, feed.version, panel.kind === 'stale' ? Math.floor(now / 60_000) : ''].join('|')
    : `nothing|${state.table.version}|${state.table.trouble ?? ''}`;
  if (root.dataset.showing === next) return;
  root.dataset.showing = next;
  root.replaceChildren();

  if (!panel) {
    const wrap = el('div', 'panel');
    if (state.table.trouble && !state.table.at) {
      // A read that failed is not a league with nothing in it.
      wrap.append(el('h2', null, 'Waiting for THRØ'));
      wrap.append(el('p', 'saying', 'THRØ has not answered yet. This screen keeps asking; leave it on.'));
    } else {
      wrap.append(el('h2', null, 'Nothing to show yet'));
      wrap.append(el('p', 'saying', 'When this league has a table or a fixture list, it appears here.'));
    }
    root.append(wrap);
    return;
  }
  if (panel.kind === 'table') root.append(drawTable(panel));
  else if (panel.kind === 'live') root.append(drawLive(panel));
  else if (panel.kind === 'stale') root.append(drawStale(now));
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
    state.table.at = Date.now();
    state.table.trouble = null;
    state.table.version += 1;
  } catch (e) {
    // What is on screen stays on screen. A dropped request is not news that the league has no table,
    // and blanking a wall on a flaky pub connection turns one bad minute into an empty evening. Past STALE it is
    // taken down, and said so (see panels).
    state.table.trouble = e.message;
  }
}

async function readLive(season) {
  try {
    state.live = (await read(`/v1/seasons/${season}/live`)).games ?? [];
    state.games.at = Date.now();
    state.games.trouble = null;
    state.games.version += 1;
  } catch (e) {
    // **A 404 is a server without the route, not a fault.** This page is a URL, so it will be pointed
    // at servers of every vintage — a venue's bookmark outlives a deployment. An older THRØ has no
    // live route, which means there are no live games to show and nothing is wrong; saying "404" on a
    // pub wall all evening would be the newer page complaining about the older server, in front of the
    // customers. Anything else leaves the last games up for LIVE_STALE, then takes them down and says so.
    if (e.status === 404) { state.live = []; state.games.at = Date.now(); state.games.trouble = null; state.games.version += 1; return; }
    state.games.trouble = e.message;
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
  // A television's browser is resized when the set changes input or the overscan is changed, and the brand's face
  // arrives a moment after the fallback's: either changes how many rows fit, so the rows are measured again.
  addEventListener('resize', refit);
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(refit).catch(() => {});
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

window.THRO_WALL = { panels, interleave, side, sides, outcome, heard, state, paginate, day };
if (typeof document !== 'undefined' && document.getElementById('wall')) start();
