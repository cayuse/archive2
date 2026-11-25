// Stations list and the station tuning page. Plain script, no build step. Everything goes through
// /api/v1/jukeboxes (a station is a jukebox) with the token the page was rendered with.
const StationsPage = (function () {
  const cfg = () => window.STATIONS_CONFIG || {};
  const $ = id => document.getElementById(id);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  async function api(method, path, body) {
    const opts = { method, headers: { 'Authorization': 'Bearer ' + cfg().apiToken, 'Accept': 'application/json' } };
    if (body !== undefined) { opts.headers['Content-Type'] = 'application/json'; opts.body = JSON.stringify(body); }
    const res = await fetch('/api/v1' + path, opts);
    let data = null;
    try { data = await res.json(); } catch (e) { /* empty body */ }
    if (!res.ok || (data && data.success === false)) {
      const message = (data && data.message) || ('Request failed (' + res.status + ')');
      showError(message);
      throw new Error(message);
    }
    showError(null);
    return data;
  }

  function showError(message) {
    const box = $('stations-error');
    if (!box) return;
    box.textContent = message || '';
    box.classList.toggle('d-none', !message);
  }

  const songLine = s => `<span class="text-truncate me-2"><span>${esc(s.title)}</span> <small class="theme-text-secondary">${esc([s.artist, s.album].filter(Boolean).join(' · '))}</small></span>`;
  const item = inner => `<li class="list-group-item d-flex justify-content-between align-items-center px-0">${inner}</li>`;
  const empty = text => `<li class="list-group-item px-0 theme-text-secondary small">${esc(text)}</li>`;

  async function searchSongs(q) {
    const data = await api('GET', '/songs?' + new URLSearchParams({ search: q, limit: 15, sort_by: 'title', sort_order: 'asc' }));
    return data.songs || [];
  }

  function wireSearch(inputId, buttonId, listId, renderButton, onPick) {
    const run = async () => {
      const q = $(inputId).value.trim();
      if (!q) return;
      const songs = await searchSongs(q);
      $(listId).innerHTML = songs.map(s => item(songLine(s) + renderButton(s))).join('') || empty('No matches');
    };
    $(buttonId).onclick = run;
    $(inputId).onkeydown = e => { if (e.key === 'Enter') { e.preventDefault(); run(); } };
    $(listId).onclick = e => { const b = e.target.closest('button[data-song]'); if (b) onPick(b.dataset.song, b); };
  }

  // ---- stations list
  function initIndex() {
    wireSearch('new-station-q', 'new-station-go', 'new-station-results',
      s => `<button type="button" class="btn btn-sm btn-primary flex-shrink-0" data-song="${esc(s.id)}">Start station</button>`,
      async songId => {
        const data = await api('POST', '/jukeboxes/station', { song_id: songId, new: true });
        window.location = '/stations/' + data.jukebox.id;
      });
    $('stations-list').onclick = async e => {
      const b = e.target.closest('button[data-delete-station]');
      if (!b || !confirm('Delete the station "' + b.dataset.name + '" and what it has learned?')) return;
      await api('DELETE', '/jukeboxes/' + b.dataset.deleteStation + '/station');
      window.location.reload();
    };
  }

  // ---- tuning page
  const DIAL_LABELS = {
    danceability: ['Less danceable', 'More danceable'], happiness: ['Darker', 'Happier'],
    aggression: ['Gentler', 'Harder'], acousticness: ['Less acoustic', 'More acoustic'],
    electronic: ['Less electronic', 'More electronic'], instrumental: ['More vocals', 'More instrumental']
  };
  const LEAN = 0.6;
  let station = null;

  const base = () => '/jukeboxes/' + cfg().stationId;

  async function load() {
    const data = await api('GET', base() + '/tuning');
    station = data.jukebox;
    renderSound(data.jukebox.radio, data.tuning);
    renderLists(data.tuning);
    $('live-badge').classList.toggle('d-none', !data.jukebox.live);
  }

  async function setSound(attrs) {
    const data = await api('PATCH', base() + '/radio_settings', attrs);
    station = data.jukebox;
    renderSound(station.radio, null);
  }

  function renderSound(radio, tuning) {
    const auto = radio.intensity === null || radio.intensity === undefined;
    $('intensity-auto').checked = auto;
    $('intensity').disabled = auto;
    $('intensity').value = auto ? 0 : radio.intensity;
    $('variety').value = radio.variety;
    $('learn').checked = !!radio.learn;
    document.querySelectorAll('#genre-mode button').forEach(b => {
      const on = b.dataset.genre === (radio.genre || 'any');
      b.classList.toggle('btn-secondary', on);
      b.classList.toggle('btn-outline-secondary', !on);
    });
    $('dials').innerHTML = cfg().dials.map(dial => {
      const value = Number((radio.steer || {})[dial] || 0);
      const labels = DIAL_LABELS[dial] || ['Less ' + dial, 'More ' + dial];
      const btn = (v, text) => `<button type="button" class="btn ${Math.sign(value) === Math.sign(v) && (v !== 0 || value === 0) ? 'btn-secondary' : 'btn-outline-secondary'}" data-dial="${dial}" data-v="${v}">${esc(text)}</button>`;
      return `<div class="btn-group btn-group-sm w-100 mb-1" role="group">${btn(-LEAN, labels[0])}${btn(0, 'Either')}${btn(LEAN, labels[1])}</div>`;
    }).join('');
    if (tuning) {
      const learned = Object.entries(tuning.learned_dials || {}).map(([dial, v]) => {
        const labels = DIAL_LABELS[dial] || (dial === 'energy' ? ['mellower', 'more energy'] : ['less ' + dial, 'more ' + dial]);
        return (v < 0 ? labels[0] : labels[1]).toLowerCase();
      });
      $('learned').textContent = !station.radio.learn ? '' :
        learned.length ? 'From your thumbs it has learned you want it: ' + learned.join(', ') + '.' :
        tuning.taste_confidence > 0 ? 'Learning your taste (' + Math.round(tuning.taste_confidence * 100) + '% of the way to full strength).' :
        'Nothing learned yet. Thumbs up and down while it plays.';
    }
  }

  function renderLists(t) {
    const remove = (kind, id, text) => `<button type="button" class="btn btn-sm btn-outline-secondary flex-shrink-0" data-act="${kind}" data-id="${esc(id)}">${esc(text)}</button>`;
    const list = (id, songs, emptyText, button) => { $(id).innerHTML = songs.map(s => item(songLine(s) + button(s))).join('') || empty(emptyText); };
    list('list-seeds', t.seeds, 'No seeds: the station follows the latest request.', s => remove('unseed', s.id, 'Remove'));
    list('list-liked', t.liked, 'Thumbs up songs you want more like.', s => remove('clear', s.id, 'Remove'));
    list('list-disliked', t.disliked, 'Nothing thumbed down on this station.', s => remove('clear', s.id, 'Remove'));
    list('list-tired', t.tired, 'Nothing shelved.', s => `<small class="theme-text-secondary me-2 flex-shrink-0">back ${esc(new Date(s.expires_at).toLocaleDateString())}</small>` + remove('clear', s.id, 'Bring back'));
    list('list-never', t.never, 'Nothing banned.', s => remove('clear', s.id, 'Allow again'));
    ['liked', 'disliked', 'tired', 'never'].forEach(k => { $('count-' + k).textContent = t[k].length || ''; });
    $('artists-block').classList.toggle('d-none', !t.removed_artists.length);
    $('list-artists').innerHTML = t.removed_artists.map(a => item(`<span>${esc(a.name)}</span>` + remove('keep-artist', a.id, 'Put back'))).join('');
    $('list-recent').innerHTML = t.recent.map(s => {
      const vote = (kind, icon, title) => `<button type="button" class="btn btn-sm ${s.standing === kind ? 'btn-secondary' : 'btn-outline-secondary'}" title="${title}" data-act="${s.standing === kind ? 'clear' : kind}" data-id="${esc(s.id)}"><i class="fas ${icon}"></i></button>`;
      return item(songLine(s) + `<span class="btn-group flex-shrink-0">${vote('up', 'fa-thumbs-up', 'More like this')}${vote('down', 'fa-thumbs-down', 'Not on this station')}${vote('tired', 'fa-bed', 'Sick of it for now')}${vote('never', 'fa-ban', 'Never play this for me')}</span>`);
    }).join('') || empty('Nothing has played on this station yet.');
  }

  function initTuning() {
    $('intensity').onchange = () => setSound({ intensity: Number($('intensity').value) });
    $('intensity-auto').onchange = () => setSound({ intensity: $('intensity-auto').checked ? 'auto' : 0 });
    $('variety').onchange = () => setSound({ variety: Number($('variety').value) });
    $('learn').onchange = async () => { await setSound({ learn: $('learn').checked }); load(); };
    $('genre-mode').onclick = e => { const b = e.target.closest('button[data-genre]'); if (b) setSound({ genre: b.dataset.genre }); };
    $('dials').onclick = e => { const b = e.target.closest('button[data-dial]'); if (b) setSound({ [b.dataset.dial]: Number(b.dataset.v) }); };
    $('reset-sound').onclick = () => setSound({ reset_steer: true, genre: 'any', variety: 0.5 });
    $('rename-station').onclick = async () => {
      const name = prompt('Station name', station ? station.name : '');
      if (!name || !name.trim()) return;
      const data = await api('PATCH', base() + '/station', { name: name.trim() });
      $('station-name').textContent = data.jukebox.name;
    };
    wireSearch('seed-q', 'seed-go', 'seed-results',
      s => `<button type="button" class="btn btn-sm btn-outline-primary flex-shrink-0" data-song="${esc(s.id)}">Add seed</button>`,
      async songId => { await api('POST', base() + '/seeds', { song_id: songId }); $('seed-results').innerHTML = ''; $('seed-q').value = ''; load(); });
    $('tuning-root').addEventListener('click', async e => {
      const b = e.target.closest('button[data-act]');
      if (!b) return;
      const id = b.dataset.id, act = b.dataset.act;
      if (act === 'unseed') await api('DELETE', base() + '/seeds/' + id);
      else if (act === 'keep-artist') await api('POST', base() + '/artists/' + id + '/keep');
      else await api('POST', base() + '/feedback', { song_id: id, kind: act });
      load();
    });
    load();
  }

  return { initIndex, initTuning };
})();
