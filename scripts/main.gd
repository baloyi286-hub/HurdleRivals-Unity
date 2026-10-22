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
var race_clock := 0.0
var start_delay := 4.0
var ui_layer: CanvasLayer
var intro_panel: PanelContainer
var status_labels: Array[Label] = []
var runners_visual: Array[Node3D] = []
var legs: Array = []
var arms: Array = []
var dust: Array[GPUParticles3D] = []
var race_hits := [0, 0]
var race_worlds: Array[Node3D] = []
var rival_visuals: Array[Node3D] = []
var fall_started := [-100.0, -100.0]
const FALL_DURATION := 2.6
var player_names := ["JOHN", "MARY"]
var hud: Label
var finish_label: Label
var net_server := TCPServer.new()
var peers: Dictionary = {}
var websocket_peers: Dictionary = {}
var http_peers: Dictionary = {}
var port := 8765
var local_ip := "192.168.0.249"
var start_button_ref: Button
var instructions_label: Label

func _ready() -> void:
    _build_world()
    _build_hud()
    _start_server()
    _update_connection_label()
    race_started = false
    start_button_ref.grab_focus.call_deferred()

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
        race_worlds.append(world)
        _add_mesh(world, "Track", Vector3(0, -0.2, 125), Vector3(18, 0.3, 270), Color(0.98, 0.37, 0.16))
        for lane in range(-5, 7, 2):
            _add_mesh(world, "LaneLine", Vector3(float(lane), -0.035, 125), Vector3(0.08, 0.025, 270), Color(1, 0.97, 0.84))
        _add_mesh(world, "Infield", Vector3(-17, -0.2, 125), Vector3(20, 0.3, 270), Color(0.23, 0.68, 0.27))
        _build_stadium(world)
        for z in range(14, 240, 14):
            for lane_x in [-4.5, -1.5, 1.5, 4.5]:
                _make_hurdle(world, Vector3(lane_x, 0, z))
        _add_mesh(world, "Finish", Vector3(0, 0.04, FINISH_Z), Vector3(13, 0.1, 1), Color.WHITE)
        var runner := Node3D.new()
        runner.name = "Player%d" % (i + 1)
        runner.position = Vector3(-1.6 if i == 0 else 1.6, 1, 0)
        world.add_child(runner)
        _build_runner(runner, i)
        runners_visual.append(runner)
        racers.append(runner)
        var camera := Camera3D.new()
        camera.current = true
        camera.fov = 68
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
    # Each camera renders its own copy of the same two shared racer positions.
    # The simulation uses racers[0] and racers[1] as the authoritative state.
    for i in range(2):
        var rival := Node3D.new()
        rival.name = "RivalRunner"
        race_worlds[i].add_child(rival)
        _build_runner(rival, 1 - i)
        rival_visuals.append(rival)

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

func _sphere(parent: Node3D, title: String, pos: Vector3, scale3: Vector3, color: Color) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    node.name = title
    var mesh := SphereMesh.new()
    mesh.radial_segments = 12
    mesh.rings = 6
    node.mesh = mesh
    node.position = pos
    node.scale = scale3
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = 0.9
    node.material_override = mat
    parent.add_child(node)
    return node

func _build_runner(runner: Node3D, index: int) -> void:
    var skin := Color(0.67, 0.38, 0.23) if index == 0 else Color(0.9, 0.61, 0.4)
    var outfit := Color(0.07, 0.1, 0.13) if index == 0 else Color(0.96, 0.43, 0.16)
    _sphere(runner, "Torso", Vector3(0, 0.05, 0), Vector3(0.5, 0.68, 0.28), outfit)
    _sphere(runner, "Neck", Vector3(0, 0.68, 0), Vector3(0.15, 0.2, 0.15), skin)
    _sphere(runner, "Head", Vector3(0, 1.04, 0), Vector3(0.44, 0.48, 0.4), skin)
    _sphere(runner, "Hair", Vector3(0, 1.37, -0.03), Vector3(0.45, 0.19, 0.42), Color(0.2, 0.12, 0.07) if index == 0 else Color(0.22, 0.15, 0.47))
    var runner_legs := []
    var runner_arms := []
    for side in [-1, 1]:
        var leg_pivot := Node3D.new()
        leg_pivot.position = Vector3(float(side) * 0.23, -0.47, 0)
        runner.add_child(leg_pivot)
        _sphere(leg_pivot, "Leg", Vector3(0, -0.48, 0), Vector3(0.19, 0.55, 0.19), skin)
        _sphere(leg_pivot, "Shoe", Vector3(0, -0.98, 0.13), Vector3(0.22, 0.15, 0.35), Color(0.95, 0.96, 0.98))
        runner_legs.append(leg_pivot)
        var arm_pivot := Node3D.new()
        arm_pivot.position = Vector3(float(side) * 0.53, 0.4, 0)
        runner.add_child(arm_pivot)
        _sphere(arm_pivot, "Arm", Vector3(0, -0.43, 0), Vector3(0.17, 0.47, 0.17), skin)
        runner_arms.append(arm_pivot)
    legs.append(runner_legs)
    arms.append(runner_arms)

func _animate_runner(index: int) -> void:
    var racer_index := index % 2 if index < 2 else 1 - (index - 2)
    var running := winner < 0 and race_clock >= start_delay and Time.get_ticks_msec() / 1000.0 >= stun_until[racer_index]
    var phase := race_clock * 15.0 + float(racer_index) * 1.2
    for side in range(2):
        var direction := 1.0 if side == 0 else -1.0
        legs[index][side].rotation.x = sin(phase) * 0.7 * direction if running else 0.0
        arms[index][side].rotation.x = sin(phase) * 0.7 * -direction if running else 0.0

func _make_hurdle(world: Node3D, position3: Vector3) -> void:
    var hurdle := Node3D.new()
    hurdle.position = position3
    world.add_child(hurdle)
    for side in [-1, 1]:
        _add_mesh(hurdle, "Post", Vector3(float(side) * 0.95, 0.57, 0), Vector3(0.09, 1.14, 0.1), Color(0.1, 0.1, 0.12))
    _add_mesh(hurdle, "TopRail", Vector3(0, 1.14, 0), Vector3(2.05, 0.14, 0.13), Color(0.96, 0.94, 0.85))
    _add_mesh(hurdle, "Stripe", Vector3(0, 1.16, -0.09), Vector3(0.55, 0.12, 0.04), Color(0.1, 0.12, 0.15))

func _build_stadium(world: Node3D) -> void:
    _add_mesh(world, "LeftKerb", Vector3(-9.2, 0.1, 125), Vector3(0.5, 0.55, 270), Color.WHITE)
    _add_mesh(world, "RightKerb", Vector3(9.2, 0.1, 125), Vector3(0.5, 0.55, 270), Color.WHITE)
    for side in [-1, 1]:
        var x := float(side) * 16.0
        _add_mesh(world, "Stands", Vector3(x, 1.3, 125), Vector3(12, 2.4, 270), Color(0.73, 0.75, 0.74))
        for tier in range(4):
            var stand_x := x + float(side) * float(tier) * 1.2
            _add_mesh(world, "Terrace", Vector3(stand_x, 2.5 + float(tier) * 0.75, 125), Vector3(2.4, 0.4, 270), Color(0.81, 0.8, 0.76))
            for j in range(45):
                var z := float(j) * 6.0
                var shirt := Color.from_hsv(float((j * 7 + tier * 3) % 17) / 17.0, 0.65, 0.9)
                _sphere(world, "Spectator", Vector3(stand_x, 3.2 + float(tier) * 0.75, z), Vector3(0.32, 0.45, 0.33), shirt)
                _sphere(world, "SpectatorHead", Vector3(stand_x, 3.78 + float(tier) * 0.75, z), Vector3(0.24, 0.27, 0.24), Color(0.8, 0.55, 0.34))

func _build_hud() -> void:
    ui_layer = CanvasLayer.new()
    add_child(ui_layer)
    var canvas := Control.new()
    canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    ui_layer.add_child(canvas)
    for i in range(2):
        var left := 24.0 if i == 0 else 984.0
        var banner := PanelContainer.new()
        banner.position = Vector2(left, 24)
        banner.custom_minimum_size = Vector2(400, 106)
        var style := StyleBoxFlat.new()
        style.bg_color = Color(0.02, 0.65, 0.83) if i == 0 else Color(0.14, 0.75, 0.25)
        style.corner_radius_top_left = 45
        style.corner_radius_bottom_left = 45
        style.corner_radius_top_right = 14
        style.corner_radius_bottom_right = 14
        style.border_width_bottom = 7
        style.border_color = Color(0.6, 0.04, 0.06) if i == 0 else Color(0.02, 0.36, 0.04)
        banner.add_theme_stylebox_override("panel", style)
        canvas.add_child(banner)
        var name_label := Label.new()
        name_label.text = "   %s    0/2" % player_names[i]
        name_label.add_theme_font_size_override("font_size", 45)
        name_label.add_theme_color_override("font_color", Color.WHITE)
        banner.add_child(name_label)
        var meter := ProgressBar.new()
        meter.position = Vector2(left + 38, 285)
        meter.size = Vector2(38, 400)
        meter.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
        meter.value = 100
        meter.show_percentage = false
        var bg := StyleBoxFlat.new()
        bg.bg_color = Color(0.16, 0.19, 0.2)
        bg.border_color = Color(0.05, 0.05, 0.05)
        bg.set_border_width_all(5)
        bg.set_corner_radius_all(15)
        meter.add_theme_stylebox_override("background", bg)
        var fill := StyleBoxFlat.new()
        fill.bg_color = Color(0.96, 0.8, 0.1)
        fill.set_corner_radius_all(10)
        meter.add_theme_stylebox_override("fill", fill)
        canvas.add_child(meter)
        var status := Label.new()
        status.position = Vector2(left + 180, 150)
        status.add_theme_font_size_override("font_size", 34)
        status.add_theme_color_override("font_color", Color.WHITE)
        canvas.add_child(status)
        status_labels.append(status)
    var separator := ColorRect.new()
    separator.color = Color(0.07, 0.07, 0.1)
    separator.position = Vector2(956, 0)
    separator.size = Vector2(8, 1080)
    canvas.add_child(separator)
    intro_panel = PanelContainer.new()
    intro_panel.position = Vector2(550, 265)
    intro_panel.custom_minimum_size = Vector2(820, 520)
    var panel_style := StyleBoxFlat.new()
    panel_style.bg_color = Color(0.04, 0.14, 0.21, 0.94)
    panel_style.set_corner_radius_all(32)
    panel_style.set_border_width_all(7)
    panel_style.border_color = Color(0.54, 0.92, 0.34)
    intro_panel.add_theme_stylebox_override("panel", panel_style)
    canvas.add_child(intro_panel)
    var layout := VBoxContainer.new()
    layout.add_theme_constant_override("separation", 22)
    intro_panel.add_child(layout)
    var title := Label.new()
    title.text = "HURDLE RIVALS"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 72)
    layout.add_child(title)
    var subtitle := Label.new()
    subtitle.text = "2 PLAYER STADIUM RACE"
    subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    subtitle.add_theme_font_size_override("font_size", 34)
    layout.add_child(subtitle)
    var instructions := Label.new()
    instructions.text = "Connect phones on the same Wi-Fi: http://%s:%d\nChoose Player 1 or Player 2 on your phone\nJump over hurdles • Steer • Push your rival" % [local_ip, port]
    instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    instructions.add_theme_font_size_override("font_size", 26)
    layout.add_child(instructions)
    instructions_label = instructions
    var start_button := Button.new()
    start_button.text = "START RACE"
    start_button.custom_minimum_size = Vector2(500, 100)
    start_button.add_theme_font_size_override("font_size", 42)
    start_button.focus_mode = Control.FOCUS_ALL
    start_button_ref = start_button
    start_button.pressed.connect(_begin_race)
    layout.add_child(start_button)
    finish_label = Label.new()
    finish_label.position = Vector2(675, 200)
    finish_label.add_theme_font_size_override("font_size", 62)
    canvas.add_child(finish_label)

func _begin_race() -> void:
    intro_panel.visible = false
    race_started = true
    winner = -1
    race_clock = 0.0
    for i in range(2):
        racers[i].position = Vector3(-1.5 if i == 0 else 1.5, 1, 0)
        velocities[i] = 0
        stun_until[i] = 0
        race_hits[i] = 0
        obstacle_last[i] = -100.0
        fall_started[i] = -100.0
        peers[i] = {"steer": 0}
    finish_label = ""

func _unhandled_input(event: InputEvent) -> void:
    if not race_started and (event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_select")):
        _begin_race()
        get_viewport().set_input_as_handled()

func _update_connection_label() -> void:
    if instructions_label != null:
        instructions_label.text = "On your phone, open http://%s:%d\nUse the same Wi-Fi network as the TV\nTV remote: press OK to start" % [local_ip, port]

func _process(delta: float) -> void:
    _poll_network()
    if not race_started:
        _sync_rival_views()
        return
    race_clock += delta
    if race_clock < start_delay:
        var countdown := int(ceil(start_delay - race_clock))
        for label in status_labels:
            label.text = str(countdown) if countdown > 1 else "GO!"
        _sync_rival_views()
        return
    var now := Time.get_ticks_msec() / 1000.0
    for i in range(2):
        var runner := racers[i]
        var fallen := now < stun_until[i]
        if winner < 0 and not fallen:
            var steering := Input.get_axis("p%d_left" % (i + 1), "p%d_right" % (i + 1))
            steering += float(peers.get(i, {}).get("steer", 0))
            steering = clampf(steering, -1.0, 1.0)
            if _action_pressed(i, "jump") and runner.position.y <= 1.01:
                velocities[i] = JUMP_SPEED
            velocities[i] -= GRAVITY * delta
            runner.position.y = maxf(1.0, runner.position.y + velocities[i] * delta)
            if runner.position.y <= 1.0:
                velocities[i] = 0.0
            runner.position.x = clampf(runner.position.x + steering * STEER_SPEED * delta, -5.0, 5.0)
            runner.position.z += RUN_SPEED * delta
            if _action_pressed(i, "push") and now > push_cooldown[i]:
                push_cooldown[i] = now + 1.8
                var other := 1 - i
                var separation := runner.position - racers[other].position
                var horizontal_distance := Vector2(separation.x, separation.z).length()
                if horizontal_distance < 2.8 and absf(separation.y) < 1.4 and now >= stun_until[other]:
                    _knock_down(other, now)
            var nearest := roundf(runner.position.z / 14.0) * 14.0
            if nearest >= 14.0 and absf(nearest - runner.position.z) < 0.3 and absf(nearest - obstacle_last[i]) > 1.0:
                obstacle_last[i] = nearest
                # Hurdles occupy four lanes; steering between them is possible.
                var hits_barrier := false
                for lane_x in [-4.5, -1.5, 1.5, 4.5]:
                    if absf(runner.position.x - lane_x) < 1.15:
                        hits_barrier = true
                        break
                if hits_barrier and runner.position.y < 2.15:
                    _knock_down(i, now)
            if runner.position.z >= FINISH_Z:
                winner = i
                finish_label.text = "%s WINS!" % player_names[i]
                intro_panel.visible = true
                start_button_ref.grab_focus.call_deferred()
        elif fallen:
            velocities[i] = 0.0
        _animate_runner(i)
        _pose_fall(runner, i, now)
        cameras[i].position = runner.position + Vector3(0, 3.1, -7.8)
        cameras[i].look_at(runner.position + Vector3(0, 1.25, 10), Vector3.UP)
        status_labels[i].text = "FALLEN! GETTING UP" if fallen else "%dm  •  %d falls" % [maxi(0, int(FINISH_Z - runner.position.z)), race_hits[i]]
    _sync_rival_views()

func _knock_down(index: int, now: float) -> void:
    if now < stun_until[index]:
        return
    fall_started[index] = now
    stun_until[index] = now + FALL_DURATION
    velocities[index] = 0.0
    race_hits[index] += 1

func _pose_fall(runner: Node3D, index: int, now: float) -> void:
    var elapsed := now - fall_started[index]
    if elapsed >= 0.0 and elapsed < FALL_DURATION:
        var down := smoothstep(0.0, 0.25, elapsed) * (1.0 - smoothstep(FALL_DURATION - 0.75, FALL_DURATION, elapsed))
        runner.rotation.z = down * (1.3 if index == 0 else -1.3)
        runner.position.y = 1.0 - down * 0.58
    else:
        runner.rotation.z = 0.0

func _sync_rival_views() -> void:
    for i in range(2):
        var rival_index := 1 - i
        rival_visuals[i].transform = racers[rival_index].transform
        # The rival is animated with the same state as the authoritative runner.
        _animate_runner(i + 2)

func _action_pressed(i: int, action: String) -> bool:
    var pressed := Input.is_action_just_pressed("p%d_%s" % [i + 1, action])
    if bool(peers.get(i, {}).get(action, false)):
        peers[i][action] = false
        return true
    return pressed

func _start_server() -> void:
    for address in IP.get_local_addresses():
        if address == "192.168.0.249":
            local_ip = address
            break
    var err := net_server.listen(port, "0.0.0.0")
    if err != OK:
        push_warning("Phone controller server unavailable: %d" % err)

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
        if path.begins_with("/start"):
            _begin_race()
            response = "STARTED"
        elif path.begins_with("/input?"):
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
    return """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<title>Hurdle Rivals Controller</title>
<style>
*{box-sizing:border-box}body{margin:0;min-height:100dvh;background:radial-gradient(circle at 50% 0%,#246a79,#0c182c 62%);color:#fff;font-family:system-ui,sans-serif;touch-action:manipulation}
main{max-width:600px;margin:auto;padding:20px}h1{text-align:center;font-size:30px;letter-spacing:2px;margin:8px 0}small{color:#c8e7ef}
.status{text-align:center;margin:12px auto 20px;font-weight:700;color:#c0ff76}.panel{border:2px solid #4bcb9b;background:#102c3e;border-radius:22px;padding:18px;margin:16px 0;box-shadow:0 8px 28px #0005}
label{display:block;font-size:15px;margin-bottom:10px;color:#d8f7fc}select{width:100%;padding:15px;border-radius:12px;font-size:20px;background:#fff;color:#10202c}
.controls{display:grid;grid-template-columns:1fr 1fr;gap:14px}.button{border:0;border-radius:22px;color:#fff;font-weight:900;font-size:23px;min-height:110px;box-shadow:inset 0 -7px #0004;touch-action:none;user-select:none;-webkit-user-select:none}
.button:active,.button.active{transform:translateY(3px);filter:brightness(1.25)}.steer{background:#1977b9}.jump{background:#34a947}.push{background:#ec7434}
.start{width:100%;min-height:65px;background:#d3f04d;color:#152d29;font-size:22px}p{text-align:center;color:#c6e1e8;font-size:14px}
</style></head><body><main><h1>🏃 HURDLE RIVALS</h1><div class="status" id="status">● Connected to TV</div>
<section class="panel"><label for="player">CHOOSE YOUR RUNNER</label><select id="player"><option value="1">🔵 JOHN — PLAYER 1</option><option value="2">🟢 MARY — PLAYER 2</option></select></section>
<button class="button start" id="start">▶ START / RESTART RACE</button>
<section class="panel"><label>STEER YOUR RUNNER</label><div class="controls"><button class="button steer" data-steer="-1">◀ LEFT</button><button class="button steer" data-steer="1">RIGHT ▶</button></div></section>
<section class="panel"><label>RACE ACTIONS</label><div class="controls"><button class="button jump" id="jump">⬆ JUMP</button><button class="button push" id="push">💥 PUSH</button></div></section>
<p>Keep this page open while racing. Both phones must use the TV's Wi-Fi network.</p></main>
<script>
const player=document.getElementById('player'),status=document.getElementById('status');
function send(value){fetch('/input?p='+player.value+'&'+value,{cache:'no-store'}).then(r=>{if(!r.ok)throw Error('Offline');status.textContent='● Connected to TV';}).catch(()=>{status.textContent='● Connection lost — retrying';});}
document.querySelectorAll('[data-steer]').forEach(b=>{let dir=b.dataset.steer;
b.addEventListener('pointerdown',e=>{e.preventDefault();b.setPointerCapture(e.pointerId);b.classList.add('active');send('steer='+dir);});
function stop(){b.classList.remove('active');send('steer=0')}
b.addEventListener('pointerup',stop);b.addEventListener('pointercancel',stop);b.addEventListener('lostpointercapture',stop);});
document.getElementById('jump').onclick=()=>send('jump=1');
document.getElementById('push').onclick=()=>send('push=1');
document.getElementById('start').onclick=()=>fetch('/start',{cache:'no-store'}).then(()=>status.textContent='● Race started').catch(()=>status.textContent='● TV unavailable');
</script></body></html>"""
