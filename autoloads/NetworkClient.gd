extends Node

const CONFIG_PATH: String = "res://data/network_config.json"
const FALLBACK_SERVER_URL: String = "https://station13-multiplayer.station13.workers.dev"
const CONNECT_TIMEOUT_SEC: float = 45.0
const PING_INTERVAL_SEC: float = 15.0

signal public_rooms_fetched(rooms: Array, error_msg: String)
signal room_created(peer_id: int, room_code: String, state: Dictionary)
signal room_joined(peer_id: int, room_code: String, state: Dictionary)
signal join_failed(error_msg: String)
signal lobby_state_received(state: Dictionary)
signal mission_started_received(state: Dictionary)
signal return_to_lobby_received(state: Dictionary)
signal room_closed_received(reason: String)
signal peer_left_received(peer_id: int)
signal relay_received(event_name: String, data: Dictionary, from_peer_id: int)

var server_url: String = FALLBACK_SERVER_URL
var my_peer_id: int = 0
var is_connected_online: bool = false

var _ws: WebSocketPeer = null
var _http: HTTPRequest = null
var _pending_mode: String = "" # "create" | "join" | ""
var _connect_timer: float = 0.0
var _ping_timer: float = 0.0
var _received_handshake: bool = false
var _last_join_error_msg: String = ""

func _ready() -> void:
	_load_server_url()
	_http = HTTPRequest.new()
	_http.timeout = 45.0
	add_child(_http)
	_http.request_completed.connect(_on_rooms_http_completed)

func _load_server_url() -> void:
	if FileAccess.file_exists(CONFIG_PATH):
		var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
		if file:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				var cfg_url: String = String((parsed as Dictionary).get("server_url", "")).strip_edges()
				if cfg_url != "":
					server_url = cfg_url

	if OS.has_feature("web"):
		var query_override: Variant = JavaScriptBridge.eval(
			"(new URLSearchParams(window.location.search)).get('server') || ''"
		)
		if query_override is String and String(query_override).strip_edges() != "":
			server_url = String(query_override).strip_edges()

	server_url = server_url.trim_suffix("/")

func is_server_configured() -> bool:
	return server_url != "" and not server_url.contains("YOUR_SUBDOMAIN")

func get_http_base_url() -> String:
	return server_url.trim_suffix("/")

func get_ws_base_url() -> String:
	var base: String = get_http_base_url()
	if base.begins_with("https://"):
		return "wss://" + base.substr(8)
	if base.begins_with("http://"):
		return "ws://" + base.substr(7)
	return base

func _process(delta: float) -> void:
	if _ws == null:
		return

	_ws.poll()
	var state: WebSocketPeer.State = _ws.get_ready_state()

	if state == WebSocketPeer.STATE_CONNECTING:
		_connect_timer += delta
		if _connect_timer >= CONNECT_TIMEOUT_SEC:
			var err_msg: String = "Sunucuya bağlanılamadı (zaman aşımı). İnternet bağlantısını kontrol edin."
			_teardown_socket()
			join_failed.emit(err_msg)
		return

	if state == WebSocketPeer.STATE_OPEN:
		if not _received_handshake:
			_connect_timer += delta
			if _connect_timer >= CONNECT_TIMEOUT_SEC:
				var err_msg: String = "Sunucu yanıt vermedi (zaman aşımı)."
				_teardown_socket()
				join_failed.emit(err_msg)
				return

		while _ws.get_available_packet_count() > 0:
			var pkt: PackedByteArray = _ws.get_packet()
			_handle_packet(pkt.get_string_from_utf8())

		if is_connected_online:
			_ping_timer += delta
			if _ping_timer >= PING_INTERVAL_SEC:
				_ping_timer = 0.0
				send_json({"type": "ping"})
		return

	if state == WebSocketPeer.STATE_CLOSED:
		var close_reason: String = _ws.get_close_reason()
		var was_online: bool = is_connected_online
		var was_pending: bool = (_pending_mode != "" and not _received_handshake)
		var saved_err: String = _last_join_error_msg
		_teardown_socket()
		if was_pending:
			var msg: String = saved_err if saved_err != "" else (close_reason if close_reason != "" else "Sunucuya bağlanılamadı.")
			join_failed.emit(msg)
		elif was_online:
			var reason_txt: String = close_reason if close_reason != "" else "Sunucu bağlantısı kesildi."
			room_closed_received.emit(reason_txt)

func _handle_packet(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return
	var msg: Dictionary = parsed
	var mtype: String = String(msg.get("type", ""))

	match mtype:
		"room_created":
			_received_handshake = true
			_pending_mode = ""
			is_connected_online = true
			my_peer_id = int(msg.get("peer_id", 1))
			_ping_timer = 0.0
			room_created.emit(my_peer_id, String(msg.get("room_code", "")), msg.get("state", {}))
		"room_joined":
			_received_handshake = true
			_pending_mode = ""
			is_connected_online = true
			my_peer_id = int(msg.get("peer_id", 2))
			_ping_timer = 0.0
			room_joined.emit(my_peer_id, String(msg.get("room_code", "")), msg.get("state", {}))
		"join_error":
			_last_join_error_msg = String(msg.get("message", "Odaya katılınamadı."))
		"lobby_state":
			lobby_state_received.emit(msg.get("state", {}))
		"mission_started":
			mission_started_received.emit(msg.get("state", {}))
		"return_to_lobby":
			return_to_lobby_received.emit(msg.get("state", {}))
		"room_closed":
			var reason: String = String(msg.get("reason", "Oda kapatıldı."))
			_teardown_socket()
			room_closed_received.emit(reason)
		"peer_left":
			peer_left_received.emit(int(msg.get("peer_id", 0)))
		"relay":
			relay_received.emit(
				String(msg.get("event", "")),
				msg.get("data", {}) if msg.get("data") is Dictionary else {},
				int(msg.get("from_peer_id", 0))
			)

func fetch_public_rooms(filter_text: String = "") -> void:
	if not is_server_configured():
		public_rooms_fetched.emit([], "Çevrimiçi sunucu henüz yapılandırılmadı (data/network_config.json).")
		return
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_http.cancel_request()
	var url: String = "%s/api/rooms?q=%s" % [get_http_base_url(), filter_text.strip_edges().uri_encode()]
	var err: Error = _http.request(url)
	if err != OK:
		public_rooms_fetched.emit([], "Açık odalar listesi alınamadı (HTTP Hata %d)." % err)

func _on_rooms_http_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		public_rooms_fetched.emit([], "Sunucuya ulaşılamadı (Kod %d)." % response_code)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		public_rooms_fetched.emit([], "Sunucu yanıtı okunamadı.")
		return
	var rooms: Array = (parsed as Dictionary).get("rooms", [])
	public_rooms_fetched.emit(rooms, "")

func create_room(
	public_room: bool,
	host_tag: String,
	mission_idx: int,
	modifier_idx: int,
	mission_name: String,
	rocket_id: String,
	site_id: String
) -> void:
	if not is_server_configured():
		join_failed.emit("Çevrimiçi sunucu URL'si ayarlanmadı (data/network_config.json). Tek kişilik için Solo butonunu kullanın.")
		return

	disconnect_from_room()
	_pending_mode = "create"
	_received_handshake = false
	_last_join_error_msg = ""
	_connect_timer = 0.0

	var url: String = "%s/ws?action=create&public=%s&tag=%s&mission_idx=%d&modifier_idx=%d&mission_name=%s&rocket_id=%s&site_id=%s" % [
		get_ws_base_url(),
		"true" if public_room else "false",
		host_tag.uri_encode(),
		mission_idx,
		modifier_idx,
		mission_name.uri_encode(),
		rocket_id.uri_encode(),
		site_id.uri_encode()
	]
	_ws = WebSocketPeer.new()
	var err: Error = _ws.connect_to_url(url)
	if err != OK:
		_teardown_socket()
		join_failed.emit("WebSocket bağlantısı başlatılamadı (Hata %d)." % err)

func join_room(code: String, player_tag: String) -> void:
	var clean_code: String = code.strip_edges().to_upper()
	if clean_code == "":
		join_failed.emit("Lütfen geçerli bir Oda Kodu girin (örn: KZM-47)!")
		return
	if not is_server_configured():
		join_failed.emit("Çevrimiçi sunucu URL'si ayarlanmadı (data/network_config.json).")
		return

	disconnect_from_room()
	_pending_mode = "join"
	_received_handshake = false
	_last_join_error_msg = ""
	_connect_timer = 0.0

	var url: String = "%s/ws?action=join&code=%s&tag=%s" % [
		get_ws_base_url(),
		clean_code.uri_encode(),
		player_tag.uri_encode()
	]
	_ws = WebSocketPeer.new()
	var err: Error = _ws.connect_to_url(url)
	if err != OK:
		_teardown_socket()
		join_failed.emit("WebSocket bağlantısı başlatılamadı (Hata %d)." % err)

func disconnect_from_room() -> void:
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		send_json({"type": "leave"})
		_ws.close(1000, "Leave")
	_teardown_socket()

func _teardown_socket() -> void:
	_ws = null
	_pending_mode = ""
	_received_handshake = false
	_connect_timer = 0.0
	_ping_timer = 0.0
	_last_join_error_msg = ""
	is_connected_online = false
	my_peer_id = 0

func send_json(payload: Dictionary) -> void:
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(payload))

func send_update_lobby(
	public_room: bool,
	mission_idx: int,
	modifier_idx: int,
	mission_name: String,
	rocket_id: String,
	site_id: String,
	host_tag: String
) -> void:
	send_json({
		"type": "update_lobby",
		"is_public": public_room,
		"mission_idx": mission_idx,
		"modifier_idx": modifier_idx,
		"mission_name": mission_name,
		"rocket_id": rocket_id,
		"site_id": site_id,
		"host_tag": host_tag
	})

func send_set_color(color_idx: int) -> void:
	send_json({
		"type": "set_color",
		"color_idx": color_idx
	})

func send_start_mission(
	mission_idx: int,
	modifier_idx: int,
	mission_name: String,
	rocket_id: String,
	site_id: String
) -> void:
	send_json({
		"type": "start_mission",
		"mission_idx": mission_idx,
		"modifier_idx": modifier_idx,
		"mission_name": mission_name,
		"rocket_id": rocket_id,
		"site_id": site_id
	})

func send_return_to_lobby() -> void:
	send_json({"type": "return_to_lobby"})

func send_relay(event_name: String, data: Dictionary = {}, include_self: bool = false) -> void:
	if not is_connected_online:
		return
	send_json({
		"type": "relay",
		"event": event_name,
		"data": data,
		"include_self": include_self
	})
