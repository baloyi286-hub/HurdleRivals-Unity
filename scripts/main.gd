extends Node

const FINISH_Z := 245.0
const RUN_SPEED := 8.0
const STEER_SPEED := 5.0
const GRAVITY := 20.0
const JUMP_SPEED := 8.0

var racers: Array[Node3D] = []
var cameras: Array[Camera3D] = []
var velocities := [0.0, 0.0]
var stun_until := [0.0, 0.0]
var push_cooldown := [0.0, 0.0]
var obstacle_last := [-100.0, -100.0]
var winner := -1
var race_started := false
var hud: Label
var finish_label: Label
var net_server := TCPServer.new()
var peers: Dictionary = {}
var websocket_peers: Dictionary = {}
var http_peers: Dictionary = {}
var port := 8765
var local_ip := "127.0.0.1"

func _ready() -> void:
    _build_world()
    _build_hud()
    _start_server()
    race_started = true

func _build_world() -> void:
    var viewport_width := 1920
    for i in range(2):
        var viewport := SubViewport.new()
        viewport.name = "PlayerViewport%d" % i
        viewport.size = Vector2i(960, 1080)
        viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
        viewport.world_3d = World3D.new()
        add_child(viewport)
        var container := SubViewportContainer.new()
        container.name = "PlayerScreen%d" % i
        container.stretch = true
        container.mouse_filter = Control.MOUSE_FILTER_IGNORE
        container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        container.anchor_left = float(i) * 0.5
        container.anchor_right = float(i + 1) * 0.5
        container.offset_left = 0
        container.offset_right = 0
        add_child(container)
        reparent_viewport(viewport, container)
        var world := Node3D.new()
        viewport.add_child(world)
        _add_mesh(world, "Track", Vector3(0, -0.2, 125), Vector3(13, 0.3, 270), Color(0.19, 0.61, 0.33))
        for z in range(14, 240, 14):
            _add_mesh(world, "Hurdle", Vector3(0, 0.7, z), Vector3(10, 1.4, 0.3), Color(1, 0.76, 0.14))
        _add_mesh(world, "Finish", Vector3(0, 0.04, FINISH_Z), Vector3(13, 0.1, 1), Color.WHITE)
        var runner := Node3D.new()
        runner.name = "Player%d" % (i + 1)
        runner.position = Vector3(-1.6 if i == 0 else 1.6, 1, 0)
        world.add_child(runner)
        _add_mesh(runner, "Runner", Vector3.ZERO, Vector3(1.1, 2, 0.9), Color(0.2, 0.83, 0.95) if i == 0 else Color(1, 0.3, 0.25))
        racers.append(runner)
        var camera := Camera3D.new()
        camera.current = true
        camera.fov = 70
        world.add_child(camera)
        cameras.append(camera)
        var light := DirectionalLight3D.new()
        light.rotation_degrees = Vector3(-45, -25, 0)
        world.add_child(light)
        var environment := WorldEnvironment.new()
        var env := Environment.new()
        env.background_mode = Environment.BG_COLOR
        env.background_color = Color(0.53, 0.79, 0.94)
        env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
        env.ambient_light_color = Color.WHITE
        environment.environment = env
        world.add_child(environment)

func reparent_viewport(viewport: SubViewport, container: SubViewportContainer) -> void:
    viewport.reparent(container)

func _add_mesh(parent: Node, title: String, pos: Vector3, size: Vector3, tint: Color) -> void:
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.name = title
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh_instance.mesh = mesh
    var material := StandardMaterial3D.new()
    material.albedo_color = tint
    mesh_instance.material_override = material
    mesh_instance.position = pos
    parent.add_child(mesh_instance)

func _build_hud() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    hud = Label.new()
    hud.position = Vector2(24, 18)
    hud.add_theme_font_size_override("font_size", 28)
    hud.text = "HURDLE RIVALS  |  P1 WASD  |  P2 ARROWS"
    layer.add_child(hud)
    finish_label = Label.new()
    finish_label.position = Vector2(780, 120)
    finish_label.add_theme_font_size_override("font_size", 52)
    layer.add_child(finish_label)

func _process(delta: float) -> void:
    _poll_network()
    if not race_started:
        return
    for i in range(2):
        var runner := racers[i]
        if winner < 0 and Time.get_ticks_msec() / 1000.0 >= stun_until[i]:
            var steering := Input.get_axis("p%d_left" % (i + 1), "p%d_right" % (i + 1))
            steering += float(peers.get(i, {}).get("steer", 0))
            steering = clampf(steering, -1, 1)
            if _action_pressed(i, "jump") and runner.position.y <= 1.01:
                velocities[i] = JUMP_SPEED
            velocities[i] -= GRAVITY * delta
            runner.position.y = maxf(1.0, runner.position.y + velocities[i] * delta)
            if runner.position.y <= 1:
                velocities[i] = 0
            runner.position.x = clampf(runner.position.x + steering * STEER_SPEED * delta, -5, 5)
            runner.position.z += RUN_SPEED * delta
            if _action_pressed(i, "push") and Time.get_ticks_msec() / 1000.0 > push_cooldown[i]:
                push_cooldown[i] = Time.get_ticks_msec() / 1000.0 + 2
                var other := 1 - i
                if runner.position.distance_to(racers[other].position) < 2.5:
                    stun_until[other] = Time.get_ticks_msec() / 1000.0 + 1.2
            var nearest := roundf((runner.position.z - 14) / 14) * 14 + 14
            if absf(nearest - runner.position.z) < 0.28 and absf(nearest - obstacle_last[i]) > 1 and runner.position.y < 2.4:
                obstacle_last[i] = nearest
                stun_until[i] = Time.get_ticks_msec() / 1000.0 + 1.1
            if runner.position.z >= FINISH_Z:
                winner = i
                finish_label.text = "PLAYER %d WINS!" % (i + 1)
        cameras[i].position = runner.position + Vector3(0, 4.4, -8)
        cameras[i].look_at(runner.position + Vector3.FORWARD * -9, Vector3.UP)
    if winner >= 0 and Input.is_key_pressed(KEY_ENTER):
        get_tree().reload_current_scene()

func _action_pressed(i: int, action: String) -> bool:
    var pressed := Input.is_action_just_pressed("p%d_%s" % [i + 1, action])
    if bool(peers.get(i, {}).get(action, false)):
        peers[i][action] = false
        return true
    return pressed

func _start_server() -> void:
    for address in IP.get_local_addresses():
        if address.begins_with("192.168.") or address.begins_with("10."):
            local_ip = address
            break
    var err := net_server.listen(port, "0.0.0.0")
    if err == OK:
        hud.text = "HURDLE RIVALS | Phones: http://%s:%d" % [local_ip, port]
    else:
        hud.text = "HURDLE RIVALS | Local controller server unavailable (%d)" % err

func _poll_network() -> void:
    if net_server.is_connection_available():
        var peer := net_server.take_connection()
        http_peers[peer.get_instance_id()] = {"stream": peer, "buffer": ""}
    for id in http_peers.keys():
        var entry: Dictionary = http_peers[id]
        var stream: StreamPeerTCP = entry["stream"]
        stream.poll()
        if stream.get_status() != StreamPeerTCP.STATUS_CONNECTED:
            http_peers.erase(id)
            continue
        var available := stream.get_available_bytes()
        if available <= 0:
            continue
        var data := stream.get_utf8_string(available)
        entry["buffer"] += data
        if "\r\n\r\n" not in entry["buffer"]:
            continue
        var request: String = entry["buffer"]
        var first_line := request.split("\r\n")[0]
        var path := first_line.split(" ")[1] if first_line.split(" ").size() > 1 else "/"
        var response := ""
        var content_type := "text/plain"
        if path.begins_with("/input?"):
            var query := path.get_slice("?", 1)
            var params := {}
            for item in query.split("&"):
                params[item.get_slice("=", 0)] = item.get_slice("=", 1)
            var player := clampi(int(params.get("p", "1")) - 1, 0, 1)
            if not peers.has(player):
                peers[player] = {}
            if params.has("steer"):
                peers[player]["steer"] = int(params["steer"])
            if params.has("jump"):
                peers[player]["jump"] = true
            if params.has("push"):
                peers[player]["push"] = true
            response = "OK"
        else:
            content_type = "text/html"
            response = _controller_page()
        var bytes := response.to_utf8_buffer()
        var header := ("HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %d\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n" % [content_type, bytes.size()]).to_utf8_buffer()
        stream.put_data(header + bytes)
        stream.disconnect_from_host()
        http_peers.erase(id)

func _controller_page() -> String:
    return """<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no"><style>body{background:#173b27;color:white;font-family:sans-serif;text-align:center}button{font-size:25px;padding:25px;margin:8px;border-radius:18px;background:#a4e66d;border:0}select{font-size:22px}</style></head><body><h1>Hurdle Rivals</h1><p>Select player</p><select id="p"><option value="1">Player 1</option><option value="2">Player 2</option></select><div><button onpointerdown="send('steer=-1')" onpointerup="send('steer=0')">◀</button><button onpointerdown="send('steer=1')" onpointerup="send('steer=0')">▶</button></div><div><button onclick="send('jump=1')">JUMP</button><button onclick="send('push=1')">PUSH</button></div><script>function send(v){fetch('/input?p='+document.getElementById('p').value+'&'+v).catch(()=>{})}</script></body></html>"""
