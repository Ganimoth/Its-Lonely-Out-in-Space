extends CharacterBody2D

@onready var ship_smoke: GPUParticles2D = $"Ship Smoke"
@onready var laser_SFX: AudioStreamPlayer2D = $LaserSFX
@onready var smoke_SFX: AudioStreamPlayer2D = $SmokeSFX
@onready var bump_sfx: AudioStreamPlayer2D = $BumpSFX
@onready var explosion_sfx: AudioStreamPlayer2D = $ExplosionSFX

signal player_died()

const projectile_scene: PackedScene = preload("res://nodes/projectile.tscn")
const explosion_particle_scene: PackedScene = preload("res://particles/explosion_particles.tscn")
const SPEED: int = 20

var momentum: Vector2 = Vector2.ZERO
var respawn_point: Vector2

var fire_rate: float = 0.75
var is_shooting: bool = false
var can_shoot: bool = true
var can_get_hit: bool = true
var is_dead: bool = false
var is_restarting: bool = false
var can_control: bool = true

# Keyboard rotation variables
var rotation_speed: float = 180.0  # degrees per second

func _ready():
	ship_smoke.emitting = false
	ship_smoke.modulate = Color(2, 2, 2)
	respawn_point = global_position
	is_dead = true

func _process(delta):
	if is_dead:
		return
	
	# Handle keyboard rotation
	if Input.is_action_pressed("rotate_left") and can_control:
		rotation_degrees -= rotation_speed * delta
	if Input.is_action_pressed("rotate_right") and can_control:
		rotation_degrees += rotation_speed * delta
		
	if Input.is_action_pressed("attack") and can_shoot and GUI.fuel > 0 and can_control:
		shoot_cooldown()
		var projectile: Area2D = projectile_scene.instantiate()
		projectile.global_position = global_position
		projectile.rotation_degrees = rotation_degrees
		add_sibling(projectile)
		GUI.fuel -= 50
		laser_SFX.play()
	
	if Input.is_action_just_pressed("restart") and not is_restarting and can_control:
		restart()

func shoot_cooldown():
	can_shoot = false
	await get_tree().create_timer(fire_rate).timeout
	can_shoot = true

func _physics_process(delta):
	if is_dead:
		return
	else:
		check_death()
	
	var x_direction: float = Input.get_axis("left", "right")
	var y_direction: float = Input.get_axis("up", "down")
	
	if GUI.fuel > 0 and can_control:
		emit_smoke(x_direction, y_direction)
		if x_direction:
			momentum.x += x_direction * SPEED * delta
		else:
			momentum.x = move_toward(momentum.x, 0, SPEED * delta)
		
		if y_direction:
			momentum.y += y_direction * SPEED * delta
		else:
			momentum.y = move_toward(momentum.y, 0, SPEED * delta)
		
		if x_direction or y_direction:
			GUI.fuel -= 1
			if not smoke_SFX.playing:
				smoke_SFX.pitch_scale = randf_range(0.7, 0.8)
				smoke_SFX.play(randf_range(0, 3))
		else:
			smoke_SFX.stop()
	else:
		ship_smoke.emitting = false
		smoke_SFX.stop()
	
	var collision: KinematicCollision2D = get_last_slide_collision()
	if collision:
		if collision.get_collider().is_in_group("environment") and can_get_hit:
			can_get_hit_cooldown()
			var collision_normal: Vector2 = collision.get_normal()
			velocity -= collision_normal * 200
			collision_normal = -abs(collision_normal)
			if collision_normal.x == 0:
				collision_normal.x = 0.5
			if collision_normal.y == 0:
				collision_normal.y = 0.5
			momentum *= 0.7 * collision_normal
			velocity *= 0.7 * collision_normal
			velocity.y = clamp(velocity.y, -300, 300)
			velocity.x = clamp(velocity.x, -300, 300)
			GUI.hp -= 20
			damage_animation()
			bump_sfx.pitch_scale = randf_range(0.5, 0.8)
			bump_sfx.play()
	
	momentum.y = clamp(momentum.y, -10, 10)
	momentum.x = clamp(momentum.x, -10, 10)
	velocity.y = clamp(velocity.y, -600, 600)
	velocity.x = clamp(velocity.x, -600, 600)
	velocity += momentum
	momentum = momentum.move_toward(Vector2.ZERO, SPEED * 0.2 * delta)
	move_and_slide()

func can_get_hit_cooldown():
	can_get_hit = false
	await get_tree().create_timer(0.1).timeout
	can_get_hit = true

func emit_smoke(x_direction: float, y_direction: float):
	# Who even needs optimized code
	if x_direction == 0 and y_direction > 0:
		ship_smoke.emitting = true
		ship_smoke.global_position = global_position + Vector2(0, -50)
		ship_smoke.rotation_degrees = 270
	elif x_direction > 0 and y_direction > 0:
		ship_smoke.emitting = true
		ship_smoke.global_position = global_position + Vector2(-50, -50)
		ship_smoke.rotation_degrees = 225
	elif x_direction > 0 and y_direction == 0:
		ship_smoke.emitting = true
		ship_smoke.global_position = global_position + Vector2(-50, 0)
		ship_smoke.rotation_degrees = 180
	elif x_direction > 0 and y_direction < 0:
		ship_smoke.emitting = true
		ship_smoke.global_position = global_position + Vector2(-50, 50)
		ship_smoke.rotation_degrees = 135
	elif x_direction == 0 and y_direction < 0:
		ship_smoke.emitting = true
		ship_smoke.global_position = global_position + Vector2(0, 50)
		ship_smoke.rotation_degrees = 90
	elif x_direction < 0 and y_direction < 0:
		ship_smoke.emitting = true
		ship_smoke.global_position = global_position + Vector2(50, 50)
		ship_smoke.rotation_degrees = 45
	elif x_direction < 0 and y_direction == 0:
		ship_smoke.emitting = true
		ship_smoke.global_position = global_position + Vector2(50, 0)
		ship_smoke.rotation_degrees = 0
	elif x_direction < 0 and y_direction > 0:
		ship_smoke.emitting = true
		ship_smoke.global_position = global_position + Vector2(50, -50)
		ship_smoke.rotation_degrees = -45
	else:
		ship_smoke.emitting = false

func check_death():
	if GUI.hp <= 0:
		die()

func die():
	is_dead = true
	%"Player Sprite".hide()
	%"Shadow Sprite".hide()
	spawn_explosion_particles()
	GUI.deaths += 1
	player_died.emit()
	move_and_slide()
	smoke_SFX.stop()
	explosion_sfx.play()
	await get_tree().create_timer(0.75).timeout
	smoke_SFX.stop()
	respawn()

func restart():
	is_restarting = true
	await get_tree().create_timer(0.75).timeout
	if Input.is_action_pressed("restart") and not is_dead:
		die()
	is_restarting = false

func spawn_explosion_particles():
	var explosion_particles: Node2D = explosion_particle_scene.instantiate()
	for particle in explosion_particles.get_children():
		particle.emitting = true
	explosion_particles.global_position = global_position
	add_sibling(explosion_particles)
	await get_tree().create_timer(2).timeout
	explosion_particles.queue_free()

func respawn():
	velocity = Vector2.ZERO
	momentum = Vector2.ZERO
	ship_smoke.emitting = false
	
	var tween: Tween = get_tree().create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	await tween.tween_property(get_tree().get_first_node_in_group("camera"), "global_position", respawn_point, 1).finished
	global_position = respawn_point
	spawn_explosion_particles()
	
	for barrier in get_tree().get_nodes_in_group("barrier"):
		barrier.renew_barrier()
	for enemy in get_tree().get_nodes_in_group("enemy"):
		enemy.respawn_enemy()
	
	await get_tree().create_timer(0.3).timeout
	GUI.fuel = GUI.max_fuel
	GUI.hp = GUI.max_hp
	%"Player Sprite".show()
	%"Shadow Sprite".show()
	is_dead = false

func damage_animation():
	var tween: Tween = get_tree().create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property($Sprites, "modulate", Color("ff8d81"), 0.1)
	tween.tween_property($Sprites, "modulate", Color.WHITE, 1)
