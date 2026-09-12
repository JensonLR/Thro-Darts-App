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

window.THRO = { mountLeagues, mountTable };
