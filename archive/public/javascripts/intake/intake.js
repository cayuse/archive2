// The Drop Box pages: collecting what was dropped (files, folders with subfolders, archives),
// sending it file by file, and showing what became of each file.
window.IntakePage = (function () {
  const JUNK = /(^|\/)(\.DS_Store|Thumbs\.db|desktop\.ini|\._[^/]*)$/i;   // clutter operating systems add; not worth sending
  const csrf = () => (document.querySelector('meta[name="csrf-token"]') || {}).content;
  const el = (id) => document.getElementById(id);

  function showError(message) {
    const box = el("intake-error");
    box.textContent = message;
    box.classList.remove("d-none");
  }

  // ---- collecting a drop ----

  // A dropped folder arrives as a tree of entries; walk it and keep each file's path inside the folder.
  function readEntry(entry, out) {
    return new Promise((resolve, reject) => {
      if (entry.isFile) {
        entry.file((file) => { out.push({ file: file, path: entry.fullPath.replace(/^\//, "") }); resolve(); }, reject);
      } else if (entry.isDirectory) {
        const reader = entry.createReader();
        const children = [];
        const more = () => reader.readEntries((batch) => {   // a folder is read in pages of 100
          if (batch.length) { children.push(...batch); more(); }
          else Promise.all(children.map((c) => readEntry(c, out))).then(resolve, reject);
        }, reject);
        more();
      } else resolve();
    });
  }

  async function fromDrop(dataTransfer) {
    const out = [];
    const entries = Array.from(dataTransfer.items || []).map((i) => i.webkitGetAsEntry && i.webkitGetAsEntry()).filter(Boolean);
    if (entries.length) await Promise.all(entries.map((e) => readEntry(e, out)));
    else Array.from(dataTransfer.files || []).forEach((f) => out.push({ file: f, path: f.name }));
    return out;
  }

  const fromInput = (input) => Array.from(input.files).map((f) => ({ file: f, path: f.webkitRelativePath || f.name }));

  function nameFor(items) {
    const tops = Array.from(new Set(items.map((i) => i.path.split("/")[0])));
    if (tops.length === 1) return tops[0];
    return tops.length + " items: " + tops.slice(0, 3).join(", ") + (tops.length > 3 ? ", …" : "");
  }

  // ---- sending ----

  function send(url, item, onProgress) {
    return new Promise((resolve, reject) => {
      const form = new FormData();
      form.append("relative_path", item.path);
      form.append("file", item.file, item.file.name);
      const xhr = new XMLHttpRequest();
      xhr.open("POST", url);
      xhr.setRequestHeader("X-CSRF-Token", csrf());
      xhr.setRequestHeader("Accept", "application/json");
      xhr.upload.onprogress = (e) => onProgress(e.loaded);
      xhr.onload = () => (xhr.status >= 200 && xhr.status < 300 ? resolve() : reject(new Error(item.path + ": " + (xhr.status === 413 ? "too large to send (the limit is 500 MB per file)" : "HTTP " + xhr.status))));
      xhr.onerror = () => reject(new Error(item.path + ": connection lost"));
      xhr.send(form);
    });
  }

  const post = (url, body) => fetch(url, { method: "POST", credentials: "same-origin",
    headers: { "X-CSRF-Token": csrf(), "Accept": "application/json", "Content-Type": "application/json" },
    body: JSON.stringify(body || {}) }).then((r) => { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); });

  let busy = false;

  async function start(urls, items) {
    items = items.filter((i) => !JUNK.test(i.path) && i.file.size > 0);
    if (busy || !items.length) return;
    busy = true;
    window.onbeforeunload = () => "Files are still being sent.";
    el("intake-error").classList.add("d-none");
    el("intake-sending").classList.remove("d-none");
    const total = items.reduce((sum, i) => sum + i.file.size, 0);
    let sent = 0, done = 0;
    const failed = [];
    const paint = (extra, label) => {
      el("intake-bar").style.width = Math.min(100, ((sent + extra) / total) * 100).toFixed(1) + "%";
      el("intake-sending-count").textContent = done + " of " + items.length + " files";
      if (label) el("intake-sending-label").textContent = label;
    };
    try {
      const batch = await post(urls.create, { name: nameFor(items) });
      const base = urls.create + "/" + batch.id;
      for (const item of items) {
        paint(0, "Sending " + item.path);
        try { await send(base + "/files", item, (loaded) => paint(loaded)); }
        catch (e) {
          try { await send(base + "/files", item, (loaded) => paint(loaded)); }   // one retry: a blip should not lose a file
          catch (again) { failed.push(again.message); }
        }
        sent += item.file.size; done += 1;
      }
      paint(0, "Sent. Sorting…");
      await post(base + "/finish");
      window.onbeforeunload = null;
      if (failed.length) { alert("Not sent:\n" + failed.join("\n")); }
      window.location = base;
    } catch (e) {
      window.onbeforeunload = null;
      busy = false;
      showError("Sending stopped: " + e.message);
    }
  }

  function initDrop(urls) {
    const zone = el("intake-drop");
    ["dragenter", "dragover"].forEach((n) => zone.addEventListener(n, (e) => { e.preventDefault(); zone.classList.add("over"); }));
    ["dragleave", "drop"].forEach((n) => zone.addEventListener(n, (e) => { e.preventDefault(); zone.classList.remove("over"); }));
    zone.addEventListener("drop", (e) => fromDrop(e.dataTransfer).then((items) => start(urls, items), (err) => showError("Could not read what was dropped: " + err)));
    // a file dropped beside the zone must not make the browser navigate to it
    ["dragover", "drop"].forEach((n) => window.addEventListener(n, (e) => e.preventDefault()));
    el("intake-pick-files").addEventListener("click", () => el("intake-files").click());
    el("intake-pick-folder").addEventListener("click", () => el("intake-folder").click());
    el("intake-files").addEventListener("change", (e) => start(urls, fromInput(e.target)));
    el("intake-folder").addEventListener("change", (e) => start(urls, fromInput(e.target)));
  }

  // ---- one drop's results ----

  const BADGE = {
    received: ["bg-light text-dark border", "Waiting"], imported: ["bg-success", "Added"], duplicate: ["bg-secondary", "Already here"],
    rejected: ["bg-warning text-dark", "Set aside"], expanded: ["bg-info text-dark", "Unpacked"], failed: ["bg-danger", "Failed"],
  };
  const HOW = { album: "Recognised as part of its album", track: "Recognised by artist, title and album", recording: "Recognised by artist and title",
    ids: "Recognised by the IDs in its tags", tags: "Not in MusicBrainz" };

  function cell(text, cls) {
    const td = document.createElement("td");
    if (cls) td.className = cls;
    if (text) td.textContent = text;
    return td;
  }

  function render(data) {
    const body = el("intake-items");
    body.replaceChildren();
    let folder = null;
    data.items.forEach((item) => {
      const cut = item.path.lastIndexOf("/");
      const dir = cut < 0 ? "" : item.path.slice(0, cut);
      if (dir !== folder) {
        folder = dir;
        const row = document.createElement("tr");
        row.className = "intake-folder";
        const td = cell(dir || "(dropped on their own)", "intake-path");
        td.colSpan = 3;
        row.appendChild(td);
        body.appendChild(row);
      }
      const row = document.createElement("tr");
      row.appendChild(cell(item.path.slice(cut + 1), "intake-path"));
      const result = cell(null, "intake-status");
      const badge = document.createElement("span");
      badge.className = "badge " + BADGE[item.status][0];
      badge.textContent = BADGE[item.status][1];
      result.appendChild(badge);
      const note = [item.status === "imported" || item.status === "duplicate" ? HOW[item.identified] : null, item.message].filter(Boolean).join(". ");
      if (note) { const small = document.createElement("div"); small.className = "small theme-text-secondary text-wrap"; small.textContent = note; result.appendChild(small); }
      row.appendChild(result);
      const song = cell();
      if (item.song) {
        const link = document.createElement("a");
        link.href = "/songs/" + item.song.id;
        link.textContent = (item.song.track ? item.song.track + ". " : "") + item.song.title;
        song.appendChild(link);
        const small = document.createElement("div");
        small.className = "small theme-text-secondary";
        small.textContent = [item.song.artist, item.song.album].filter(Boolean).join(" · ") + (item.song.needs_review ? " · needs review" : "");
        song.appendChild(small);
      }
      row.appendChild(song);
      body.appendChild(row);
    });
    if (!data.items.length) {
      const row = document.createElement("tr");
      const td = cell(data.status === "done" ? "Nothing arrived in this drop." : "Waiting for the sorter to pick this up…", "theme-text-secondary");
      td.colSpan = 3;
      row.appendChild(td);
      body.appendChild(row);
    }
    const c = data.counts || {};
    const parts = [[c.imported, "added"], [c.duplicate, "already here"], [c.rejected, "set aside"], [c.failed, "failed"], [c.received, "still to do"]]
      .filter((p) => p[0]).map((p) => p[0] + " " + p[1]);
    const state = { uploading: "Still being sent.", queued: "Waiting for the sorter.", processing: "Being sorted now.", done: "Finished." }[data.status];
    el("intake-summary").textContent = state + (parts.length ? " " + parts.join(", ") + "." : "");
    if (data.error) showError("The sorter stopped early: " + data.error);
  }

  function initBatch(data, url) {
    render(data);
    if (data.status === "done") return;
    const timer = setInterval(() => {
      fetch(url, { credentials: "same-origin", headers: { "Accept": "application/json" } }).then((r) => r.json()).then((fresh) => {
        render(fresh);
        if (fresh.status === "done") clearInterval(timer);
      }).catch(() => {});
    }, 2000);
  }

  return { initDrop: initDrop, initBatch: initBatch };
})();
