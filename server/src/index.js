import { DurableObject } from "cloudflare:workers";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

const MAX_PLAYERS = 4;
const ROOM_TTL_MS = 90_000;
const ROLES = ["Komutan", "Sistem Müh.", "Yük Uzmanı", "Uçuş Müh."];

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      ...CORS_HEADERS,
    },
  });
}

function generateRoomCode() {
  const letters = "ABCDEFGHJKLMNPQRSTUVWXYZ";
  let prefix = "";
  for (let i = 0; i < 3; i++) {
    prefix += letters[Math.floor(Math.random() * letters.length)];
  }
  const num = Math.floor(10 + Math.random() * 90);
  return `${prefix}-${num}`;
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    const url = new URL(request.url);

    if (url.pathname === "/health" || url.pathname === "/") {
      return jsonResponse({
        ok: true,
        service: "station13-multiplayer",
        protocol: "websocket-hibernation",
      });
    }

    if (url.pathname === "/api/rooms" && request.method === "GET") {
      const lobbyStub = env.LOBBY_REGISTRY.get(env.LOBBY_REGISTRY.idFromName("global"));
      const query = url.searchParams.get("q") || "";
      const res = await lobbyStub.fetch(`https://lobby/list?q=${encodeURIComponent(query)}`);
      const body = await res.text();
      return new Response(body, {
        status: res.status,
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          ...CORS_HEADERS,
        },
      });
    }

    if (url.pathname === "/ws") {
      if (request.headers.get("Upgrade") !== "websocket") {
        return jsonResponse({ ok: false, error: "Expected Upgrade: websocket" }, 426);
      }

      const action = (url.searchParams.get("action") || "").toLowerCase();

      if (action === "create") {
        const lobbyStub = env.LOBBY_REGISTRY.get(env.LOBBY_REGISTRY.idFromName("global"));
        const allocRes = await lobbyStub.fetch("https://lobby/allocate", { method: "POST" });
        const allocData = await allocRes.json();
        const roomCode = allocData.room_code;

        const roomId = env.GAME_ROOM.idFromName(roomCode);
        const roomStub = env.GAME_ROOM.get(roomId);
        const forwardUrl = new URL(request.url);
        forwardUrl.pathname = "/create";
        forwardUrl.searchParams.set("room_code", roomCode);

        return roomStub.fetch(new Request(forwardUrl.toString(), request));
      }

      if (action === "join") {
        const rawCode = (url.searchParams.get("code") || "").trim().toUpperCase();
        if (!rawCode) {
          return rejectWsWithError("Lütfen geçerli bir Oda Kodu girin (örn: KZM-47)!");
        }
        const roomId = env.GAME_ROOM.idFromName(rawCode);
        const roomStub = env.GAME_ROOM.get(roomId);
        const forwardUrl = new URL(request.url);
        forwardUrl.pathname = "/join";
        forwardUrl.searchParams.set("room_code", rawCode);

        return roomStub.fetch(new Request(forwardUrl.toString(), request));
      }

      return rejectWsWithError("Geçersiz bağlantı isteği.");
    }

    return jsonResponse({ ok: false, error: "Not found" }, 404);
  },
};

function rejectWsWithError(message) {
  const pair = new WebSocketPair();
  const [client, server] = Object.values(pair);
  server.accept();
  server.send(JSON.stringify({ type: "join_error", message }));
  server.close(4000, message);
  return new Response(null, { status: 101, webSocket: client });
}

export class LobbyRegistry extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec(`
        CREATE TABLE IF NOT EXISTS rooms (
          room_code TEXT PRIMARY KEY,
          is_public INTEGER NOT NULL DEFAULT 0,
          is_mission_active INTEGER NOT NULL DEFAULT 0,
          host_name TEXT NOT NULL DEFAULT '',
          mission_name TEXT NOT NULL DEFAULT '',
          player_count INTEGER NOT NULL DEFAULT 1,
          max_players INTEGER NOT NULL DEFAULT 4,
          updated_at INTEGER NOT NULL
        );
      `);
    });
  }

  _pruneExpired() {
    const cutoff = Date.now() - ROOM_TTL_MS;
    this.ctx.storage.sql.exec("DELETE FROM rooms WHERE updated_at < ?", cutoff);
  }

  async fetch(request) {
    const url = new URL(request.url);
    this._pruneExpired();

    if (url.pathname === "/allocate" && request.method === "POST") {
      let candidate = generateRoomCode();
      for (let i = 0; i < 20; i++) {
        const existing = this.ctx.storage.sql
          .exec("SELECT room_code FROM rooms WHERE room_code = ?", candidate)
          .toArray();
        if (existing.length === 0) break;
        candidate = generateRoomCode();
      }
      this.ctx.storage.sql.exec(
        `INSERT OR REPLACE INTO rooms
         (room_code, is_public, is_mission_active, host_name, mission_name, player_count, max_players, updated_at)
         VALUES (?, 0, 0, '', '', 1, ?, ?)`,
        candidate,
        MAX_PLAYERS,
        Date.now()
      );
      return jsonResponse({ ok: true, room_code: candidate });
    }

    if (url.pathname === "/upsert" && request.method === "POST") {
      const body = await request.json();
      if (!body || !body.room_code) {
        return jsonResponse({ ok: false }, 400);
      }
      this.ctx.storage.sql.exec(
        `INSERT OR REPLACE INTO rooms
         (room_code, is_public, is_mission_active, host_name, mission_name, player_count, max_players, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        String(body.room_code),
        body.is_public ? 1 : 0,
        body.is_mission_active ? 1 : 0,
        String(body.host_name || "Host"),
        String(body.mission_name || ""),
        Number(body.player_count || 1),
        Number(body.max_players || MAX_PLAYERS),
        Date.now()
      );
      return jsonResponse({ ok: true });
    }

    if (url.pathname === "/remove" && request.method === "POST") {
      const body = await request.json();
      if (body && body.room_code) {
        this.ctx.storage.sql.exec("DELETE FROM rooms WHERE room_code = ?", String(body.room_code));
      }
      return jsonResponse({ ok: true });
    }

    if (url.pathname === "/list" && request.method === "GET") {
      const q = (url.searchParams.get("q") || "").trim().toLowerCase();
      const rows = this.ctx.storage.sql
        .exec(
          `SELECT room_code, is_public, is_mission_active, host_name, mission_name, player_count, max_players, updated_at
           FROM rooms
           WHERE is_public = 1 AND is_mission_active = 0 AND player_count > 0 AND player_count < max_players
           ORDER BY updated_at DESC
           LIMIT 50`
        )
        .toArray();

      const filtered = q
        ? rows.filter((r) => {
            const code = String(r.room_code || "").toLowerCase();
            const host = String(r.host_name || "").toLowerCase();
            const mission = String(r.mission_name || "").toLowerCase();
            return code.includes(q) || host.includes(q) || mission.includes(q);
          })
        : rows;

      return jsonResponse({ ok: true, rooms: filtered });
    }

    return jsonResponse({ ok: false }, 404);
  }
}

export class GameRoom extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec(`
        CREATE TABLE IF NOT EXISTS room_state (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          data TEXT NOT NULL
        );
      `);
    });
  }

  _loadState() {
    const rows = this.ctx.storage.sql.exec("SELECT data FROM room_state WHERE id = 1").toArray();
    if (rows.length === 0) return null;
    try {
      return JSON.parse(rows[0].data);
    } catch {
      return null;
    }
  }

  _saveState(state) {
    this.ctx.storage.sql.exec(
      "INSERT OR REPLACE INTO room_state (id, data) VALUES (1, ?)",
      JSON.stringify(state)
    );
  }

  _clearState() {
    this.ctx.storage.sql.exec("DELETE FROM room_state WHERE id = 1");
  }

  _pruneDisconnectedPlayers(state) {
    const livePeerIds = new Set();
    for (const sock of this.ctx.getWebSockets()) {
      const att = sock.deserializeAttachment();
      if (att && att.peer_id) {
        livePeerIds.add(att.peer_id);
      }
    }
    const before = state.players.length;
    state.players = state.players.filter((p) => livePeerIds.has(p.peer_id));
    if (state.players.length !== before) {
      this._reindexRoles(state);
      this._saveState(state);
    }
  }

  _reindexRoles(state) {
    for (let i = 0; i < state.players.length; i++) {
      state.players[i].role = ROLES[i] || "Mürettebat";
    }
  }

  _pickColorIdx(state) {
    const used = new Set(state.players.map((p) => Number(p.color_idx)));
    for (let c = 0; c < 4; c++) {
      if (!used.has(c)) return c;
    }
    return state.players.length % 4;
  }

  _dedupeTag(state, rawTag) {
    let base = String(rawTag || "Astronot#1000").trim();
    if (!base) base = "Astronot#1000";
    const existing = new Set(state.players.map((p) => String(p.tag || "").toLowerCase()));
    if (!existing.has(base.toLowerCase())) return base;
    let n = 2;
    while (existing.has(`${base}_${n}`.toLowerCase())) {
      n++;
    }
    return `${base}_${n}`;
  }

  async _syncRegistry(state) {
    const lobbyStub = this.env.LOBBY_REGISTRY.get(this.env.LOBBY_REGISTRY.idFromName("global"));
    if (!state || !state.exists || state.players.length === 0) {
      if (state && state.room_code) {
        await lobbyStub.fetch("https://lobby/remove", {
          method: "POST",
          body: JSON.stringify({ room_code: state.room_code }),
        });
      }
      return;
    }
    const hostPlayer = state.players.find((p) => p.is_host) || state.players[0];
    await lobbyStub.fetch("https://lobby/upsert", {
      method: "POST",
      body: JSON.stringify({
        room_code: state.room_code,
        is_public: Boolean(state.is_public),
        is_mission_active: Boolean(state.is_mission_active),
        host_name: hostPlayer ? hostPlayer.tag : "Host",
        mission_name: state.mission_name || "",
        player_count: state.players.length,
        max_players: MAX_PLAYERS,
      }),
    });
  }

  _broadcast(payload, excludePeerId = null) {
    const text = JSON.stringify(payload);
    for (const sock of this.ctx.getWebSockets()) {
      const att = sock.deserializeAttachment();
      if (excludePeerId !== null && att && att.peer_id === excludePeerId) {
        continue;
      }
      try {
        sock.send(text);
      } catch {
        // Ignore dead socket; hibernation runtime closes it
      }
    }
  }

  _publicStateView(state) {
    return {
      room_code: state.room_code,
      is_public: Boolean(state.is_public),
      is_mission_active: Boolean(state.is_mission_active),
      mission_idx: Number(state.mission_idx || 0),
      modifier_idx: Number(state.modifier_idx || 0),
      mission_name: String(state.mission_name || ""),
      rocket_id: String(state.rocket_id || ""),
      site_id: String(state.site_id || ""),
      players: state.players,
    };
  }

  async fetch(request) {
    const url = new URL(request.url);
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);

    if (url.pathname === "/create") {
      // Close any leftover sockets if this room code was somehow reused
      for (const oldSock of this.ctx.getWebSockets()) {
        try {
          oldSock.close(4001, "Room recreated");
        } catch {}
      }

      const roomCode = (url.searchParams.get("room_code") || "").toUpperCase();
      const isPublic = url.searchParams.get("public") === "true";
      const hostTag = url.searchParams.get("tag") || "Commander#1000";
      const missionIdx = Number(url.searchParams.get("mission_idx") || 0);
      const modifierIdx = Number(url.searchParams.get("modifier_idx") || 0);
      const missionName = url.searchParams.get("mission_name") || "";
      const rocketId = url.searchParams.get("rocket_id") || "";
      const siteId = url.searchParams.get("site_id") || "";

      const state = {
        exists: true,
        room_code: roomCode,
        is_public: isPublic,
        is_mission_active: false,
        mission_idx: missionIdx,
        modifier_idx: modifierIdx,
        mission_name: missionName,
        rocket_id: rocketId,
        site_id: siteId,
        next_peer_id: 2,
        last_registry_sync: Date.now(),
        players: [
          {
            peer_id: 1,
            tag: hostTag,
            color_idx: 0,
            is_host: true,
            role: ROLES[0],
          },
        ],
      };

      this._saveState(state);
      this.ctx.acceptWebSocket(server);
      server.serializeAttachment({ peer_id: 1, tag: hostTag, is_host: true });
      await this._syncRegistry(state);

      server.send(
        JSON.stringify({
          type: "room_created",
          peer_id: 1,
          room_code: roomCode,
          state: this._publicStateView(state),
        })
      );

      return new Response(null, { status: 101, webSocket: client });
    }

    if (url.pathname === "/join") {
      const roomCode = (url.searchParams.get("room_code") || "").toUpperCase();
      const rawTag = url.searchParams.get("tag") || "Astronot#1000";
      const state = this._loadState();

      this.ctx.acceptWebSocket(server);

      if (!state || !state.exists) {
        const msg = `HATA: '${roomCode}' kodlu açık bir oda bulunamadı!`;
        server.send(JSON.stringify({ type: "join_error", message: msg }));
        server.close(4004, msg);
        return new Response(null, { status: 101, webSocket: client });
      }

      this._pruneDisconnectedPlayers(state);

      if (state.players.length === 0) {
        const msg = `HATA: '${roomCode}' kodlu oda artık aktif değil.`;
        server.send(JSON.stringify({ type: "join_error", message: msg }));
        server.close(4004, msg);
        return new Response(null, { status: 101, webSocket: client });
      }

      if (state.is_mission_active) {
        const msg = `HATA: '${roomCode}' odasında görev zaten başlamış!`;
        server.send(JSON.stringify({ type: "join_error", message: msg }));
        server.close(4009, msg);
        return new Response(null, { status: 101, webSocket: client });
      }

      if (state.players.length >= MAX_PLAYERS) {
        const msg = `HATA: '${roomCode}' odası tamamen dolu (4/4)!`;
        server.send(JSON.stringify({ type: "join_error", message: msg }));
        server.close(4009, msg);
        return new Response(null, { status: 101, webSocket: client });
      }

      const peerId = Number(state.next_peer_id || 2);
      state.next_peer_id = peerId + 1;
      const uniqueTag = this._dedupeTag(state, rawTag);
      const colorIdx = this._pickColorIdx(state);
      const role = ROLES[state.players.length] || "Mürettebat";

      state.players.push({
        peer_id: peerId,
        tag: uniqueTag,
        color_idx: colorIdx,
        is_host: false,
        role,
      });

      this._saveState(state);
      server.serializeAttachment({ peer_id: peerId, tag: uniqueTag, is_host: false });
      await this._syncRegistry(state);

      const view = this._publicStateView(state);
      server.send(
        JSON.stringify({
          type: "room_joined",
          peer_id: peerId,
          room_code: state.room_code,
          state: view,
        })
      );

      this._broadcast({ type: "lobby_state", state: view }, peerId);
      return new Response(null, { status: 101, webSocket: client });
    }

    return jsonResponse({ ok: false }, 404);
  }

  async webSocketMessage(ws, rawMessage) {
    const att = ws.deserializeAttachment();
    if (!att || !att.peer_id) return;

    let msg;
    try {
      msg = JSON.parse(typeof rawMessage === "string" ? rawMessage : new TextDecoder().decode(rawMessage));
    } catch {
      return;
    }
    if (!msg || typeof msg !== "object") return;

    const state = this._loadState();
    if (!state || !state.exists) return;

    switch (msg.type) {
      case "ping": {
        const now = Date.now();
        if (att.is_host && now - Number(state.last_registry_sync || 0) >= 12_000) {
          state.last_registry_sync = now;
          this._saveState(state);
          await this._syncRegistry(state);
        }
        ws.send(JSON.stringify({ type: "pong" }));
        break;
      }

      case "update_lobby": {
        if (!att.is_host) return;
        if (typeof msg.is_public === "boolean") state.is_public = msg.is_public;
        if (typeof msg.mission_idx === "number") state.mission_idx = msg.mission_idx;
        if (typeof msg.modifier_idx === "number") state.modifier_idx = msg.modifier_idx;
        if (typeof msg.mission_name === "string") state.mission_name = msg.mission_name;
        if (typeof msg.rocket_id === "string") state.rocket_id = msg.rocket_id;
        if (typeof msg.site_id === "string") state.site_id = msg.site_id;
        if (typeof msg.host_tag === "string" && msg.host_tag.trim() !== "") {
          const hostP = state.players.find((p) => p.peer_id === att.peer_id);
          if (hostP) hostP.tag = msg.host_tag.trim();
        }
        state.last_registry_sync = Date.now();
        this._saveState(state);
        await this._syncRegistry(state);
        this._broadcast({ type: "lobby_state", state: this._publicStateView(state) });
        break;
      }

      case "set_color": {
        const reqColor = Number(msg.color_idx);
        if (Number.isNaN(reqColor) || reqColor < 0 || reqColor > 3) return;
        const taken = state.players.some(
          (p) => p.peer_id !== att.peer_id && Number(p.color_idx) === reqColor
        );
        if (taken) return;
        const me = state.players.find((p) => p.peer_id === att.peer_id);
        if (!me) return;
        me.color_idx = reqColor;
        this._saveState(state);
        this._broadcast({ type: "lobby_state", state: this._publicStateView(state) });
        break;
      }

      case "start_mission": {
        if (!att.is_host) return;
        state.is_mission_active = true;
        if (typeof msg.mission_idx === "number") state.mission_idx = msg.mission_idx;
        if (typeof msg.modifier_idx === "number") state.modifier_idx = msg.modifier_idx;
        if (typeof msg.mission_name === "string") state.mission_name = msg.mission_name;
        if (typeof msg.rocket_id === "string") state.rocket_id = msg.rocket_id;
        if (typeof msg.site_id === "string") state.site_id = msg.site_id;
        this._saveState(state);
        await this._syncRegistry(state);
        this._broadcast(
          { type: "mission_started", state: this._publicStateView(state) },
          att.peer_id
        );
        break;
      }

      case "return_to_lobby": {
        if (!att.is_host) return;
        state.is_mission_active = false;
        this._saveState(state);
        await this._syncRegistry(state);
        this._broadcast(
          { type: "return_to_lobby", state: this._publicStateView(state) },
          att.peer_id
        );
        break;
      }

      case "relay": {
        const out = {
          type: "relay",
          event: String(msg.event || ""),
          data: msg.data && typeof msg.data === "object" ? msg.data : {},
          from_peer_id: att.peer_id,
        };
        this._broadcast(out, msg.include_self ? null : att.peer_id);
        break;
      }

      case "leave": {
        await this._handlePeerDisconnect(ws, att);
        try {
          ws.close(1000, "Client left");
        } catch {}
        break;
      }
    }
  }

  async _handlePeerDisconnect(ws, att) {
    if (!att || !att.peer_id) return;
    const state = this._loadState();
    if (!state || !state.exists) return;

    const wasPresent = state.players.some((p) => p.peer_id === att.peer_id);
    if (!wasPresent) return;

    if (att.is_host) {
      this._broadcast(
        { type: "room_closed", reason: "Host bağlantıyı kapattı." },
        att.peer_id
      );
      for (const sock of this.ctx.getWebSockets()) {
        if (sock !== ws) {
          try {
            sock.close(4002, "Host disconnected");
          } catch {}
        }
      }
      state.exists = false;
      state.players = [];
      this._clearState();
      await this._syncRegistry(state);
      return;
    }

    state.players = state.players.filter((p) => p.peer_id !== att.peer_id);
    this._reindexRoles(state);

    if (state.players.length === 0) {
      state.exists = false;
      this._clearState();
      await this._syncRegistry(state);
      return;
    }

    this._saveState(state);
    await this._syncRegistry(state);
    this._broadcast({ type: "peer_left", peer_id: att.peer_id });
    this._broadcast({ type: "lobby_state", state: this._publicStateView(state) });
  }

  async webSocketClose(ws) {
    const att = ws.deserializeAttachment();
    await this._handlePeerDisconnect(ws, att);
  }

  async webSocketError(ws) {
    const att = ws.deserializeAttachment();
    await this._handlePeerDisconnect(ws, att);
  }
}
