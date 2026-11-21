import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { WebSocketServer, WebSocket } from "ws";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const LEADERBOARD_FILE = process.env.LEADERBOARD_FILE || path.join(__dirname, "leaderboard-data.json");
const MAX_LEADERBOARD_RECORDS = 200;

const PORT = Number(process.env.PORT || 8787);
const MAX_PLAYERS = 4;
const ROOM_TTL_MS = 90_000;
const ROLES = ["Komutan", "Sistem Müh.", "Yük Uzmanı", "Uçuş Müh."];

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

/** @type {Map<string, any>} */
const rooms = new Map();

/** @type {Array<any>} */
let leaderboard = loadLeaderboard();

function loadLeaderboard() {
  try {
    if (!fs.existsSync(LEADERBOARD_FILE)) return [];
    const parsed = JSON.parse(fs.readFileSync(LEADERBOARD_FILE, "utf8"));
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function saveLeaderboard() {
  try {
    fs.writeFileSync(LEADERBOARD_FILE, JSON.stringify(leaderboard, null, 2), "utf8");
  } catch (err) {
    console.error("Failed to save leaderboard:", err);
  }
}

function sortLeaderboard(list) {
  list.sort((a, b) => {
    const ta = Number(a.time_sec ?? 999999);
    const tb = Number(b.time_sec ?? 999999);
    if (Math.abs(ta - tb) < 0.05) {
      return Number(b.score || 0) - Number(a.score || 0);
    }
    return ta - tb;
  });
}

function readJsonBody(req, maxBytes = 8192) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > maxBytes) {
        reject(new Error("Payload too large"));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => {
      try {
        const text = Buffer.concat(chunks).toString("utf8");
        resolve(JSON.parse(text || "{}"));
      } catch {
        reject(new Error("Invalid JSON"));
      }
    });
    req.on("error", reject);
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

function allocateRoomCode() {
  let candidate = generateRoomCode();
  for (let i = 0; i < 30; i++) {
    if (!rooms.has(candidate)) return candidate;
    candidate = generateRoomCode();
  }
  return candidate;
}

function pruneExpiredRooms() {
  const now = Date.now();
  for (const [code, room] of rooms.entries()) {
    if (now - room.updated_at > ROOM_TTL_MS) {
      for (const sock of room.sockets.values()) {
        try {
          sock.close(4003, "Room expired");
        } catch {}
      }
      rooms.delete(code);
    }
  }
}

setInterval(pruneExpiredRooms, 15_000).unref();

function publicStateView(room) {
  return {
    room_code: room.room_code,
    is_public: Boolean(room.is_public),
    is_mission_active: Boolean(room.is_mission_active),
    mission_idx: Number(room.mission_idx || 0),
    modifier_idx: Number(room.modifier_idx || 0),
    mission_name: String(room.mission_name || ""),
    rocket_id: String(room.rocket_id || ""),
    site_id: String(room.site_id || ""),
    players: room.players,
  };
}

function broadcast(room, payload, excludePeerId = null) {
  const text = JSON.stringify(payload);
  for (const [pid, sock] of room.sockets.entries()) {
    if (excludePeerId !== null && pid === excludePeerId) continue;
    if (sock.readyState === WebSocket.OPEN) {
      try {
        sock.send(text);
      } catch {}
    }
  }
}

function reindexRoles(room) {
  for (let i = 0; i < room.players.length; i++) {
    room.players[i].role = ROLES[i] || "Mürettebat";
  }
}

function pickColorIdx(room) {
  const used = new Set(room.players.map((p) => Number(p.color_idx)));
  for (let c = 0; c < 4; c++) {
    if (!used.has(c)) return c;
  }
  return room.players.length % 4;
}

function dedupeTag(room, rawTag) {
  let base = String(rawTag || "Astronot#1000").trim();
  if (!base) base = "Astronot#1000";
  const existing = new Set(room.players.map((p) => String(p.tag || "").toLowerCase()));
  if (!existing.has(base.toLowerCase())) return base;
  let n = 2;
  while (existing.has(`${base}_${n}`.toLowerCase())) {
    n++;
  }
  return `${base}_${n}`;
}

function sendJson(res, status, data) {
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    ...CORS_HEADERS,
  });
  res.end(JSON.stringify(data));
}

const server = http.createServer(async (req, res) => {
  if (req.method === "OPTIONS") {
    res.writeHead(204, CORS_HEADERS);
    res.end();
    return;
  }

  const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);

  if (url.pathname === "/health" || url.pathname === "/") {
    sendJson(res, 200, {
      ok: true,
      service: "station13-multiplayer",
      runtime: "node",
      active_rooms: rooms.size,
    });
    return;
  }

  if (url.pathname === "/api/rooms" && req.method === "GET") {
    pruneExpiredRooms();
    const q = (url.searchParams.get("q") || "").trim().toLowerCase();
    const out = [];
    for (const room of rooms.values()) {
      if (!room.is_public || room.is_mission_active) continue;
      if (room.players.length <= 0 || room.players.length >= MAX_PLAYERS) continue;
      const hostPlayer = room.players.find((p) => p.is_host) || room.players[0];
      const entry = {
        room_code: room.room_code,
        is_public: 1,
        is_mission_active: 0,
        host_name: hostPlayer ? hostPlayer.tag : "Host",
        mission_name: room.mission_name || "",
        player_count: room.players.length,
        max_players: MAX_PLAYERS,
        updated_at: room.updated_at,
      };
      if (q) {
        const hay = `${entry.room_code} ${entry.host_name} ${entry.mission_name}`.toLowerCase();
        if (!hay.includes(q)) continue;
      }
      out.push(entry);
    }
    out.sort((a, b) => b.updated_at - a.updated_at);
    sendJson(res, 200, { ok: true, rooms: out.slice(0, 50) });
    return;
  }

  if (url.pathname === "/api/leaderboard" && req.method === "GET") {
    const missionId = (url.searchParams.get("mission_id") || "").trim();
    sortLeaderboard(leaderboard);
    const filtered = missionId
      ? leaderboard.filter((r) => String(r.mission_id || "") === missionId)
      : leaderboard;
    sendJson(res, 200, { ok: true, records: filtered.slice(0, 100) });
    return;
  }

  if (url.pathname === "/api/leaderboard" && req.method === "POST") {
    try {
      const body = await readJsonBody(req);
      const missionId = String(body.mission_id || "").trim().slice(0, 64);
      const team = String(body.team || "").trim().slice(0, 80);
      const hostTag = String(body.host_tag || "").trim().slice(0, 64);
      const playerCount = Math.max(1, Math.min(4, Number(body.player_count || 1) || 1));
      const timeSec = Math.round(Number(body.time_sec) * 10) / 10;
      const score = Math.max(0, Math.round(Number(body.score || 0)));

      if (!missionId || !team || !Number.isFinite(timeSec) || timeSec <= 0) {
        sendJson(res, 400, { ok: false, error: "Invalid leaderboard record" });
        return;
      }

      const duplicate = leaderboard.find(
        (r) =>
          r.mission_id === missionId &&
          r.team === team &&
          Math.abs(Number(r.time_sec) - timeSec) < 0.05 &&
          Number(r.score) === score
      );

      if (!duplicate) {
        const record = {
          mission_id: missionId,
          team,
          host_tag: hostTag,
          player_count: playerCount,
          time_sec: timeSec,
          score,
          created_at: Date.now(),
        };
        leaderboard.push(record);
        sortLeaderboard(leaderboard);
        if (leaderboard.length > MAX_LEADERBOARD_RECORDS) {
          leaderboard = leaderboard.slice(0, MAX_LEADERBOARD_RECORDS);
        }
        saveLeaderboard();
        sendJson(res, 201, { ok: true, record, records: leaderboard.slice(0, 100) });
        return;
      }

      sortLeaderboard(leaderboard);
      sendJson(res, 200, { ok: true, record: duplicate, records: leaderboard.slice(0, 100) });
    } catch (err) {
      sendJson(res, 400, { ok: false, error: err.message || "Bad request" });
    }
    return;
  }

  sendJson(res, 404, { ok: false, error: "Not found" });
});

const wss = new WebSocketServer({ noServer: true });

server.on("upgrade", (req, socket, head) => {
  const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
  if (url.pathname !== "/ws") {
    socket.destroy();
    return;
  }
  wss.handleUpgrade(req, socket, head, (ws) => {
    wss.emit("connection", ws, req, url);
  });
});

function rejectWs(ws, message, code = 4000) {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: "join_error", message }));
  }
  ws.close(code, message);
}

function handleDisconnect(ws) {
  const meta = ws._meta;
  if (!meta) return;
  ws._meta = null;

  const room = rooms.get(meta.room_code);
  if (!room) return;

  room.sockets.delete(meta.peer_id);

  if (meta.is_host) {
    broadcast(room, { type: "room_closed", reason: "Host bağlantıyı kapattı." }, meta.peer_id);
    for (const sock of room.sockets.values()) {
      try {
        sock.close(4002, "Host disconnected");
      } catch {}
    }
    rooms.delete(meta.room_code);
    return;
  }

  room.players = room.players.filter((p) => p.peer_id !== meta.peer_id);
  reindexRoles(room);

  if (room.players.length === 0) {
    rooms.delete(meta.room_code);
    return;
  }

  room.updated_at = Date.now();
  broadcast(room, { type: "peer_left", peer_id: meta.peer_id });
  broadcast(room, { type: "lobby_state", state: publicStateView(room) });
}

wss.on("connection", (ws, _req, url) => {
  const action = (url.searchParams.get("action") || "").toLowerCase();

  if (action === "create") {
    const roomCode = allocateRoomCode();
    const isPublic = url.searchParams.get("public") === "true";
    const hostTag = url.searchParams.get("tag") || "Commander#1000";
    const missionIdx = Number(url.searchParams.get("mission_idx") || 0);
    const modifierIdx = Number(url.searchParams.get("modifier_idx") || 0);
    const missionName = url.searchParams.get("mission_name") || "";
    const rocketId = url.searchParams.get("rocket_id") || "";
    const siteId = url.searchParams.get("site_id") || "";

    const room = {
      room_code: roomCode,
      is_public: isPublic,
      is_mission_active: false,
      mission_idx: missionIdx,
      modifier_idx: modifierIdx,
      mission_name: missionName,
      rocket_id: rocketId,
      site_id: siteId,
      next_peer_id: 2,
      updated_at: Date.now(),
      players: [
        {
          peer_id: 1,
          tag: hostTag,
          color_idx: 0,
          is_host: true,
          role: ROLES[0],
        },
      ],
      sockets: new Map([[1, ws]]),
    };

    rooms.set(roomCode, room);
    ws._meta = { room_code: roomCode, peer_id: 1, is_host: true };

    ws.send(
      JSON.stringify({
        type: "room_created",
        peer_id: 1,
        room_code: roomCode,
        state: publicStateView(room),
      })
    );
  } else if (action === "join") {
    const rawCode = (url.searchParams.get("code") || "").trim().toUpperCase();
    if (!rawCode) {
      rejectWs(ws, "Lütfen geçerli bir Oda Kodu girin (örn: KZM-47)!");
      return;
    }
    const room = rooms.get(rawCode);
    if (!room) {
      rejectWs(ws, `HATA: '${rawCode}' kodlu açık bir oda bulunamadı!`, 4004);
      return;
    }
    if (room.is_mission_active) {
      rejectWs(ws, `HATA: '${rawCode}' odasında görev zaten başlamış!`, 4009);
      return;
    }
    if (room.players.length >= MAX_PLAYERS) {
      rejectWs(ws, `HATA: '${rawCode}' odası tamamen dolu (4/4)!`, 4009);
      return;
    }

    const peerId = room.next_peer_id++;
    const uniqueTag = dedupeTag(room, url.searchParams.get("tag") || "Astronot#1000");
    const colorIdx = pickColorIdx(room);
    const role = ROLES[room.players.length] || "Mürettebat";

    room.players.push({
      peer_id: peerId,
      tag: uniqueTag,
      color_idx: colorIdx,
      is_host: false,
      role,
    });
    room.sockets.set(peerId, ws);
    room.updated_at = Date.now();
    ws._meta = { room_code: rawCode, peer_id: peerId, is_host: false };

    const view = publicStateView(room);
    ws.send(
      JSON.stringify({
        type: "room_joined",
        peer_id: peerId,
        room_code: rawCode,
        state: view,
      })
    );
    broadcast(room, { type: "lobby_state", state: view }, peerId);
  } else {
    rejectWs(ws, "Geçersiz bağlantı isteği.");
    return;
  }

  ws.on("message", (raw) => {
    const meta = ws._meta;
    if (!meta) return;
    const room = rooms.get(meta.room_code);
    if (!room) return;

    let msg;
    try {
      msg = JSON.parse(raw.toString("utf8"));
    } catch {
      return;
    }
    if (!msg || typeof msg !== "object") return;

    room.updated_at = Date.now();

    switch (msg.type) {
      case "ping":
        ws.send(JSON.stringify({ type: "pong" }));
        break;

      case "update_lobby":
        if (!meta.is_host) return;
        if (typeof msg.is_public === "boolean") room.is_public = msg.is_public;
        if (typeof msg.mission_idx === "number") room.mission_idx = msg.mission_idx;
        if (typeof msg.modifier_idx === "number") room.modifier_idx = msg.modifier_idx;
        if (typeof msg.mission_name === "string") room.mission_name = msg.mission_name;
        if (typeof msg.rocket_id === "string") room.rocket_id = msg.rocket_id;
        if (typeof msg.site_id === "string") room.site_id = msg.site_id;
        if (typeof msg.host_tag === "string" && msg.host_tag.trim() !== "") {
          const hp = room.players.find((p) => p.peer_id === meta.peer_id);
          if (hp) hp.tag = msg.host_tag.trim();
        }
        broadcast(room, { type: "lobby_state", state: publicStateView(room) });
        break;

      case "set_color": {
        const reqColor = Number(msg.color_idx);
        if (Number.isNaN(reqColor) || reqColor < 0 || reqColor > 3) return;
        const taken = room.players.some(
          (p) => p.peer_id !== meta.peer_id && Number(p.color_idx) === reqColor
        );
        if (taken) return;
        const me = room.players.find((p) => p.peer_id === meta.peer_id);
        if (!me) return;
        me.color_idx = reqColor;
        broadcast(room, { type: "lobby_state", state: publicStateView(room) });
        break;
      }

      case "start_mission":
        if (!meta.is_host) return;
        room.is_mission_active = true;
        if (typeof msg.mission_idx === "number") room.mission_idx = msg.mission_idx;
        if (typeof msg.modifier_idx === "number") room.modifier_idx = msg.modifier_idx;
        if (typeof msg.mission_name === "string") room.mission_name = msg.mission_name;
        if (typeof msg.rocket_id === "string") room.rocket_id = msg.rocket_id;
        if (typeof msg.site_id === "string") room.site_id = msg.site_id;
        broadcast(room, { type: "mission_started", state: publicStateView(room) }, meta.peer_id);
        break;

      case "return_to_lobby":
        if (!meta.is_host) return;
        room.is_mission_active = false;
        broadcast(room, { type: "return_to_lobby", state: publicStateView(room) }, meta.peer_id);
        break;

      case "relay":
        broadcast(
          room,
          {
            type: "relay",
            event: String(msg.event || ""),
            data: msg.data && typeof msg.data === "object" ? msg.data : {},
            from_peer_id: meta.peer_id,
          },
          msg.include_self ? null : meta.peer_id
        );
        break;

      case "leave":
        handleDisconnect(ws);
        try {
          ws.close(1000, "Client left");
        } catch {}
        break;
    }
  });

  ws.on("close", () => handleDisconnect(ws));
  ws.on("error", () => handleDisconnect(ws));
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`Station 13 Node multiplayer server listening on port ${PORT}`);
});
