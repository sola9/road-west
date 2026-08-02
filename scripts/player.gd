extends CharacterBody3D


@export var movement_speed: float = 30.0
@export var sprint_multiplier: float = 3.0
@export var mouse_sensitivity: float = 0.002

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	up_direction = Vector3.UP
	floor_max_angle = deg_to_rad(60.0)
	floor_snap_length = 0.3


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)

		camera.rotation.x -= event.relative.y * mouse_sensitivity
		camera.rotation.x = clampf(
			camera.rotation.x,
			-deg_to_rad(89.0),
			deg_to_rad(89.0)
		)

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	var input_vector := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)

	var direction := (
		global_transform.basis.x * input_vector.x
		+ global_transform.basis.z * input_vector.y
	)

	direction.y = 0.0
	direction = direction.normalized()

	var speed := movement_speed

	if Input.is_action_pressed("sprint"):
		speed *= sprint_multiplier

	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	if not is_on_floor():
		velocity.y -= 30.0 * delta
	else:
		velocity.y = 0.0

	move_and_slide()
