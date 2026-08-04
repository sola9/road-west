extends CanvasLayer


@onready var pause_panel: Control = $PausePanel
@onready var resume_button: Button = \
	$PausePanel/CenterContainer/PanelContainer/VBoxContainer/ResumeButton


func _ready() -> void:
	# This node must keep receiving input while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS

	pause_panel.hide()

	# Make sure gameplay begins unpaused with the mouse captured.
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not event.is_echo():
		toggle_pause()

		# Prevent the Escape press from also reaching other input systems.
		get_viewport().set_input_as_handled()


func toggle_pause() -> void:
	set_paused(not get_tree().paused)


func set_paused(should_pause: bool) -> void:
	if should_pause:
		pause_panel.show()
		get_tree().paused = true

		# Make the cursor visible and allow it to move freely.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

		# Useful for keyboard and controller navigation.
		resume_button.grab_focus()
	else:
		pause_panel.hide()
		get_tree().paused = false

		# Hide and recenter the cursor for gameplay.
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_resume_button_pressed() -> void:
	set_paused(false)

func _on_quit_button_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()
