## XR rig: headset tracking, controller rays, and hand-tracking fallback.
##
## Both controller rays and hand pinch are wired to the same grab action, so the app is
## usable whichever input the headset reports. Tracking failures degrade instead of
## dying: the debug camera keeps the app explorable on a flat screen too.
extends Node3D

const GRAB_ACTION := "grab"
const PINCH_ACTION := "pinch"

var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var left_hand: XRController3D
var right_hand: XRController3D
var left_ray: RayCast3D
var right_ray: RayCast3D
var flat_camera: Camera3D
var xr_active := false

func _ready() -> void:
	_build()
	xr_active = _start_xr()

func _build() -> void:
	xr_origin = XROrigin3D.new()
	xr_origin.name = "XROrigin"
	add_child(xr_origin)

	xr_camera = XRCamera3D.new()
	xr_camera.name = "XRCamera"
	xr_camera.position = Vector3(0, 1.6, 0)
	xr_origin.add_child(xr_camera)

	left_hand = _make_controller("LeftHand", Vector3(-0.25, 1.1, -0.35))
	right_hand = _make_controller("RightHand", Vector3(0.25, 1.1, -0.35))
	left_ray = _make_ray(left_hand)
	right_ray = _make_ray(right_hand)

	flat_camera = Camera3D.new()
	flat_camera.name = "FlatCamera"
	# Framed on the bench: close enough to read the board, high enough to see the layout.
	flat_camera.position = Vector3(0, 1.50, 0.55)
	flat_camera.rotation_degrees = Vector3(-40, 0, 0)
	flat_camera.fov = 60
	add_child(flat_camera)

func _make_controller(node_name: String, pos: Vector3) -> XRController3D:
	var c := XRController3D.new()
	c.name = node_name
	c.tracker = "left_hand" if node_name.begins_with("Left") else "right_hand"
	c.position = pos
	xr_origin.add_child(c)
	return c

## A short forward ray from each hand: the pointer for snapping wires and pressing
## buttons, with the tip drawn so the user can see where it lands.
func _make_ray(parent: XRController3D) -> RayCast3D:
	var ray := RayCast3D.new()
	ray.name = "Ray"
	ray.target_position = Vector3(0, 0, -2.5)
	ray.collide_with_areas = true
	ray.collide_with_bodies = true
	parent.add_child(ray)

	var tip := MeshInstance3D.new()
	tip.name = "Tip"
	var sphere := SphereMesh.new()
	sphere.radius = 0.008
	sphere.height = 0.016
	tip.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.9, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.5, 0.35)
	tip.material_override = mat
	ray.add_child(tip)
	return ray

func _start_xr() -> bool:
	var xr := XRServer.find_interface("OpenXR")
	if xr == null or not xr.is_initialized():
		push_warning("OpenXR unavailable; running in flat mode")
		flat_camera.current = true
		return false
	get_viewport().use_xr = true
	# Keep the flat camera behind the XR one when XR is live.
	flat_camera.current = false
	xr_camera.current = true
	return true

func left_raycast() -> RayCast3D:
	return left_ray

func right_raycast() -> RayCast3D:
	return right_ray

func primary_ray() -> RayCast3D:
	return right_ray
