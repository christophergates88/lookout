// Mock of the artifact runtime for local testing: window.claude.use('db'|'downloads'|'user')
(function(){
  const store = window.__seed || {};
  const listeners = [];
  const writes = [];
  const clone = v => JSON.parse(JSON.stringify(v));
  const snapDoc = (path) => { const d = store[path]; return { id: path.split('/').pop(), exists: !!d, data: () => d ? Object.freeze(clone(d)) : undefined, metadata: { fromCache: false, hasPendingWrites: false } }; };
  function deliver(l) {
    try {
      if (l.type === 'doc') return l.cb(snapDoc(l.path));
      const depth = l.path.split('/').length + 1;
      let docs = Object.keys(store).filter(p => p.startsWith(l.path + '/') && p.split('/').length === depth).map(snapDoc);
      if (l.orderBy) { const f = l.orderBy; docs.sort((a, b) => String(a.data()[f] ?? '').localeCompare(String(b.data()[f] ?? ''))); if (l.dir === 'desc') docs.reverse(); }
      else docs.sort((a, b) => a.id.localeCompare(b.id));
      if (l.limit) docs = docs.slice(0, l.limit);
      l.cb({ docs, size: docs.length, empty: !docs.length, docChanges: () => [], metadata: { fromCache: false, hasPendingWrites: false } });
    } catch (e) { console.error('mock deliver', e); }
  }
  const notify = () => listeners.forEach(deliver);
  function docRef(path) {
    if (path.split('/').length % 2) throw new TypeError('document path needs an even number of segments: ' + path);
    return {
      id: path.split('/').pop(), path,
      async get() { return snapDoc(path); },
      async set(data) { if (window.__failWrites) { const e = new Error('fail'); e.code = window.__failWrites; throw e; } writes.push({ op: 'set', path, data: clone(data) }); store[path] = clone(data); setTimeout(notify, 0); },
      async update(data) { if (!store[path]) { const e = new Error('missing'); e.code = 'invalid_argument'; throw e; } writes.push({ op: 'update', path, data: clone(data) }); Object.assign(store[path], clone(data)); setTimeout(notify, 0); },
      async delete() { writes.push({ op: 'delete', path }); delete store[path]; setTimeout(notify, 0); },
      onSnapshot(cb, err) { const l = { type: 'doc', path, cb }; listeners.push(l); setTimeout(() => deliver(l), 0); return () => { const i = listeners.indexOf(l); if (i >= 0) listeners.splice(i, 1); }; },
      collection(sub) { return collRef(path + '/' + sub); },
    };
  }
  function collRef(path, opts) {
    opts = opts || {};
    if (!(path.split('/').length % 2)) throw new TypeError('collection path needs an odd number of segments: ' + path);
    return {
      path,
      doc(id) { return docRef(path + '/' + (id || ('m' + Math.random().toString(36).slice(2, 9)))); },
      async add(data) { const r = this.doc(); await r.set(data); return r; },
      where() { return collRef(path, opts); },
      orderBy(f, dir) { return collRef(path, Object.assign({}, opts, { orderBy: f, dir })); },
      limit(n) { return collRef(path, Object.assign({}, opts, { limit: n })); },
      async get() { return new Promise(res => { const l = { type: 'coll', path, cb: res, orderBy: opts.orderBy, dir: opts.dir, limit: opts.limit }; deliver(l); }); },
      onSnapshot(cb, err) { const l = { type: 'coll', path, cb, orderBy: opts.orderBy, dir: opts.dir, limit: opts.limit }; listeners.push(l); setTimeout(() => deliver(l), 0); return () => { const i = listeners.indexOf(l); if (i >= 0) listeners.splice(i, 1); }; },
    };
  }
  const db = { doc: docRef, collection: p => collRef(p) };
  const downloads = { async save({ filename, data }) { writes.push({ op: 'download', filename, bytes: (data.length || data.size || 0) }); return { outcome: 'saved' }; } };
  const user = { async id() { return 'u_test'; }, async me() { return { id: 'u_test', name: 'Test' }; }, isOwner() { return true; }, canEdit() { return true; }, async can() { return true; }, async profiles() { return {}; } };
  window.claude = { use: async (name) => { if (window.__offline) return null; return ({ db, downloads, user })[name] || null; } };
  window.__hqMock = { store, writes, notify };
})();
